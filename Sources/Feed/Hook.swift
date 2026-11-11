// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

// The status line hook: the script, kept in the code, installed only on an explicit click, chaining an existing command.
// settings.json is otherwise off limits: this file reads the statusLine key and disableAllHooks, and changes only statusLine.

public enum HookScript {
    /// The script text, identical to hook/statusline.sh in the repository (a test checks that).
    public static let template = """
    #!/bin/sh
    # The status line hook. Copies the feed Claude Code hands it to one file per session, atomically,
    # then hands the same input to the status line command that was configured before, if any.
    # It parses nothing and needs nothing but sh. The app fills in DIR and PREV at install time.
    DIR='__DIR__'
    PREV='__PREV__'
    input=$(cat)
    sid=$(printf '%s' "$input" | sed -n 's/.*"session_id":"\\([0-9a-fA-F-]*\\)".*/\\1/p' | head -n 1)
    mkdir -p "$DIR"
    if [ -n "$sid" ]; then
      printf '%s' "$input" > "$DIR/$sid.json.tmp" && mv -f "$DIR/$sid.json.tmp" "$DIR/$sid.json"
    else
      printf '%s' "$input" > "$DIR/latest.json.tmp" && mv -f "$DIR/latest.json.tmp" "$DIR/latest.json"
    fi
    # files of sessions that stopped writing over a minute ago, the same rule the app uses, so nothing piles up
    # in the folder even when the app is gone
    find "$DIR" -maxdepth 1 -type f \\( -name '*.json' -o -name '*.json.tmp' \\) -mmin +1 -delete 2>/dev/null
    if [ -n "$PREV" ]; then printf '%s' "$input" | sh -c "$PREV"; fi
    exit 0

    """

    /// The script with DIR and PREV filled in, both single quoted for sh: inside single quotes nothing expands, and a single
    /// quote in the text is written as '\'' (close, an escaped quote, open again).
    public static func render(sessionsDir: String, previousCommand: String?) -> String {
        func q(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "'\\''") }
        return template
            .replacingOccurrences(of: "__DIR__", with: q(sessionsDir))
            .replacingOccurrences(of: "__PREV__", with: q(previousCommand ?? ""))
    }
}

public struct HookStatus: Sendable, Equatable {
    public var installed: Bool
    public var previousCommand: String?   // a status line command that is not ours, when one exists
    public var hooksDisabled: Bool        // disableAllHooks is true: Claude Code runs no status line from this file
    /// The user's own refreshInterval when it is longer than 5 s: before install the one Install would lower,
    /// from install the one it lowered, for Remove to put back when the backup file is gone.
    public var slowerRefresh: Double?
    /// settings.json points at our script but the script is gone (a zap, a deleted data folder): not installed, Install puts it back.
    public var scriptMissing: Bool
    /// With several settings folders: installed in at least one of them. Equal to installed for one folder.
    public var anyInstalled: Bool
    /// The settings folders Install writes to, as the user knows them: "~/.claude", "~/.claude-work".
    public var targets: [String]
    public init(installed: Bool, previousCommand: String?, hooksDisabled: Bool = false, slowerRefresh: Double? = nil,
                scriptMissing: Bool = false, anyInstalled: Bool? = nil, targets: [String] = ["~/.claude"]) {
        self.installed = installed; self.previousCommand = previousCommand; self.hooksDisabled = hooksDisabled; self.slowerRefresh = slowerRefresh
        self.scriptMissing = scriptMissing; self.anyInstalled = anyInstalled ?? installed; self.targets = targets
    }
}

public enum HookError: Error, Sendable, CustomStringConvertible {
    case cannotReadSettings(String)
    case cannotWriteSettings(String, cause: (any Error)? = nil)
    case cannotWriteScript(String, cause: (any Error)? = nil)
    case inFolder(String, Error)

    public var description: String {
        switch self {
        case .inFolder(let folder, let e): return folder + ": " + ((e as? HookError)?.description ?? e.localizedDescription)
        case .cannotReadSettings(let m): return "cannot read settings.json: " + m
        case .cannotWriteSettings(let m, _): return "cannot write settings.json: " + m
        case .cannotWriteScript(let m, _): return "cannot write the hook script: " + m
        }
    }

    /// The system error underneath, for the problem report's codes (never its text).
    public var cause: (any Error)? {
        switch self {
        case .inFolder(_, let e): return (e as? HookError)?.cause ?? e
        case .cannotReadSettings: return nil
        case .cannotWriteSettings(_, let c), .cannotWriteScript(_, let c): return c
        }
    }

    /// The same error without the folder it happened in.
    public var inner: HookError? {
        if case .inFolder(_, let e) = self { return (e as? HookError)?.inner } else { return self }
    }
}

