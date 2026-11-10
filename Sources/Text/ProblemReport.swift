// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// "Copy a problem report" in Settings: plain text the user pastes into an issue or a mail. The app sends nothing.
// What it holds was set 05.11.2026: versions, the Mac model, the switches, the status line entry per settings folder and
// when its data last came, how many sessions run, and the errors the app shows. Never a prompt, a session name or id,
// a project path or a usage figure.
//
// No free text from the system or from an error message ever reaches it (second review of 00b5982, 05.11.2026: scrubbing
// such text kept leaking folder and project names). An error is a Fault: an area, a fixed verb, a fixed step and reason the
// app chose, and the error's domain, code and POSIX errno. Folder rows are fixed names too. The user's name is checked
// in the fields the system fills.
import Foundation

/// An error's codes, never its text: the NSError domain (a short identifier, or "other domain"), its code, and the POSIX
/// errno underneath when there is one.
public struct ErrorCode: Sendable, Equatable {
    public var domain: String
    public var code: Int
    public var posix: Int32?

    public init(domain: String, code: Int, posix: Int32? = nil) {
        self.domain = Self.safeDomain(domain); self.code = code; self.posix = posix
    }

    /// The codes of any error. Its description, file names and paths are left behind.
    public init(_ error: any Error) {
        let ns = error as NSError
        var posix: Int32? = ns.domain == NSPOSIXErrorDomain ? Int32(clamping: ns.code) : nil
        var under = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        while posix == nil, let u = under {
            if u.domain == NSPOSIXErrorDomain { posix = Int32(clamping: u.code) }
            under = u.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.init(domain: ns.domain, code: ns.code, posix: posix)
    }

    /// A domain is a reverse-DNS or type name. Anything else (a path, spaces, quotes, over 64 characters) is not printed.
    static func safeDomain(_ d: String) -> String {
        d.range(of: #"^[A-Za-z][A-Za-z0-9_.]{0,63}$"#, options: .regularExpression) != nil ? d : "other domain"
    }

    /// "NSCocoaErrorDomain 513, POSIX 13 EACCES", or "POSIX 1 EPERM" for a plain POSIX error.
    public var text: String {
        var parts: [String] = []
        if domain != NSPOSIXErrorDomain { parts.append("\(domain) \(code)") }
        if let p = posix { parts.append("POSIX \(p)" + (Self.errnoNames[p].map { " " + $0 } ?? "")) }
        return parts.joined(separator: ", ")
    }

    static let errnoNames: [Int32: String] = [
        1: "EPERM", 2: "ENOENT", 3: "ESRCH", 4: "EINTR", 5: "EIO", 9: "EBADF", 12: "ENOMEM", 13: "EACCES", 16: "EBUSY",
        17: "EEXIST", 18: "EXDEV", 20: "ENOTDIR", 21: "EISDIR", 22: "EINVAL", 23: "ENFILE", 24: "EMFILE", 27: "EFBIG",
        28: "ENOSPC", 30: "EROFS", 35: "EAGAIN", 60: "ETIMEDOUT", 62: "ELOOP", 63: "ENAMETOOLONG", 66: "ENOTEMPTY", 69: "EDQUOT",
    ]
}

/// One error the app shows, in fixed words. Every part is chosen from a closed set; there is no field for free text.
public struct Fault: Sendable, Equatable {
    public enum Area: String, Sendable {
        case statusLine = "Status line entry"
        case removeScript = "Remove script"
        case openAtLogin = "Open at login"
        case transcripts = "Transcripts"
        case processList = "Process list"
        case feedFormat = "Feed format"
        case macWarning = "Mac tab"
    }
    public enum Verb: String, Sendable {
        case install = "could not install"
        case remove = "could not remove"
        case write = "could not write"
        case read = "could not read"
        case register = "could not register"
        case unregister = "could not unregister"
        case changed = "changed, update tokenpanda"
        case warning = "shows its warning: memory pressure or a process holding the CPU"
    }
    /// Where inside an install or remove it failed.
    public enum Step: String, Sendable {
        case readSettings = "could not read the settings file"
        case writeSettings = "could not write the settings file"
        case writeScript = "could not write the hook script"
    }
    /// Why, when the app itself knows it.
    public enum Reason: String, Sendable {
        case notJSON = "not valid JSON"
        case notObject = "not a JSON object"
        case tooLarge = "over 1 MB"
        case notRegularFile = "not a regular file"
        case linkToMissingFolder = "a link into a folder that does not exist"
    }

    public var area: Area
    public var verb: Verb
    public var step: Step?
    public var reason: Reason?
    public var code: ErrorCode?

    public init(_ area: Area, _ verb: Verb, step: Step? = nil, reason: Reason? = nil, code: ErrorCode? = nil) {
        self.area = area; self.verb = verb; self.step = step; self.reason = reason; self.code = code
    }

    /// "Status line entry: could not install, could not write the settings file (NSCocoaErrorDomain 513, POSIX 13 EACCES)"
    public var text: String {
        var s = area.rawValue + ": " + verb.rawValue
        if let step { s += ", " + step.rawValue }
        if let reason { s += ": " + reason.rawValue }
        if let c = code?.text, !c.isEmpty { s += " (" + c + ")" }
        return s
    }
}

public struct ProblemReport: Sendable, Equatable {
    /// One settings folder: its name as Settings shows it ("~/.claude"). The report prints only a fixed name for it.
    public struct Folder: Sendable, Equatable {
        public var name: String
        public var installed: Bool
        public var scriptMissing: Bool
        public var hooksDisabled: Bool
        public init(name: String, installed: Bool, scriptMissing: Bool = false, hooksDisabled: Bool = false) {
            self.name = name; self.installed = installed; self.scriptMissing = scriptMissing; self.hooksDisabled = hooksDisabled
        }
    }

    public var version: String?
    public var macOS: String            // "26.1 (25B78)"
    public var model: String            // hw.model, "Mac15,6"
    public var openAtLogin: LoginItem
    public var macInBar: Bool
    public var nudges: Bool
    public var listPrice: Bool
    public var keepAwake: Bool
    public var keepAwakeWhileOpen: Bool
    public var restoreSessions: Bool
    public var reopenApp: TerminalApp
    public var folders: [Folder]
    public var lastData: Date?           // the newest status line write the app read
    public var sessions: Int
    public var faults: [Fault]
    public var userNames: [String]       // the account name and the parts of the full name: never in the report
    public var timeZone: TimeZone

    public init(version: String?, macOS: String, model: String, openAtLogin: LoginItem, macInBar: Bool, nudges: Bool, listPrice: Bool,
                keepAwake: Bool, keepAwakeWhileOpen: Bool, restoreSessions: Bool, reopenApp: TerminalApp, folders: [Folder],
                lastData: Date?, sessions: Int, faults: [Fault], userNames: [String] = [], timeZone: TimeZone = .current) {
        self.version = version; self.macOS = macOS; self.model = model; self.openAtLogin = openAtLogin; self.macInBar = macInBar
        self.nudges = nudges; self.listPrice = listPrice; self.keepAwake = keepAwake; self.keepAwakeWhileOpen = keepAwakeWhileOpen
        self.restoreSessions = restoreSessions; self.reopenApp = reopenApp; self.folders = folders; self.lastData = lastData
        self.sessions = sessions; self.faults = faults; self.userNames = userNames; self.timeZone = timeZone
    }

    public var text: String {
        func onOff(_ b: Bool) -> String { b ? "on" : "off" }
        // the user's name is checked only in the fields the system fills (versions, model, error domains), never in the
        // joined text: a name part that is also a fixed word ("Price", "Read", "Mac") would otherwise be replaced there and
        // give the name away (third review, 1e22148)
        func free(_ s: String) -> String { Self.hideUser(Self.plain(s), names: userNames) }
        let faults = faults.map { f -> Fault in
            var f = f
            if let d = f.code?.domain, Self.hideUser(d, names: userNames) != d.precomposedStringWithCanonicalMapping { f.code?.domain = "other domain" }
            return f
        }
        var out = ["tokenpanda problem report",
                   "tokenpanda " + free(version ?? "unknown"),
                   "macOS " + free(macOS),
                   "Mac model " + free(model),
                   "",
                   "Open at login: " + (openAtLogin == .on ? "on" : openAtLogin == .needsApproval ? "waiting for the OK in Login Items" : "off"),
                   "Mac figures in the bar: " + onOff(macInBar),
                   "Nudges: " + onOff(nudges),
                   "List price equivalent: " + onOff(listPrice),
                   "Keep the Mac awake: " + onOff(keepAwake)]
        if keepAwake { out.append("  also while a session waits: " + onOff(keepAwakeWhileOpen)) }
        out.append("Reopen sessions after a restart: " + (restoreSessions ? "on, in " + reopenApp.title : "off"))
        out.append("")
        if folders.isEmpty { out.append("Status line entry: no settings folder found") }
        for (f, name) in zip(folders, Self.folderNames(folders.map(\.name))) {
            var state = f.installed ? "set up" : f.scriptMissing ? "not set up, the hook script is gone" : "not set up"
            if f.installed, f.hooksDisabled { state += ", disableAllHooks is on" }
            out.append("Status line entry in \(name): \(state)")
        }
        out.append("Last status line data: " + (lastData.map { Self.stamp($0, timeZone) } ?? "none read since the app started"))
        out.append("Sessions running: \(sessions)")
        out.append("")
        if faults.isEmpty { out.append("Errors shown: none") } else { out.append("Errors shown:"); out += faults.map { "- " + $0.text } }
        return out.joined(separator: "\n") + "\n"
    }

    /// The fixed name of each settings folder: ~/.claude and ~/.config/claude by name, any ~/.claude-something as
    /// ~/.claude-(name) (the suffix can be a client), anything else as "other folder". A name met twice is numbered.
    public static func folderNames(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { raw in
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = n == "~/.claude" || n == "~/.claude/" ? "~/.claude"
                : n == "~/.config/claude" || n == "~/.config/claude/" ? "~/.config/claude"
                : n.range(of: #"^~/\.claude[^/\n]+/?$"#, options: .regularExpression) != nil ? "~/.claude-(name)" : "other folder"
            seen[base, default: 0] += 1
            return seen[base]! == 1 ? base : "\(base) \(seen[base]!)"
        }
    }

    /// Version, macOS and model strings come from the system: kept to letters, digits and a few signs, at most 40 long.
    public static func plain(_ s: String) -> String {
        let kept = String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII || " .,()-_".unicodeScalars.contains($0) })
        return kept.isEmpty ? "unknown" : String(kept.prefix(40))
    }

    /// The guard on the system-filled fields: the account name and each part of the full name (two characters or more), compared in NFC and
    /// without case, become "(user)" wherever they stand as a word.
    public static func hideUser(_ text: String, names: [String]) -> String {
        var s = text.precomposedStringWithCanonicalMapping
        let parts = Set(names.flatMap { $0.precomposedStringWithCanonicalMapping.split(whereSeparator: { $0.isWhitespace }) }.map(String.init))
        for n in parts.filter({ $0.count >= 2 }).sorted(by: { $0.count > $1.count }) {
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: n) + #"(?![\p{L}\p{N}])"#
            s = s.replacingOccurrences(of: pattern, with: "(user)", options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    static func stamp(_ d: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}
