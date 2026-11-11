// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

// Session restore: which Claude Code sessions were open when the Mac last went down, and the .command file that resumes one in Terminal, iTerm or Ghostty.
// The record holds the session id, the folder, the transcript path, the session's name and the options it was started with,
// nothing of what was written. It lives only on this Mac.

public struct RestoreRecord: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var id: String
        public var folder: String
        public var transcript: String?
        public var lastSeen: Date
        public var name: String?          // the session's name (-n or /rename), when it has one
        public var options: [String]?     // the start options a reopen keeps; nil when they could not be read
        /// The settings folder the session ran under (CLAUDE_CONFIG_DIR for a second account). nil reads as ~/.claude,
        /// also in a restore.json written before 0.1.19, which did not keep it.
        public var configDir: String?
        public init(id: String, folder: String, transcript: String?, lastSeen: Date, name: String? = nil, options: [String]? = nil,
                    configDir: String? = nil) {
            self.id = id; self.folder = folder; self.transcript = transcript; self.lastSeen = lastSeen; self.name = name; self.options = options
            self.configDir = configDir
        }
        /// What the notifications call the session: its name, or its folder's name when it has none.
        public var label: String { name ?? (folder as NSString).lastPathComponent }
    }

    /// How one session was started, read while it runs.
    public struct Launch: Sendable, Equatable {
        public var name: String?
        public var options: [String]?
        public var configDir: String?   // the settings folder whose sessions folder holds the session's file
        public init(name: String?, options: [String]?, configDir: String? = nil) { self.name = name; self.options = options; self.configDir = configDir }
    }
    public var entries: [Entry]
    public var lastScan: Date
    public init(entries: [Entry] = [], lastScan: Date) { self.entries = entries; self.lastScan = lastScan }

    /// A session still counts this long after its last feed. At a restart Terminal closes the sessions before the app quits,
    /// sometimes minutes before when Terminal asks to close its windows, so a shorter time loses them.
    public static let keepFor: TimeInterval = 600
    /// A record older than this at boot is not offered: after a week away the sessions are history, not lost work.
    public static let offerWithin: TimeInterval = 7 * 24 * 3600

    /// Applies one scan's open sessions: seen ones are refreshed, others drop out once keepFor has passed since their last feed.
    /// A session's name and options come from launches, by session id; when it is missing there, the last ones read stay.
    public mutating func apply(_ sessions: [OpenSession], launches: [String: Launch] = [:], now: Date) {
        var byId: [String: Entry] = [:]
        for e in entries where now.timeIntervalSince(e.lastSeen) <= Self.keepFor { byId[e.id] = e }
        for s in sessions {
            guard let folder = s.snapshot.projectDir else { continue }
            let id = s.snapshot.sessionId
            let old = byId[id]
            let launch = launches[id]
            // the settings folder: from Claude Code's session file, else the one kept, else the one the transcript lies in
            let config = launch?.configDir ?? old?.configDir ?? Reopen.configDir(fromTranscript: s.snapshot.transcriptPath)
            byId[id] = Entry(id: id, folder: folder, transcript: s.snapshot.transcriptPath, lastSeen: now,
                             name: launch.map { $0.name } ?? old?.name, options: launch?.options ?? old?.options, configDir: config)
        }
        entries = byId.values.sorted { $0.id < $1.id }
        lastScan = now
    }

    /// The sessions that were open when the app last ran, if that was before this boot. Empty otherwise.
    public func lost(bootTime: Date, now: Date) -> [Entry] {
        guard lastScan < bootTime, now.timeIntervalSince(lastScan) <= Self.offerWithin else { return [] }
        return entries.filter { lastScan.timeIntervalSince($0.lastSeen) <= Self.keepFor && Reopen.isSessionId($0.id) }
    }

    /// A record written before 0.1.19 may hold an inline JSON value of --settings or --mcp-config: it is dropped here,
    /// so it is never in a script and goes from the file at the next save.
    public static func load(from url: URL) -> RestoreRecord? {
        guard let d = SafeFile.read(url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        guard var r = try? dec.decode(RestoreRecord.self, from: d) else { return nil }
        for i in r.entries.indices { r.entries[i].options = r.entries[i].options.map { LaunchOptions.withoutInlineJSON($0).options } }
        return r
    }

    /// The file is written when a session comes or goes or a name, the options or the settings folder change, and
    /// otherwise when only the last scan moved, at most this often: the offer after a restart judges the record's last
    /// scan, and a record written only on a change kept the time of the last change, so sessions open unchanged for
    /// over seven days were never offered (0.1.19, review).
    public static let scanSaveEvery: TimeInterval = 5 * 60

    /// Whether this scan writes the file: the sessions changed, or the last scan is scanSaveEvery past the one written.
    /// While the restart offer is unanswered the record from before the restart stays on disk, so a relaunch before the
    /// answer offers the same sessions again; at most an hour, so an offer nobody took does not come back days later
    /// (0.1.19, flow test of the second full pass: the first scan after a restart wrote an empty record within 20 s).
    public static let holdWhileOffered: TimeInterval = 3600

    public static func holdForOffer(pending: Bool, offeredAt: Date?, now: Date) -> Bool {
        guard pending, let at = offeredAt else { return false }
        return now.timeIntervalSince(at) < holdWhileOffered
    }

    public static func shouldSave(key: [String], savedKey: [String], lastScan: Date, savedScan: Date?) -> Bool {
        if key != savedKey { return true }
        guard let saved = savedScan else { return true }
        return lastScan.timeIntervalSince(saved) >= scanSaveEvery
    }

    /// What tells a change of the sessions for shouldSave: id, name, options and settings folder of each.
    public var saveKey: [String] {
        entries.map { [$0.id, $0.name ?? "", ($0.options ?? []).joined(separator: "\u{1}"), $0.configDir ?? ""].joined(separator: "\u{2}") }
    }

    /// Written owner only. A failure is logged and returned.
    @discardableResult
    public func save(to url: URL) -> Error? {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970; enc.outputFormatting = .sortedKeys
        do {
            let d = try enc.encode(self)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try d.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return nil
        } catch {
            FileLog.failed(url.lastPathComponent, error)
            return error
        }
    }
}