public struct Hook: Sendable {
    public let settingsURL: URL
    public let dataDir: URL
    /// nil for ~/.claude, the folder every earlier version used; otherwise a short name of the settings folder, so each
    /// folder has its own script (its own chained command) and its own backup.
    public let id: String?
    public var hookPath: URL { dataDir.appendingPathComponent(id.map { "hook-\($0).sh" } ?? "hook.sh") }
    /// The statusLine object as it was before install, so uninstall can put it back exactly. {} when there was none.
    public var backupPath: URL { dataDir.appendingPathComponent(id.map { "statusline-before-\($0).json" } ?? "statusline-before.json") }
    /// The statusLine command runs in a shell, so the path is single quoted; Application Support has a space in it.
    public var hookCommand: String { "'" + hookPath.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public var sessionsDir: URL { dataDir.appendingPathComponent("sessions", isDirectory: true) }
    public static let refreshInterval = 5

    public init(settingsURL: URL, dataDir: URL, id: String? = nil) { self.settingsURL = settingsURL; self.dataDir = dataDir; self.id = id }

    /// A refreshInterval longer than the hook's own, which Install lowers to 5.
    static func slower(_ statusLine: [String: Any]?) -> Double? {
        guard let n = (statusLine?["refreshInterval"] as? NSNumber)?.doubleValue, n > Double(refreshInterval) else { return nil }
        return n
    }

    func isOurs(_ command: String) -> Bool { command == hookCommand || command == hookPath.path }

    /// Why settings.json could not be read as settings.
    static func unreadable(_ url: URL) -> String {
        guard let size = SafeFile.regularFileSize(url.path) else { return "settings.json is not a regular file" }
        if size > SafeFile.jsonLimit { return "settings.json is over 1 MB" }
        // valid JSON that is not an object (an array, a string) against text that is not JSON at all
        if let data = try? Data(contentsOf: url), (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil {
            return "settings.json is not a JSON object"
        }
        return "settings.json is not valid JSON"
    }

    /// Reads the statusLine key and disableAllHooks, which switches the status line off. Anything else stays unread.
    public func status() -> HookStatus {
        let obj = readSettings()
        let disabled = (obj?["disableAllHooks"] as? Bool) ?? false
        guard let sl = obj?["statusLine"] as? [String: Any], let cmd = sl["command"] as? String else {
            return HookStatus(installed: false, previousCommand: nil, hooksDisabled: disabled)
        }
        if isOurs(cmd) {
            // the entry is ours, but Claude Code would run a script that is not there: say so and offer Install again
            guard FileManager.default.isExecutableFile(atPath: hookPath.path) else {
                return HookStatus(installed: false, previousCommand: nil, hooksDisabled: disabled, scriptMissing: true)
            }
            return HookStatus(installed: true, previousCommand: nil, hooksDisabled: disabled)
        }
        return HookStatus(installed: false, previousCommand: cmd, hooksDisabled: disabled, slowerRefresh: Self.slower(sl))
    }

    /// The modification time of settings.json, so a caller can re-read it only when it changed. nil when it does not exist.
    public func settingsModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: settingsURL.path))?[.modificationDate] as? Date
    }

    func readSettings() -> [String: Any]? { readSettingsText()?.settings }

    /// The file's bytes and what they parse to: the bytes are what Install and Remove edit, member by member.
    func readSettingsText() -> (data: Data, settings: [String: Any])? {
        guard let d = SafeFile.read(settingsURL), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return (d, obj)
    }

    /// The statusLine object saved at install. nil: no backup file. .some(nil): there was no statusLine before.
    func readBackup() -> [String: Any]?? {
        guard let obj = readBackupFile() else { return nil }
        return .some(obj["statusLine"] as? [String: Any])
    }

    func readBackupFile() -> [String: Any]? {
        guard let d = SafeFile.read(backupPath) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// createdSettings: there was no settings.json before install, so Remove deletes the file again when nothing else is in it.
    func writeBackup(_ statusLine: [String: Any]?, createdSettings: Bool = false) throws {
        var obj: [String: Any] = statusLine.map { ["statusLine": $0] } ?? [:]
        if createdSettings { obj["createdSettings"] = true }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: backupPath, options: .atomic)
    }

    /// Writes the script and the statusLine entry. Only ever called from an install row's click.
    /// An existing statusLine keeps its other keys (padding and the like); type and command change, and refreshInterval
    /// is set to 5 when there was none or a longer one: idle sessions must write within the 10 s open rule. Remove puts
    /// the user's own value back from the backup.
    /// previousFallback: the chained command the app kept in its preferences, used when the entry is ours but the backup is gone.
    public func install(previousFallback: String? = nil) throws -> HookStatus {
        let fm = FileManager.default
        // before anything is written: a link into a folder that does not exist fails here, with nothing left behind
        do { _ = try SettingsFile.writableTarget(settingsURL) } catch { throw HookError.cannotWriteSettings(SettingsFile.reason(error), cause: error) }
        var settings: [String: Any] = [:]
        var original: Data? = nil
        let created = !fm.fileExists(atPath: settingsURL.path)
        if !created {
            guard let s = readSettingsText() else { throw HookError.cannotReadSettings(Self.unreadable(settingsURL)) }
            settings = s.settings
            original = s.data
        }
        let existing = settings["statusLine"] as? [String: Any]
        let existingCommand = existing?["command"] as? String
        let alreadyOurs = existingCommand.map(isOurs) ?? false
        // a reinstall chains what was there before the first install, kept in the backup
        let backup = readBackup()
        let before: [String: Any]? = alreadyOurs ? (backup ?? nil) : existing
        var previous = before?["command"] as? String
        if previous == nil, alreadyOurs, backup == nil { previous = previousFallback }
        if let p = previous, isOurs(p) { previous = nil }
        let script = HookScript.render(sessionsDir: sessionsDir.path, previousCommand: previous)
        do {
            try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
            try script.write(to: hookPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath.path)
            if !alreadyOurs { try writeBackup(existing, createdSettings: created) }
        } catch { throw HookError.cannotWriteScript(error.localizedDescription, cause: error) }
        var sl = existing ?? [:]
        sl["type"] = "command"
        sl["command"] = hookCommand
        if let n = (sl["refreshInterval"] as? NSNumber)?.doubleValue, n >= 1, n <= Double(Hook.refreshInterval) {
            // a shorter interval of the user's own stays
        } else {
            sl["refreshInterval"] = Hook.refreshInterval
        }
        settings["statusLine"] = sl
        try writeSettings(settings, original: original)
        return HookStatus(installed: true, previousCommand: previous, slowerRefresh: Self.slower(before))
    }

    /// An installed script from an earlier version brought to the current template, so a change to the script reaches every
    /// install at the next launch, not only at the next Install. DIR is written anew from this Hook's sessions folder (0.1.0
    /// to 0.1.10 quoted it in double quotes); PREV, single quoted in every version, is kept as it is. The file is the app's own:
    /// anything else edited in it is replaced. True when rewritten.
    @discardableResult
    public func refreshScript() -> Bool {
        guard status().installed, let old = try? String(contentsOf: hookPath, encoding: .utf8) else { return false }
        // PREV='...' with '\'' for a quote inside, possibly over several lines
        guard let re = try? NSRegularExpression(pattern: "(?m)^PREV='(?:[^']|'\\\\'')*'$"),
              let m = re.firstMatch(in: old, range: NSRange(old.startIndex..., in: old)),
              let r = Range(m.range, in: old) else { return false }
        let fresh = HookScript.render(sessionsDir: sessionsDir.path, previousCommand: nil)
        let script = fresh.replacingOccurrences(of: "PREV=''", with: String(old[r]))
        guard script != old else { return false }
        do {
            try script.write(to: hookPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath.path)
            return true
        } catch { return false }
    }

    /// Puts the statusLine object back as it was before install, or removes the key when there was none.
    /// Touches settings.json only while the entry is still ours; a statusLine the user changed since stays as it is.
    /// previousCommand and previousRefresh are the fallback when the backup file is missing. The script, the backup and the
    /// sessions folder are removed.
    /// removeSessions: false while another settings folder still feeds the shared sessions folder.
    public func uninstall(previousCommand: String?, previousRefresh: Double? = nil, removeSessions: Bool = true) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsURL.path) {
            guard let text = readSettingsText() else { throw HookError.cannotReadSettings(Self.unreadable(settingsURL)) }
            var settings = text.settings
            let current = settings["statusLine"] as? [String: Any]
            if let cmd = current?["command"] as? String, isOurs(cmd) {
                let created = (readBackupFile()?["createdSettings"] as? Bool) ?? false
                if let backup = readBackup() {
                    if let before = backup { settings["statusLine"] = before } else { settings.removeValue(forKey: "statusLine") }
                } else if let previousCommand, var sl = current {
                    sl["command"] = previousCommand
                    if let r = previousRefresh, r.isFinite {
                        if let whole = Int(exactly: r) { sl["refreshInterval"] = whole } else { sl["refreshInterval"] = r }
                    }
                    settings["statusLine"] = sl
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                if created, settings.isEmpty {
                    // Install made this file and nothing else was added since: it goes, instead of an empty {} left behind.
                    // Through a link (a dotfiles folder whose file did not exist yet) the file Install wrote goes and the
                    // link stays as the user had it; deleting the link left the entry in the file it pointed at (to 0.1.13).
                    let target = (try? SettingsFile.resolve(settingsURL)) ?? settingsURL
                    do { try fm.removeItem(at: target) } catch { throw HookError.cannotWriteSettings(error.localizedDescription, cause: error) }
                } else {
                    try writeSettings(settings, original: text.data)
                }
            }
        }
        if removeSessions { try? fm.removeItem(at: sessionsDir) }
        try? fm.removeItem(at: hookPath)
        try? fm.removeItem(at: backupPath)
    }

    /// Only the statusLine member changes: the file's other bytes stay as they were, key order, number spelling, spacing
    /// and all (0.1.19; until 0.1.18 the system JSON writer wrote the whole file anew, audit F-52). A new file, or one the
    /// member edit cannot place (SettingsText), is written whole by the system writer, pretty printed with slashes
    /// unescaped. A settings.json that is a link (into a dotfiles folder) stays a link: the file it points at is written,
    /// atomically, and keeps its mode; a new file is made owner only.
    func writeSettings(_ settings: [String: Any], original: Data? = nil) throws {
        do {
            let data = try original.flatMap { SettingsText.edit($0, to: settings) }
                ?? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
            try SettingsFile.write(data, to: settingsURL)
        } catch { throw HookError.cannotWriteSettings(SettingsFile.reason(error), cause: error) }
    }
}

