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
        public init(id: String, folder: String, transcript: String?, lastSeen: Date, name: String? = nil, options: [String]? = nil) {
            self.id = id; self.folder = folder; self.transcript = transcript; self.lastSeen = lastSeen; self.name = name; self.options = options
        }
        /// What the notifications call the session: its name, or its folder's name when it has none.
        public var label: String { name ?? (folder as NSString).lastPathComponent }
    }

    /// How one session was started, read while it runs.
    public struct Launch: Sendable, Equatable {
        public var name: String?
        public var options: [String]?
        public init(name: String?, options: [String]?) { self.name = name; self.options = options }
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
            byId[id] = Entry(id: id, folder: folder, transcript: s.snapshot.transcriptPath, lastSeen: now,
                             name: launch.map { $0.name } ?? old?.name, options: launch?.options ?? old?.options)
        }
        entries = byId.values.sorted { $0.id < $1.id }
        lastScan = now
    }

    /// The sessions that were open when the app last ran, if that was before this boot. Empty otherwise.
    public func lost(bootTime: Date, now: Date) -> [Entry] {
        guard lastScan < bootTime, now.timeIntervalSince(lastScan) <= Self.offerWithin else { return [] }
        return entries.filter { lastScan.timeIntervalSince($0.lastSeen) <= Self.keepFor && Reopen.isSessionId($0.id) }
    }

    public static func load(from url: URL) -> RestoreRecord? {
        guard let d = SafeFile.read(url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(RestoreRecord.self, from: d)
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