/// The restart notice said once more at the first open of the panel, when it was posted and the sessions are still
/// waiting: right after a login macOS shows its own "Login Item Added" banner, and the notice can go under it and be
/// found only in Notification Center (flow test 11.2, 0.1.18). Once per launch, never before the notice was posted.
public struct OfferRepeat: Sendable, Equatable {
    public private(set) var posted = false
    public private(set) var repeated = false
    public init() {}
    public mutating func didPost() { posted = true }
    /// true once: the panel opened after the notice was posted while its sessions still wait for Reopen.
    public mutating func panelOpened(pending: Bool) -> Bool {
        guard posted, !repeated, pending else { return false }
        repeated = true
        return true
    }
}

/// The .command file that resumes one session, in whichever of Terminal, iTerm or Ghostty is picked. Only a session id of the UUID shape and an existing folder get one,
/// both single quoted for the shell.
public enum Reopen {
    public static func isSessionId(_ s: String) -> Bool {
        s.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
    }

    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The transcript line Claude Code writes when Remote Control was on for the session. Not documented by Anthropic:
    /// if it stops appearing, sessions still reopen, without Remote Control.
    public static let remoteControlMarker = Data("\"type\":\"bridge-session\"".utf8)

    /// transcript_path comes from the feed: it is opened only when it is a regular file, never a FIFO or a device.
    public static func hadRemoteControl(transcript: String?) -> Bool {
        guard let t = transcript, SafeFile.isRegularFile(t),
              let d = try? Data(contentsOf: URL(fileURLWithPath: t), options: .mappedIfSafe) else { return false }
        return d.range(of: remoteControlMarker) != nil
    }

}