/// settings.json changed member by member: a member whose value moved is replaced in place (an object inside it member
/// by member too), a member that went is cut with its comma, a new one is added after the last, in the spacing of the
/// ones before it. Every other byte stays. The result must parse to exactly the settings asked for, or nil is returned
/// and the caller writes the file whole: a duplicate key, a member removed and added in one object, or anything the
/// scanner does not follow. A leading byte order mark stays, and what is inserted takes the file's line ending (CRLF when
/// its first line break is one) and the key to value spacing of the members beside it (second review of 0.1.19: the BOM
/// made the whole file be written anew, and inserted values came with LF and the system writer's "key" : value).
public enum SettingsText {
    struct Member { var key: String; var keyStart: Int; var keyEnd: Int; var valueStart: Int; var valueEnd: Int }
    struct Object { var open: Int; var close: Int; var members: [Member] }
    struct Change { var range: Range<Int>; var bytes: [UInt8] }
    /// How the file spells what is inserted: its line break and its key to value spacing.
    struct Style { var newline: String; var colon: String = ": " }

    static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// CRLF when the file's first line break is one, else LF.
    static func newline(_ b: [UInt8]) -> String {
        guard let i = b.firstIndex(of: 0x0a) else { return "\n" }
        return i > 0 && b[i - 1] == 0x0d ? "\r\n" : "\n"
    }

    /// A member's key to value spacing ("": "", " : "), unless it spans a line break: then the usual ": ".
    static func colon(_ b: [UInt8], _ m: Member) -> String {
        let c = b[m.keyEnd..<m.valueStart]
        return c.contains(0x0a) || c.contains(0x0d) ? ": " : String(decoding: c, as: UTF8.self)
    }

