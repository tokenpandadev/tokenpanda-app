// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

// Session restore: which Claude Code sessions were open when the Mac last went down, and the Terminal file that resumes one.
// The record holds the session id, the folder and the transcript path, nothing of what was written. It lives only on this Mac.

public struct RestoreRecord: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var id: String
        public var folder: String
        public var transcript: String?
        public var lastSeen: Date
        public init(id: String, folder: String, transcript: String?, lastSeen: Date) {
            self.id = id; self.folder = folder; self.transcript = transcript; self.lastSeen = lastSeen
        }
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
    public mutating func apply(_ sessions: [OpenSession], now: Date) {
        var byId: [String: Entry] = [:]
        for e in entries where now.timeIntervalSince(e.lastSeen) <= Self.keepFor { byId[e.id] = e }
        for s in sessions {
            guard let folder = s.snapshot.projectDir else { continue }
            byId[s.snapshot.sessionId] = Entry(id: s.snapshot.sessionId, folder: folder, transcript: s.snapshot.transcriptPath, lastSeen: now)
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
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(RestoreRecord.self, from: d)
    }

    /// Written owner only.
    public func save(to url: URL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970; enc.outputFormatting = .sortedKeys
        guard let d = try? enc.encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// The Terminal file that resumes one session. Only a session id of the UUID shape and an existing folder get one,
/// both single quoted for the shell.
public enum Reopen {
    public static func isSessionId(_ s: String) -> Bool {
        s.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
    }

    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The transcript line Claude Code writes when Remote Control was on for the session. Not documented by Anthropic:
    /// if it stops appearing, sessions still reopen, without Remote Control.
    public static let remoteControlMarker = Data("\"type\":\"bridge-session\"".utf8)

    public static func hadRemoteControl(transcript: String?) -> Bool {
        guard let t = transcript, let d = try? Data(contentsOf: URL(fileURLWithPath: t), options: .mappedIfSafe) else { return false }
        return d.range(of: remoteControlMarker) != nil
    }

    /// The script. A login shell, so claude is found the way a Terminal window finds it. The file deletes itself first.
    /// With Remote Control, a start that fails falls back to a plain resume.
    public static func script(id: String, folder: String, remoteControl: Bool) -> String? {
        var isDir: ObjCBool = false
        guard isSessionId(id), FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { return nil }
        let resume = "claude --resume " + quote(id)
        let run = remoteControl ? resume + " --remote-control || " + resume : resume
        return "#!/bin/zsh -l\nrm -f -- \"$0\"\ncd " + quote(folder) + " || exit 1\n" + run + "\n"
    }
}
