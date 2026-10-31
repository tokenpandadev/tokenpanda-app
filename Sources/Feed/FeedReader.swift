// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Pace

/// The last limits the feed carried, kept so the figures survive the per session files being dropped.
/// Only the windows and the snapshot time: no path, no model, no session id.
public struct Limits: Sendable, Equatable, Codable {
    public struct Record: Sendable, Equatable, Codable {
        public var used: Double
        public var resetsAt: Date
        public var previousResetsAt: Date?   // the reset before this one, for the length check
        public var contradicts: Bool         // a consecutive reset closer than the key's length: unknown window
        public var retired: Bool             // absent from every file of the last scan that carried limits
        public init(used: Double, resetsAt: Date, previousResetsAt: Date? = nil, contradicts: Bool = false, retired: Bool = false) {
            self.used = used; self.resetsAt = resetsAt; self.previousResetsAt = previousResetsAt; self.contradicts = contradicts; self.retired = retired
        }
        enum CodingKeys: String, CodingKey { case used, resetsAt, previousResetsAt, contradicts, retired }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            used = try c.decode(Double.self, forKey: .used)
            resetsAt = try c.decode(Date.self, forKey: .resetsAt)
            previousResetsAt = try c.decodeIfPresent(Date.self, forKey: .previousResetsAt)
            contradicts = try c.decodeIfPresent(Bool.self, forKey: .contradicts) ?? false
            retired = try c.decodeIfPresent(Bool.self, forKey: .retired) ?? false
        }
    }
    public var windows: [String: Record]
    public var asOf: Date
    /// Keys a reply came without: the plan no longer has them, the row is hidden. A record stays for the length check.
    public var hidden: Set<String>
    public init(windows: [String: Record] = [:], asOf: Date, hidden: Set<String> = []) { self.windows = windows; self.asOf = asOf; self.hidden = hidden }

    enum CodingKeys: String, CodingKey { case windows, asOf, hidden }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windows = try c.decode([String: Record].self, forKey: .windows)
        asOf = try c.decode(Date.self, forKey: .asOf)
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
    }

    /// The keys always drawn, in this order; any other key the feed carries follows them.
    public static let fixedKeys = ["seven_day", "five_hour"]

    /// Applies the merged rate_limits of one scan (or one feed). Per key the latest reset wins, and inside one reset the
    /// highest percentage, the stored one included: the server's figure only rises within a window, lower ones are older
    /// cached replies. A window whose reset moved is checked against the key's length.
    /// A stored key the scan does not carry is retired, not deleted. `replied` says a session answered in this scan:
    /// a key absent then is hidden, since a reply carries every window the plan has.
    public mutating func apply(_ rateLimits: [String: LimitWindow], at: Date, replied: Bool = false) {
        for (key, w) in rateLimits {
            hidden.remove(key)
            guard let old = windows[key] else {
                windows[key] = Record(used: w.usedPercentage, resetsAt: w.resetsAt)
                continue
            }
            var rec = old
            rec.retired = false
            if w.resetsAt > old.resetsAt {
                rec.previousResetsAt = old.resetsAt
                if let len = WindowKind.length(forKey: key) {
                    // consecutive windows of one key are at least one length apart; closer means the key's length is wrong
                    rec.contradicts = w.resetsAt.timeIntervalSince(old.resetsAt) < len - 60
                }
                rec.used = w.usedPercentage
                rec.resetsAt = w.resetsAt
            } else if w.resetsAt == old.resetsAt {
                rec.used = max(old.used, w.usedPercentage)
            }
            // an older reset than the stored one is a stale cached figure: the stored window stands
            windows[key] = rec
        }
        for key in windows.keys where rateLimits[key] == nil { windows[key]?.retired = true }
        if replied {
            for key in Set(windows.keys).union(Self.fixedKeys) where rateLimits[key] == nil { hidden.insert(key) }
        }
        asOf = at
    }

    /// The record the eyes, the spoken label and the nudges may use: none for a retired or hidden window.
    public func active(_ key: String) -> Record? {
        guard !hidden.contains(key), let r = windows[key], !r.retired else { return nil }
        return r
    }

    public func isUnknown(_ key: String) -> Bool {
        WindowKind.length(forKey: key) == nil || (windows[key]?.contradicts ?? false)
    }

    /// One scan's rate_limits merged across every session file that carries them: per key the latest reset that has not
    /// passed, and the highest percentage at that reset.
    public static func merge(_ feeds: [[String: LimitWindow]], now: Date) -> [String: LimitWindow] {
        var out: [String: LimitWindow] = [:]
        for feed in feeds {
            for (key, w) in feed where w.resetsAt > now {
                if let o = out[key] {
                    if w.resetsAt > o.resetsAt || (w.resetsAt == o.resetsAt && w.usedPercentage > o.usedPercentage) { out[key] = w }
                } else {
                    out[key] = w
                }
            }
        }
        return out
    }
}