    public static func edit(_ data: Data, to target: [String: Any]) -> Data? {
        let b = [UInt8](data)
        let start = b.starts(with: bom) ? bom.count : 0   // a byte order mark stays where it is
        guard let original = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let o = object(b, at: space(b, start)),
              let changes = changes(b, o, from: original, to: target, indent: "", newline: newline(b)) else { return nil }
        var out = b
        var lastStart = Int.max
        for c in changes.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            guard c.range.upperBound <= lastStart else { return nil }   // two changes overlap
            out.replaceSubrange(c.range, with: c.bytes)
            lastStart = c.range.lowerBound
        }
        let result = Data(out)
        guard let back = (try? JSONSerialization.jsonObject(with: result)) as? NSDictionary, back.isEqual(to: target) else { return nil }
        return result
    }

    static func changes(_ b: [UInt8], _ o: Object, from original: [String: Any], to target: [String: Any], indent: String,
                        newline: String) -> [Change]? {
        let keys = o.members.map(\.key)
        guard Set(keys).count == keys.count else { return nil }
        var out: [Change] = []
        var removed = false
        for (k, m) in o.members.enumerated() {
            guard let new = target[m.key] else {
                removed = true
                if k > 0 { out.append(Change(range: o.members[k - 1].valueEnd..<m.valueEnd, bytes: [])) }
                else if o.members.count > 1 { out.append(Change(range: m.keyStart..<o.members[1].keyStart, bytes: [])) }
                else { out.append(Change(range: (o.open + 1)..<o.close, bytes: [])) }
                continue
            }
            let old = original[m.key]
            if let old, (old as AnyObject).isEqual(new) { continue }
            let lineIndent = indentOfLine(b, m.keyStart)
            if let oldObj = old as? [String: Any], let newObj = new as? [String: Any], let inner = object(b, at: m.valueStart),
               let sub = changes(b, inner, from: oldObj, to: newObj, indent: lineIndent, newline: newline) {
                out += sub
            } else {
                guard let text = render(new, indent: lineIndent, style: Style(newline: newline, colon: colon(b, m))) else { return nil }
                out.append(Change(range: m.valueStart..<m.valueEnd, bytes: text))
            }
        }
        let added = target.keys.filter { !keys.contains($0) }.sorted()
        guard !added.isEmpty else { return out }
        guard !removed else { return nil }
        if let last = o.members.last {
            // the gap before the last member (its comma, line break and indent) and its key to value spacing, repeated
            let gap: [UInt8] = o.members.count > 1 ? Array(b[o.members[o.members.count - 2].valueEnd..<last.keyStart])
                                                   : [UInt8(ascii: ",")] + Array(b[(o.open + 1)..<last.keyStart])
            let colon = Array(b[last.keyEnd..<last.valueStart])
            let lineIndent = indentOfLine(b, last.keyStart)
            let style = Style(newline: newline, colon: Self.colon(b, last))
            var text: [UInt8] = []
            for key in added {
                guard let k = render(key, indent: "", style: style), let v = render(target[key] as Any, indent: lineIndent, style: style)
                else { return nil }
                text += gap + k + colon + v
            }
            out.append(Change(range: last.valueEnd..<last.valueEnd, bytes: text))
        } else {
            let inner = indent + "  "
            let style = Style(newline: newline)
            var parts: [String] = []
            for key in added {
                guard let k = render(key, indent: "", style: style), let v = render(target[key] as Any, indent: inner, style: style)
                else { return nil }
                parts.append(inner + String(decoding: k, as: UTF8.self) + style.colon + String(decoding: v, as: UTF8.self))
            }
            let nl = newline
            out.append(Change(range: (o.open + 1)..<o.close, bytes: Array((nl + parts.joined(separator: "," + nl) + nl + indent).utf8)))
        }
        return out
    }

    /// A value pretty printed two spaces deep, keys sorted, its later lines indented to the member's line, in the file's
    /// line break and key to value spacing. Strings and numbers are spelled by the system writer.
    static func render(_ value: Any, indent: String, style: Style) -> [UInt8]? {
        text(value, indent: indent, style: style).map { Array($0.utf8) }
    }

    static func text(_ value: Any, indent: String, style: Style) -> String? {
        let inner = indent + "  ", nl = style.newline
        if let d = value as? [String: Any] {
            if d.isEmpty { return "{}" }
            var parts: [String] = []
            for k in d.keys.sorted() {
                guard let key = text(k, indent: inner, style: style), let v = d[k], let t = text(v, indent: inner, style: style) else { return nil }
                parts.append(inner + key + style.colon + t)
            }
            return "{" + nl + parts.joined(separator: "," + nl) + nl + indent + "}"
        }
        if let a = value as? [Any] {
            if a.isEmpty { return "[]" }
            var parts: [String] = []
            for v in a {
                guard let t = text(v, indent: inner, style: style) else { return nil }
                parts.append(inner + t)
            }
            return "[" + nl + parts.joined(separator: "," + nl) + nl + indent + "]"
        }
        guard value is String || value is NSNumber || value is NSNull,
              let d = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .fragmentsAllowed]) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    /// The same member edit for remove.sh, in JavaScript for osascript (part of macOS): argument one the file, two the
    /// saved statusLine as JSON or empty to remove the key. It prints the new text followed by one x, which sh strips, so
    /// that a missing or doubled final line break survives the command substitution; or nothing when the file is not a
    /// JSON object. When the member cannot be placed it prints the whole object, its key order kept, two spaces deep (a
    /// final line break when the file had one), unless the file holds a 16 digit run (a number JavaScript would round).
    /// An entry put back is placed member by member, as the app's Remove does (a member that moved replaced in place, one
    /// that went cut, a new one added after the last), in the file's line ending and spacing (second audit, F-72); the
    /// result is compared to the settings asked for with keys in any order, as plutil gives the saved entry sorted. No
    /// single quote and no backslash in it: it sits in single quotes in sh.
    public static let zapScript = #"""
    function run(a){var r=go(a);return r?r+"x":""}
    function go(a){try{
    var t=$.NSString.stringWithContentsOfFileEncodingError(a[0],4,null).js;if(t.charCodeAt(0)===65279)t=t.slice(1);
    var o=JSON.parse(t);if(o===null||typeof o!=="object"||Array.isArray(o))return "";
    var j=a[1]?JSON.parse(a[1]):null;if(j)o.statusLine=j;else delete o.statusLine;
    var want=cn(o);var r=cut(t,j);
    if(r!==null){try{if(cn(JSON.parse(r))===want)return r}catch(e){}}
    if(/[0-9]{16}/.test(t))return "";
    return JSON.stringify(o,null,2)+(t.charCodeAt(t.length-1)===10?LF:"")}catch(e){return ""}}
    var LF=String.fromCharCode(10),CR=String.fromCharCode(13);
    function cn(v){if(v===null||typeof v!=="object")return JSON.stringify(v);if(Array.isArray(v))return "["+v.map(cn).join(",")+"]";
    return "{"+Object.keys(v).sort().map(function(k){return JSON.stringify(k)+":"+cn(v[k])}).join(",")+"}"}
    function isObj(v){return v!==null&&typeof v==="object"&&!Array.isArray(v)}
    function sp(t,i){var c=t.charCodeAt(i);return c===32||c===9||c===10||c===13}
    function ws(t,i){while(i<t.length&&sp(t,i))i++;return i}
    function str(t,i){var k=i+1;while(k<t.length){var c=t.charCodeAt(k);if(c===92){k+=2;continue}if(c===34)return k+1;k++}return -1}
    function val(t,i){var c=t.charCodeAt(i),k=i;if(c===34)return str(t,i);
    if(c===123||c===91){var d=0;while(k<t.length){c=t.charCodeAt(k);if(c===34){k=str(t,k);if(k<0)return -1;continue}
    if(c===123||c===91)d++;else if(c===125||c===93){d--;if(d===0)return k+1}k++}return -1}
    while(k<t.length&&!sp(t,k)&&",}]".indexOf(t[k])<0)k++;return k>i?k:-1}
    function obj(t,i){var m=[],seen={};i=ws(t,i+1);
    while(i<t.length&&t.charCodeAt(i)!==125){if(t.charCodeAt(i)!==34)return null;var ke=str(t,i);if(ke<0)return null;
    var v=ws(t,ke);if(t.charCodeAt(v)!==58)return null;v=ws(t,v+1);var ve=val(t,v);if(ve<0)return null;
    var k=JSON.parse(t.slice(i,ke));if(seen["#"+k])return null;seen["#"+k]=1;
    m.push({k:k,s:i,ke:ke,v:v,e:ve});i=ws(t,ve);if(t.charCodeAt(i)===44)i=ws(t,i+1)}
    return i<t.length?{m:m,c:i}:null}
    function ind(t,at){var ls=at;while(ls>0&&t.charCodeAt(ls-1)!==10)ls--;var le=ls;
    while(le<at&&(t.charCodeAt(le)===32||t.charCodeAt(le)===9))le++;return t.slice(ls,le)}
    function col(t,x){var c=t.slice(x.ke,x.v);return c.indexOf(LF)<0&&c.indexOf(CR)<0?c:": "}
    function lay(v,i,br,c){var n=i+"  ",p=[];
    if(Array.isArray(v)){if(!v.length)return "[]";for(var a=0;a<v.length;a++)p.push(n+lay(v[a],n,br,c));return "["+br+p.join(","+br)+br+i+"]"}
    if(isObj(v)){var ks=Object.keys(v);if(!ks.length)return "{}";for(var b=0;b<ks.length;b++)p.push(n+JSON.stringify(ks[b])+c+lay(v[ks[b]],n,br,c));
    return "{"+br+p.join(","+br)+br+i+"}"}
    return JSON.stringify(v)}
    function sub(t,st,j,br){var O=obj(t,st);if(!O)return null;var m=O.m,out=[],rm=false,have={};
    for(var x=0;x<m.length;x++){var e=m[x];have["#"+e.k]=1;
    if(!Object.prototype.hasOwnProperty.call(j,e.k)){rm=true;
    if(x>0)out.push({a:m[x-1].e,b:e.e,x:""});else if(m.length>1)out.push({a:e.s,b:m[1].s,x:""});else out.push({a:st+1,b:O.c,x:""});continue}
    var w=j[e.k];if(cn(JSON.parse(t.slice(e.v,e.e)))===cn(w))continue;
    var r=t.charCodeAt(e.v)===123&&isObj(w)?sub(t,e.v,w,br):null;
    out=out.concat(r||[{a:e.v,b:e.e,x:lay(w,ind(t,e.s),br,col(t,e))}])}
    var add=Object.keys(j).filter(function(k){return !have["#"+k]});if(!add.length)return out;if(rm)return null;
    var txt="";if(m.length){var l=m[m.length-1],gap=m.length>1?t.slice(m[m.length-2].e,l.s):","+t.slice(st+1,l.s),c=t.slice(l.ke,l.v);
    for(var y=0;y<add.length;y++)txt+=gap+JSON.stringify(add[y])+c+lay(j[add[y]],ind(t,l.s),br,col(t,l));out.push({a:l.e,b:l.e,x:txt});return out}
    var i0=ind(t,st),p=[];for(var z=0;z<add.length;z++)p.push(i0+"  "+JSON.stringify(add[z])+": "+lay(j[add[z]],i0+"  ",br,": "));
    out.push({a:st+1,b:O.c,x:br+p.join(","+br)+br+i0});return out}
    function apply(t,ch){ch.sort(function(p,q){return q.a-p.a});var last=t.length+1;
    for(var x=0;x<ch.length;x++){if(ch[x].b>last)return null;t=t.slice(0,ch[x].a)+ch[x].x+t.slice(ch[x].b);last=ch[x].a}return t}
    function cut(t,j){var i=ws(t,0);if(t.charCodeAt(i)!==123)return null;
    var f=t.indexOf(LF),br=f>0&&t.charCodeAt(f-1)===13?CR+LF:LF;
    if(j){var O=obj(t,i);if(!O)return null;
    var cur=null;for(var x=0;x<O.m.length;x++)if(O.m[x].k==="statusLine")cur=O.m[x];if(!cur)return null;
    var r=t.charCodeAt(cur.v)===123&&isObj(j)?sub(t,cur.v,j,br):null;
    return apply(t,r||[{a:cur.v,b:cur.e,x:lay(j,ind(t,cur.s),br,col(t,cur))}])}
    var P=obj(t,i);if(!P)return null;var m=P.m,n=-1;for(var y=0;y<m.length;y++)if(m[y].k==="statusLine")n=y;if(n<0)return null;var e=m[n];
    if(n>0)return t.slice(0,m[n-1].e)+t.slice(e.e);
    if(m.length>1)return t.slice(0,e.s)+t.slice(m[1].s);
    return t.slice(0,i+1)+t.slice(P.c)}
    """#

    static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d }

    static func space(_ b: [UInt8], _ i: Int) -> Int { var i = i; while i < b.count, isSpace(b[i]) { i += 1 }; return i }

    /// The spaces and tabs that start the line `at` is on.
    static func indentOfLine(_ b: [UInt8], _ at: Int) -> String {
        var start = at
        while start > 0, b[start - 1] != 0x0a { start -= 1 }
        var end = start
        while end < at, b[end] == 0x20 || b[end] == 0x09 { end += 1 }
        return String(decoding: b[start..<end], as: UTF8.self)
    }

    /// The end of the string that starts at i (after its closing quote).
    static func string(_ b: [UInt8], _ i: Int) -> Int? {
        guard i < b.count, b[i] == 0x22 else { return nil }
        var j = i + 1
        while j < b.count {
            if b[j] == 0x5c { j += 2; continue }
            if b[j] == 0x22 { return j + 1 }
            j += 1
        }
        return nil
    }

    /// The end of the value that starts at i.
    static func value(_ b: [UInt8], _ i: Int) -> Int? {
        guard i < b.count else { return nil }
        switch b[i] {
        case 0x22: return string(b, i)
        case 0x7b, 0x5b:
            var depth = 0
            var j = i
            while j < b.count {
                let c = b[j]
                if c == 0x22 { guard let e = string(b, j) else { return nil }; j = e; continue }
                if c == 0x7b || c == 0x5b { depth += 1 } else if c == 0x7d || c == 0x5d { depth -= 1; if depth == 0 { return j + 1 } }
                j += 1
            }
            return nil
        default:
            var j = i
            while j < b.count, !isSpace(b[j]), b[j] != 0x2c, b[j] != 0x7d, b[j] != 0x5d { j += 1 }
            return j > i ? j : nil
        }
    }

    /// The members of the object that starts at `start`.
    static func object(_ b: [UInt8], at start: Int) -> Object? {
        guard start < b.count, b[start] == 0x7b else { return nil }
        var members: [Member] = []
        var i = space(b, start + 1)
        while i < b.count {
            if b[i] == 0x7d { return Object(open: start, close: i, members: members) }   // also after a trailing comma
            guard let keyEnd = string(b, i),
                  let key = (try? JSONSerialization.jsonObject(with: Data(b[i..<keyEnd]), options: .fragmentsAllowed)) as? String else { return nil }
            var j = space(b, keyEnd)
            guard j < b.count, b[j] == 0x3a else { return nil }
            j = space(b, j + 1)
            guard let valueEnd = value(b, j) else { return nil }
            members.append(Member(key: key, keyStart: i, keyEnd: keyEnd, valueStart: j, valueEnd: valueEnd))
            j = space(b, valueEnd)
            guard j < b.count else { return nil }
            if b[j] == 0x2c { j = space(b, j + 1) } else if b[j] != 0x7d { return nil }
            i = j
        }
        return nil
    }
}

/// Writes settings.json the way an editor that respects links does.
public enum SettingsFile {
    /// The file a path finally names, found the way the kernel opens it: part by part from /, each part that is a link
    /// replaced by its target (an absolute one from /, a relative one from the real folder reached so far), and ".."
    /// stepping up from that real folder, never by text. A part that does not exist yet (ENOENT) ends the walk, the rest
    /// appended, so a link to a file not made yet names that file; a ".." after it throws ENOENT, as the kernel does, and
    /// any other error on the way (ENOTDIR, EACCES) is thrown. 0.1.11 to 0.1.14 joined a relative link to the folder as
    /// written and removed ".." by text, which named another file when a folder on the way was itself a link (audit F-2,
    /// 04.11). More than 32 links is a loop, the kernel's limit.
    static func resolve(_ url: URL) throws -> URL {
        var pending = url.absoluteURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        pending.reverse()   // a stack: the next part last
        var real = ""       // the real path reached so far, no link in it; "" is /
        var links = 0
        var missing = false
        while let part = pending.popLast() {
            if part == "." { continue }
            if part == ".." {
                // the real folder is known, so its parent is too; past a missing part there is no folder to step out of
                if missing { throw POSIXError(.ENOENT) }
                if let slash = real.lastIndex(of: "/") { real = String(real[..<slash]) }
                continue
            }
            let next = real + "/" + part
            if missing { real = next; continue }
            var st = stat()
            guard lstat(next, &st) == 0 else {
                let e = errno
                guard e == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: e) ?? .EIO) }
                // not there (yet): what follows cannot be a link either
                missing = true
                real = next
                continue
            }
            guard st.st_mode & S_IFMT == S_IFLNK else {
                // a file with more parts after it: the kernel stops there, also for a ".."
                if st.st_mode & S_IFMT != S_IFDIR, !pending.isEmpty { throw POSIXError(.ENOTDIR) }
                real = next
                continue
            }
            links += 1
            if links > 32 { throw POSIXError(.ELOOP) }
            let dest = try FileManager.default.destinationOfSymbolicLink(atPath: next)
            if dest.hasPrefix("/") { real = "" }
            pending.append(contentsOf: dest.split(separator: "/", omittingEmptySubsequences: true).map(String.init).reversed())
        }
        return URL(fileURLWithPath: real.isEmpty ? "/" : real)
    }

    /// A link into a folder that does not exist: Install does not make it (spec 20.1.9).
    struct MissingFolder: Error { let folder: URL }

    /// Whether an error is that refusal, for the problem report's fixed reason.
    public static func isMissingFolder(_ error: any Error) -> Bool { error is MissingFolder }

    static func reason(_ error: Error) -> String {
        if let m = error as? MissingFolder {
            return "it is a link into " + (m.folder.path as NSString).abbreviatingWithTildeInPath + ", a folder that does not exist"
        }
        return error.localizedDescription
    }

    /// The file to write, and whether its folder may be made: only the settings folder itself, when it is no link, as
    /// Claude Code makes its own folder. A settings.json that is a link into a folder that does not exist is refused,
    /// as Claude Code's own write there would fail; from 0.1.11 Install made that folder (and its parents) and Remove
    /// left it (audit F-6).
    static func writableTarget(_ url: URL) throws -> URL {
        let target = try resolve(url)
        let dir = target.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue { return target }
        // the settings folder as named, itself no link (a dangling ~/.claude link is a folder elsewhere): it may be made
        let folder = url.deletingLastPathComponent()
        let own = try? resolve(folder), parent = try? resolve(folder.deletingLastPathComponent())
        guard let own, let parent, own.path == dir.path, own.path == parent.appendingPathComponent(folder.lastPathComponent).path else {
            throw MissingFolder(folder: dir)
        }
        return target
    }

    /// Writes data to the file the path names: a temporary file in the same folder, made with the old file's mode (0600 for
    /// a new file), then renamed over it. Neither a link nor a mode is ever replaced or widened.
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let target = try writableTarget(url)
        let dir = target.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var mode: mode_t = 0o600
        var st = stat()
        if stat(target.path, &st) == 0 { mode = st.st_mode & 0o7777 }
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).tokenpanda-\(UUID().uuidString)")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var ok = false
        defer { if !ok { unlink(tmp.path) } }
        var failure: Int32 = 0
        data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            var off = 0
            while off < buf.count {
                let n = Darwin.write(fd, base + off, buf.count - off)
                if n < 0 { if errno == EINTR { continue }; failure = errno; return }
                off += n
            }
        }
        if failure == 0, fchmod(fd, mode) != 0 { failure = errno }   // the umask may have narrowed it at open
        if failure == 0, fsync(fd) != 0 { failure = errno }
        close(fd)
        if failure != 0 { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
        guard rename(tmp.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        ok = true
    }
}

/// The settings folders Claude Code may read on this Mac. A menu bar app does not see the shell's environment, so
/// CLAUDE_CONFIG_DIR is taken from the app's own environment when it has one, and the home folder is looked at for
/// the usual places: ~/.claude, ~/.config/claude, and folders named .claude-something or .claude_something (the common
/// CLAUDE_CONFIG_DIR pattern for a second account). Only names are read here.
///
/// Install goes only where Claude Code already keeps settings: ~/.claude, a CLAUDE_CONFIG_DIR folder, and the others
/// only when they hold a settings.json. A ~/.claude-something folder that holds only transcripts (a ~/.claude-backup) is
/// left out for transcripts too, as the README says: until the second audit of 0.1.19 (F-70) its copies were counted a
/// second time. Making a settings.json in a folder is how a user opts it in.
public enum ConfigFolders {
    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        folders(home: home, environment: environment, projectsCount: false)
    }

    /// Every folder with transcripts to count: the install targets and ~/.config/claude or the CLAUDE_CONFIG_DIR folder when
    /// it holds only a projects folder. For the tests; the app takes both lists from one listing (scan).
    static func transcriptFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        folders(home: home, environment: environment, projectsCount: true)
    }

    /// CLAUDE_CONFIG_DIR as one path, as Claude Code reads it, a leading ~ expanded: a comma is part of the name (until
    /// 0.1.18 the value was split at commas, audit F-66). nil when unset or blank.
    public static func environmentFolder(_ environment: [String: String]) -> URL? {
        guard let dir = environment["CLAUDE_CONFIG_DIR"], !dir.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Both lists from one listing of the home folder: the install targets and the transcript folders.
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> (install: [URL], transcripts: [URL]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return (folders(home: home, environment: environment, projectsCount: false, listing: names),
                folders(home: home, environment: environment, projectsCount: true, listing: names))
    }

    /// The transcript roots: the usual places and the projects folder of each transcript folder, in that order.
    public static func transcriptRoots(usual: [URL], folders: [URL]) -> [URL] {
        var roots = usual
        for f in folders {
            let r = f.appendingPathComponent("projects", isDirectory: true)
            if !roots.contains(r) { roots.append(r) }
        }
        return roots
    }

    static func folders(home: URL, environment: [String: String], projectsCount: Bool, listing: [String]? = nil) -> [URL] {
        let fm = FileManager.default
        func isDir(_ u: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }
        let primary = home.appendingPathComponent(".claude", isDirectory: true)
        var candidates: [URL] = [primary]
        func qualifies(_ u: URL) -> Bool {
            fm.fileExists(atPath: u.appendingPathComponent("settings.json").path) || (projectsCount && isDir(u.appendingPathComponent("projects")))
        }
        let xdg = home.appendingPathComponent(".config/claude", isDirectory: true)
        if qualifies(xdg) { candidates.append(xdg) }
        if let env = environmentFolder(environment) { candidates.append(env) }
        let names = (listing ?? ((try? fm.contentsOfDirectory(atPath: home.path)) ?? [])).filter { $0.hasPrefix(".claude-") || $0.hasPrefix(".claude_") }.sorted()
        for n in names {
            // a .claude-something folder counts only with a settings.json: one with only projects is a backup copy
            let u = home.appendingPathComponent(n, isDirectory: true)
            if fm.fileExists(atPath: u.appendingPathComponent("settings.json").path) { candidates.append(u) }
        }
        var seen = Set<String>()
        var out: [URL] = []
        for c in candidates where isDir(c) {
            let key = c.resolvingSymlinksInPath().standardizedFileURL.path
            if seen.insert(key).inserted { out.append(c) }
        }
        // nothing there yet: ~/.claude, where Claude Code starts
        return out.isEmpty ? [primary] : out
    }

    /// The name of a settings folder's script and backup file. nil for ~/.claude, which keeps the names every earlier
    /// version used. Otherwise a readable part and a hash of the full resolved path, so two folders never share one:
    /// ~/.claude-work and ~/.claude_work read alike but hash apart. Earlier versions wrote only ~/.claude's files, so
    /// there is nothing under an older name to move.
    public static func id(for folder: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = folder.standardizedFileURL.path
        if path == home.appendingPathComponent(".claude").standardizedFileURL.path { return nil }
        let base = home.standardizedFileURL.path + "/"
        let rel = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
        let cleaned = String(rel.map { $0.isLetter || $0.isNumber ? $0 : "-" }).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return (cleaned.isEmpty ? "root" : String(cleaned.prefix(40))) + "-" + fnv1a(resolved)
    }

    /// FNV-1a, 64 bit, as 16 hex digits: stable across launches and versions, unlike Swift's seeded Hasher.
    static func fnv1a(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }

    /// The folder as the user knows it: "~/.claude".
    public static func display(_ folder: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = folder.standardizedFileURL.path
        let h = home.standardizedFileURL.path
        if path == h { return "~" }
        return path.hasPrefix(h + "/") ? "~" + path.dropFirst(h.count) : path
    }
}

/// When a feed scan looks in the home folder for a settings folder made since launch: at most once a minute, and at
/// each open of the panel (forced). Until 0.1.18 every scan listed the home folder, every 5 s and up to once a second
/// while sessions write (review).
public struct FolderClock: Sendable, Equatable {
    public static let every: TimeInterval = 60
    public private(set) var last: Date?
    public init() {}
    /// true when a look is due now, and counts it.
    public mutating func due(now: Date, force: Bool = false) -> Bool {
        if !force, let l = last, now.timeIntervalSince(l) < Self.every, now >= l { return false }
        last = now
        return true
    }
}

/// The status line entry across every settings folder: one Hook each, sharing the data folder and the sessions folder.
public struct HookSet: Sendable {
    public let hooks: [Hook]
    public let targets: [String]

    public init(folders: [URL], dataDir: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        hooks = folders.map { Hook(settingsURL: $0.appendingPathComponent("settings.json"), dataDir: dataDir, id: ConfigFolders.id(for: $0, home: home)) }
        targets = folders.map { ConfigFolders.display($0, home: home) }
    }

    /// Installed means in every folder. The chained command and the slower refresh come from a folder that still needs Install.
    public func status() -> HookStatus {
        let each = hooks.map { $0.status() }
        let installed = each.allSatisfy(\.installed)
        let pending = each.filter { !$0.installed }
        let ins = each.filter(\.installed)
        return HookStatus(installed: installed, previousCommand: pending.compactMap(\.previousCommand).first,
                          hooksDisabled: !ins.isEmpty && ins.allSatisfy(\.hooksDisabled),
                          slowerRefresh: pending.compactMap(\.slowerRefresh).first,
                          scriptMissing: each.contains(where: \.scriptMissing), anyInstalled: !ins.isEmpty, targets: targets)
    }

    /// One date that moves when any settings.json moves, appears or goes.
    public func settingsModified() -> [Date?] { hooks.map { $0.settingsModified() } }

    /// What each feed tick compares to read the status again: every settings.json's time and whether each script is
    /// there. Until 0.1.18 only the times, so a script deleted while the app ran was not noticed (review).
    public struct Stamp: Sendable, Equatable {
        public var settings: [Date?]
        public var scripts: [Bool]
    }

    public func stamp() -> Stamp {
        Stamp(settings: settingsModified(), scripts: hooks.map { FileManager.default.isExecutableFile(atPath: $0.hookPath.path) })
    }

    /// The sessions folder, made at launch only while an entry is installed somewhere: after Remove deleted it, a launch
    /// does not make it again (review; until 0.1.18 every launch did). True when it is there afterwards.
    @discardableResult
    public func prepareSessionsFolder() -> Bool {
        guard let dir = hooks.first?.sessionsDir else { return false }
        guard hooks.contains(where: { $0.status().installed }) else { return FileManager.default.fileExists(atPath: dir.path) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: dir.path)
    }

    /// Installs into every folder that does not have the entry yet. Stops at the first error and says which folder.
    /// The remove script is rewritten either way, for what got installed.
    public func install(previousFallback: (Hook) -> String? = { _ in nil }) throws -> [(Hook, HookStatus)] {
        var out: [(Hook, HookStatus)] = []
        defer { writeRemoveScript() }
        for (h, t) in zip(hooks, targets) where !h.status().installed {
            do { out.append((h, try h.install(previousFallback: previousFallback(h)))) }
            catch { throw hooks.count > 1 ? HookError.inFolder(t, error) : error }
        }
        return out
    }

    /// remove.sh in the data folder: Remove without the app, for brew's zap. Homebrew before 7.0.10 deletes the app before
    /// it runs a zap script, so the zap runs this file, which lives in the data folder until the zap's own trash step.
    /// It needs sh, osascript (the JSON edit, in JavaScript) and plutil as the fallback. Per settings file: only while statusLine still runs our script, it puts back the
    /// saved entry or removes the key, and deletes a settings.json that Install created and that is empty again.
    public var removeScriptPath: URL? { hooks.first.map { $0.dataDir.appendingPathComponent("remove.sh") } }

    public static func removeScript(_ hooks: [Hook]) -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var out = """
        #!/bin/sh
        # tokenpanda's Remove without the app, written by the app at Install and Remove. brew uninstall --zap runs it
        # before it trashes this folder. For each settings.json: only while its statusLine still runs tokenpanda's script,
        # put back the entry saved at install, or remove the key; delete the file if Install created it and it is empty.
        # Only the statusLine member is changed, the rest of the file kept as it is, by the JavaScript below (osascript,
        # part of macOS), written to a temporary file next to it and renamed over it (a link stays a link: the file it
        # points at is written); plutil, which writes the whole file on one line in its own key order, only when that
        # fails. When the entry is still there afterwards it says so and the script exits 1.
        EDIT='\(SettingsText.zapScript)'
        FAIL=0
        restore() {
          S="$1"; OURS="$2"; B="$3"
          [ -f "$S" ] || return 0
          cmd=$(/usr/bin/plutil -extract statusLine.command raw -o - "$S" 2>/dev/null) || return 0
          [ "$cmd" = "$OURS" ] || return 0
          J=""
          if [ -f "$B" ]; then J=$(/usr/bin/plutil -extract statusLine json -o - "$B" 2>/dev/null) || J=""; fi
          T=$(/usr/bin/readlink -f "$S" 2>/dev/null) || T="$S"
          ok=""
          if OUT=$(/usr/bin/osascript -l JavaScript -e "$EDIT" "$T" "$J" 2>/dev/null) && [ -n "$OUT" ]; then
            OUT=${OUT%x}
            # the JavaScript drops a byte order mark (JSON.parse refuses one): put it back
            if [ "$(/usr/bin/head -c 3 "$T" | /usr/bin/od -An -tx1 | /usr/bin/tr -d ' \\n')" = "efbbbf" ]; then
              BOM=$(printf '\\357\\273\\277')
              case "$OUT" in "$BOM"*) ;; *) OUT="$BOM$OUT" ;; esac
            fi
            N="$(/usr/bin/dirname "$T")/.$(/usr/bin/basename "$T").tokenpanda-$$"
            M=$(/usr/bin/stat -f %Lp "$T" 2>/dev/null) || M=600
            if (set -C; umask 077; printf '%s' "$OUT" > "$N") 2>/dev/null && /bin/chmod "$M" "$N" 2>/dev/null \\
               && /bin/mv -f "$N" "$T" 2>/dev/null; then
              ok=1
            else
              /bin/rm -f "$N" 2>/dev/null
            fi
          fi
          if [ -z "$ok" ]; then
            if [ -n "$J" ]; then
              /usr/bin/plutil -replace statusLine -json "$J" "$T" >/dev/null 2>&1 && ok=1
            else
              /usr/bin/plutil -remove statusLine "$T" >/dev/null 2>&1 && ok=1
            fi
          fi
          now=$(/usr/bin/plutil -extract statusLine.command raw -o - "$S" 2>/dev/null) || now=""
          if [ -z "$ok" ] || [ "$now" = "$OURS" ]; then
            echo "tokenpanda: could not write $S, its status line entry is still there" >&2
            FAIL=1
            return 0
          fi
          if [ -f "$B" ] && [ "$(/usr/bin/plutil -extract createdSettings raw -o - "$B" 2>/dev/null)" = "true" ] \\
             && [ "$(/usr/bin/plutil -convert json -o - "$S" 2>/dev/null)" = "{}" ]; then
            T=$(/usr/bin/readlink -f "$S" 2>/dev/null) || T="$S"
            rm -f "$T"
          fi
          echo "tokenpanda: status line entry removed from $S"
        }

        """
        for h in hooks { out += "restore \(q(h.settingsURL.path)) \(q(h.hookCommand)) \(q(h.backupPath.path))\n" }
        return out + "exit $FAIL\n"
    }

    /// Every installed script brought to the current template (see Hook.refreshScript).
    public func refreshScripts() { for h in hooks { h.refreshScript() } }

    /// Lists the folders whose entry is ours (installed, or pointing at a lost script); with none, the file goes.
    /// Returns why it could not be written, for the Settings tab, and logs it: without it brew's zap cannot put the entry back.
    @discardableResult
    public func writeRemoveScript() -> String? { writeRemoveScriptError()?.localizedDescription }

    /// The same, with the error itself, so the problem report can print its codes.
    @discardableResult
    public func writeRemoveScriptError() -> (any Error)? {
        guard let url = removeScriptPath else { return nil }
        let fm = FileManager.default
        let ours = hooks.filter { let st = $0.status(); return st.installed || st.scriptMissing }
        if ours.isEmpty {
            if fm.fileExists(atPath: url.path) {
                do { try fm.removeItem(at: url) } catch { FileLog.failed("remove.sh (delete)", error) }
            }
            return nil
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.removeScript(ours).write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return nil
        } catch {
            FileLog.failed("remove.sh", error)
            return error
        }
    }

    /// Removes the entry from every folder that has it; the sessions folder goes with the last one.
    public func uninstall(previousCommand: (Hook) -> String?, previousRefresh: (Hook) -> Double?) throws {
        var firstError: Error? = nil
        for (h, t) in zip(hooks, targets) {
            let st = h.status()
            guard st.installed || st.scriptMissing || FileManager.default.fileExists(atPath: h.hookPath.path) else { continue }
            do { try h.uninstall(previousCommand: previousCommand(h), previousRefresh: previousRefresh(h), removeSessions: false) }
            catch { if firstError == nil { firstError = hooks.count > 1 ? HookError.inFolder(t, error) : error } }
        }
        writeRemoveScript()
        if let firstError { throw firstError }
        if !hooks.contains(where: { $0.status().installed }), let first = hooks.first { try? FileManager.default.removeItem(at: first.sessionsDir) }
    }
}
