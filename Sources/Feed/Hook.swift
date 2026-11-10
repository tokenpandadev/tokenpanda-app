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

    func readSettings() -> [String: Any]? {
        guard let d = SafeFile.read(settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
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
        let created = !fm.fileExists(atPath: settingsURL.path)
        if !created {
            guard let s = readSettings() else { throw HookError.cannotReadSettings(Self.unreadable(settingsURL)) }
            settings = s
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
        try writeSettings(settings)
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
            guard var settings = readSettings() else { throw HookError.cannotReadSettings(Self.unreadable(settingsURL)) }
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
                    try writeSettings(settings)
                }
            }
        }
        if removeSessions { try? fm.removeItem(at: sessionsDir) }
        try? fm.removeItem(at: hookPath)
        try? fm.removeItem(at: backupPath)
    }

    /// The system JSON writer re-serialises the file: pretty printed with slashes unescaped; indentation and key order may change.
    /// In content only the statusLine key differs. A settings.json that is a link (into a dotfiles folder) stays a link: the
    /// file it points at is written, atomically, and keeps its mode; a new file is made owner only.
    func writeSettings(_ settings: [String: Any]) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
            try SettingsFile.write(data, to: settingsURL)
        } catch { throw HookError.cannotWriteSettings(SettingsFile.reason(error), cause: error) }
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
/// only when they hold a settings.json. A copy that holds only transcripts (a ~/.claude-backup) is read for its
/// transcripts and left alone; making a settings.json in a folder is how a user opts it in.
public enum ConfigFolders {
    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        folders(home: home, environment: environment, projectsCount: false)
    }

    /// Every folder with transcripts to count: the install targets and the folders that hold only a projects folder.
    public static func transcriptFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                         environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        folders(home: home, environment: environment, projectsCount: true)
    }

    static func folders(home: URL, environment: [String: String], projectsCount: Bool) -> [URL] {
        let fm = FileManager.default
        func isDir(_ u: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }
        let primary = home.appendingPathComponent(".claude", isDirectory: true)
        var candidates: [URL] = [primary]
        func qualifies(_ u: URL) -> Bool {
            fm.fileExists(atPath: u.appendingPathComponent("settings.json").path) || (projectsCount && isDir(u.appendingPathComponent("projects")))
        }
        let xdg = home.appendingPathComponent(".config/claude", isDirectory: true)
        if qualifies(xdg) { candidates.append(xdg) }
        if let dirs = environment["CLAUDE_CONFIG_DIR"] {
            for d in dirs.split(separator: ",") {
                let t = (d.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
                if !t.isEmpty { candidates.append(URL(fileURLWithPath: t, isDirectory: true)) }
            }
        }
        let names = ((try? fm.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0.hasPrefix(".claude-") || $0.hasPrefix(".claude_") }.sorted()
        for n in names {
            let u = home.appendingPathComponent(n, isDirectory: true)
            if qualifies(u) { candidates.append(u) }
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
    /// It needs only sh and plutil. Per settings file: only while statusLine still runs our script, it puts back the
    /// saved entry or removes the key, and deletes a settings.json that Install created and that is empty again.
    public var removeScriptPath: URL? { hooks.first.map { $0.dataDir.appendingPathComponent("remove.sh") } }

    public static func removeScript(_ hooks: [Hook]) -> String {
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var out = """
        #!/bin/sh
        # tokenpanda's Remove without the app, written by the app at Install and Remove. brew uninstall --zap runs it
        # before it trashes this folder. For each settings.json: only while its statusLine still runs tokenpanda's script,
        # put back the entry saved at install, or remove the key; delete the file if Install created it and it is empty.
        restore() {
          S="$1"; OURS="$2"; B="$3"
          [ -f "$S" ] || return 0
          cmd=$(/usr/bin/plutil -extract statusLine.command raw -o - "$S" 2>/dev/null) || return 0
          [ "$cmd" = "$OURS" ] || return 0
          if [ -f "$B" ] && J=$(/usr/bin/plutil -extract statusLine json -o - "$B" 2>/dev/null); then
            /usr/bin/plutil -replace statusLine -json "$J" "$S"
          else
            /usr/bin/plutil -remove statusLine "$S"
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
        return out + "exit 0\n"
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