public struct OpenSession: Sendable, Equatable {
    public var snapshot: Snapshot
    public init(snapshot: Snapshot) { self.snapshot = snapshot }
    public var usedPercentage: Double { snapshot.contextUsedPercentage ?? 0 }
}

public struct FeedState: Sendable, Equatable {
    public var limits: Limits?
    public var sessions: [OpenSession]       // open, sorted by context used, largest first
    public var lastWriteAt: Date?            // the newest file's write time, for "Usage live"
    public var scanError: String?
    public init(limits: Limits? = nil, sessions: [OpenSession] = [], lastWriteAt: Date? = nil, scanError: String? = nil) {
        self.limits = limits; self.sessions = sessions; self.lastWriteAt = lastWriteAt; self.scanError = scanError
    }
    public func isLive(now: Date) -> Bool {
        guard let t = lastWriteAt else { return false }
        return now.timeIntervalSince(t) <= OpenSessionsRule.liveHeaderWithin
    }
}

/// Reads the snapshot folder the hook writes into, keeps the last limits, drops files after 60 s.
public actor FeedReader {
    public nonisolated let sessionsDir: URL
    let limitsFile: URL
    var limits: Limits?
    var figuresSeen: [String: ReplyFigures] = [:]   // session id to the figures of its file in the last scan, to tell a reply

    struct ReplyFigures: Equatable { var tokens: Int?; var cost: Double? }

    public init(dataDir: URL) {
        sessionsDir = dataDir.appendingPathComponent("sessions", isDirectory: true)
        limitsFile = dataDir.appendingPathComponent("limits.json")
        if let d = try? Data(contentsOf: limitsFile) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
            limits = try? dec.decode(Limits.self, from: d)
        }
    }

    public func scan(now: Date = Date()) -> FeedState {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: sessionsDir.path) else {
            return FeedState(limits: limits, sessions: [], lastWriteAt: nil)
        }
        var sessions: [OpenSession] = []
        var feeds: [[String: LimitWindow]] = []
        var newestLimits: Date? = nil
        var lastWrite: Date? = nil
        var replied = false
        var nextFigures: [String: ReplyFigures] = [:]
        for name in names where name.hasSuffix(".json") {
            let url = sessionsDir.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path), let mtime = attrs[.modificationDate] as? Date else { continue }
            if OpenSessionsRule.shouldDelete(writtenAt: mtime, now: now) {
                try? fm.removeItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url), let snap = SnapshotParser.parse(data, writtenAt: mtime) else { continue }
            if mtime > (lastWrite ?? .distantPast) { lastWrite = mtime }
            let figures = ReplyFigures(tokens: snap.currentUsageTokens, cost: snap.totalCostUSD)
            if let rl = snap.rateLimits {
                feeds.append(rl)
                if mtime > (newestLimits ?? .distantPast) { newestLimits = mtime }
                // a reply: a session seen before whose figures moved; the first sight of a file after launch is not one
                if snap.currentUsageTokens != nil, let before = figuresSeen[snap.sessionId], before != figures { replied = true }
            }
            nextFigures[snap.sessionId] = figures
            if OpenSessionsRule.isOpen(writtenAt: mtime, now: now) { sessions.append(OpenSession(snapshot: snap)) }
        }
        figuresSeen = nextFigures
        if let t = newestLimits, t > (limits?.asOf ?? .distantPast) {
            var l = limits ?? Limits(asOf: t)
            l.apply(Limits.merge(feeds, now: now), at: t, replied: replied)
            if l != limits {
                limits = l
                persist()
            }
        }
        sessions.sort { $0.usedPercentage > $1.usedPercentage }
        return FeedState(limits: limits, sessions: sessions, lastWriteAt: lastWrite)
    }

    func persist() {
        guard let limits else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(limits) {
            try? FileManager.default.createDirectory(at: limitsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: limitsFile, options: .atomic)
        }
    }
}
