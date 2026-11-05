// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Pace

/// The keys Limits.Record decodes, the same names its synthesized encoding writes. At file level: types nest one deep.
enum LimitsRecordKey: String, CodingKey { case used, resetsAt, previousResetsAt, contradicts, retired }

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
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: LimitsRecordKey.self)
            used = try c.decode(Double.self, forKey: .used)
            resetsAt = try c.decode(Date.self, forKey: .resetsAt)
            // the same ranges the feed parser keeps: a broken limits.json is dropped, never drawn
            guard used.isFinite, used >= 0, used <= SnapshotParser.maxPercent,
                  resetsAt.timeIntervalSince1970 >= 0, resetsAt.timeIntervalSince1970 < SnapshotParser.maxEpoch else {
                throw DecodingError.dataCorruptedError(forKey: .used, in: c, debugDescription: "out of range")
            }
            previousResetsAt = try c.decodeIfPresent(Date.self, forKey: .previousResetsAt)
            contradicts = try c.decodeIfPresent(Bool.self, forKey: .contradicts) ?? false
            retired = try c.decodeIfPresent(Bool.self, forKey: .retired) ?? false
        }
    }
    public var windows: [String: Record]
    public var asOf: Date
    /// Keys a reply came without: the plan no longer has them, the row is hidden. A record stays for the length check.
    public var hidden: Set<String>
    /// The newest reply carried no plan windows at all (an API key, Bedrock, Vertex): the stored ones are not drawn.
    public var planless: Bool
    public init(windows: [String: Record] = [:], asOf: Date, hidden: Set<String> = [], planless: Bool = false) {
        self.windows = windows; self.asOf = asOf; self.hidden = hidden; self.planless = planless
    }

    enum CodingKeys: String, CodingKey { case windows, asOf, hidden, planless }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windows = try c.decode([String: Record].self, forKey: .windows)
        asOf = try c.decode(Date.self, forKey: .asOf)
        hidden = try c.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        planless = try c.decodeIfPresent(Bool.self, forKey: .planless) ?? false
    }

    /// The keys always drawn, in this order; any other key the feed carries follows them.
    public static let fixedKeys = ["seven_day", "five_hour"]

    /// Applies the merged rate_limits of one scan (or one feed). Per key the latest reset wins, and inside one reset the
    /// highest percentage, the stored one included: the server's figure only rises within a window, lower ones are older
    /// cached replies. A new reset that follows a stored window which had already passed is the next window of the same
    /// account and is checked against the key's length. A reset that moves while the stored window still runs, earlier or
    /// later, is another account (/login, or two accounts open at once): it replaces the record without the check.
    /// A stored key the scan does not carry is retired, not deleted. `repliedAt` is the time of the newest reply in this
    /// scan: a key absent from a reply that came after its reset is hidden, since a reply carries every window the plan
    /// has. Before its reset a missing window only goes quiet.
    /// `carriedWindows` says whether any raw feed had a window entry, before passed or unreadable ones were dropped;
    /// only a reply with none at all makes the limits planless.
    public mutating func apply(_ rateLimits: [String: LimitWindow], at: Date, repliedAt: Date? = nil, carriedWindows: Bool? = nil) {
        for (key, w) in rateLimits {
            hidden.remove(key)
            guard let old = windows[key] else {
                windows[key] = Record(used: w.usedPercentage, resetsAt: w.resetsAt)
                continue
            }
            var rec = old
            rec.retired = false
            if w.resetsAt > old.resetsAt, old.resetsAt <= at {
                rec.previousResetsAt = old.resetsAt
                if let len = WindowKind.length(forKey: key) {
                    // consecutive windows of one key are at least one length apart; closer means the key's length is wrong
                    rec.contradicts = w.resetsAt.timeIntervalSince(old.resetsAt) < len - 60
                }
                rec.used = w.usedPercentage
                rec.resetsAt = w.resetsAt
            } else if w.resetsAt == old.resetsAt {
                rec.used = max(old.used, w.usedPercentage)
            } else {
                // merge already took the latest reset of every file, so no file carries the stored window any more
                rec = Record(used: w.usedPercentage, resetsAt: w.resetsAt)
            }
            windows[key] = rec
        }
        for key in windows.keys where rateLimits[key] == nil { windows[key]?.retired = true }
        if carriedWindows ?? !rateLimits.isEmpty { planless = false } else if repliedAt != nil { planless = true }
        if let r = repliedAt {
            for key in Set(windows.keys).union(Self.fixedKeys) where rateLimits[key] == nil {
                if let rec = windows[key], r < rec.resetsAt { continue }
                hidden.insert(key)
            }
        }
        asOf = at
    }

    /// The record the eyes, the spoken label and the nudges may use: none for a retired or hidden window, or planless.
    public func active(_ key: String) -> Record? {
        guard !planless, !hidden.contains(key), let r = windows[key], !r.retired else { return nil }
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
    public var lastWriteAt: Date?            // the newest file's write time, for "Live from Claude Code"
    public var scanError: String?
    public var formatChanged: Bool           // a file's rate_limits had entries and none of them read as a window
    public init(limits: Limits? = nil, sessions: [OpenSession] = [], lastWriteAt: Date? = nil, scanError: String? = nil, formatChanged: Bool = false) {
        self.limits = limits; self.sessions = sessions; self.lastWriteAt = lastWriteAt; self.scanError = scanError; self.formatChanged = formatChanged
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
    var parsed: [String: Parsed] = [:]              // file name to its last parse, kept while the file does not change
    public private(set) var parseCount = 0          // files parsed since launch, for the tests

    struct ReplyFigures: Equatable { var tokens: Int?; var cost: Double? }

    /// What tells a rewrite: the hook moves a new file over the old one, so the file number changes with every write,
    /// and the time and size change with nearly every one.
    struct Stamp: Equatable { var modified: Date; var size: Int; var fileNumber: Int }
    struct Parsed { var stamp: Stamp; var snapshot: Snapshot? }   // nil: the file did not read as a snapshot

    public init(dataDir: URL) {
        sessionsDir = dataDir.appendingPathComponent("sessions", isDirectory: true)
        limitsFile = dataDir.appendingPathComponent("limits.json")
        if let d = SafeFile.read(limitsFile) {
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
        var repliedAt: Date? = nil
        var formatChanged = false
        var carriedWindows = false
        var nextFigures: [String: ReplyFigures] = [:]
        for name in names where name.hasSuffix(".tmp") {
            // a hook run Claude Code cancelled between the write and the move leaves its .tmp file behind
            let url = sessionsDir.appendingPathComponent(name)
            if let mtime = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               OpenSessionsRule.shouldDelete(writtenAt: mtime, now: now) { try? fm.removeItem(at: url) }
        }
        var nextParsed: [String: Parsed] = [:]
        for name in names where name.hasSuffix(".json") {
            let url = sessionsDir.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path), let mtime = attrs[.modificationDate] as? Date else { continue }
            if OpenSessionsRule.shouldDelete(writtenAt: mtime, now: now) {
                try? fm.removeItem(at: url)
                continue
            }
            // a file is read and parsed again only when it changed since the last scan; an unchanged one gives the same
            // snapshot, so the reply check, the merge and the open and expiry rules below see what a fresh parse gives
            let stamp = Stamp(modified: mtime, size: (attrs[.size] as? NSNumber)?.intValue ?? -1,
                              fileNumber: (attrs[.systemFileNumber] as? NSNumber)?.intValue ?? -1)
            let entry: Parsed
            // only a regular file is kept: the stamp of a link says nothing about the file it names
            if let p = parsed[name], p.stamp == stamp, attrs[.type] as? FileAttributeType == .typeRegular {
                entry = p
            } else {
                parseCount += 1
                entry = Parsed(stamp: stamp, snapshot: SafeFile.read(url).flatMap { SnapshotParser.parse($0, writtenAt: mtime) })
            }
            nextParsed[name] = entry
            guard let snap = entry.snapshot else { continue }
            if mtime > (lastWrite ?? .distantPast) { lastWrite = mtime }
            let figures = ReplyFigures(tokens: snap.currentUsageTokens, cost: snap.totalCostUSD)
            // a reply: a session seen before whose figures moved; the first sight of a file after launch is not one
            let replied = snap.currentUsageTokens != nil && figuresSeen[snap.sessionId].map { $0 != figures } == true
            if snap.rateLimitsUnreadable {
                formatChanged = true      // windows under keys the parser does not know: never read as "no windows"
            } else if snap.rateLimits != nil || replied {
                // a reply without rate_limits (an API key, Bedrock, Vertex) is a feed with no plan windows
                feeds.append(snap.rateLimits ?? [:])
                if snap.rateLimitsCarriedWindows { carriedWindows = true }
                if mtime > (newestLimits ?? .distantPast) { newestLimits = mtime }
                if replied { repliedAt = max(repliedAt ?? mtime, mtime) }
            }
            nextFigures[snap.sessionId] = figures
            if OpenSessionsRule.isOpen(writtenAt: mtime, now: now) { sessions.append(OpenSession(snapshot: snap)) }
        }
        figuresSeen = nextFigures
        parsed = nextParsed   // a deleted or vanished file leaves the cache with its scan
        if let t = newestLimits, t > (limits?.asOf ?? .distantPast) {
            var l = limits ?? Limits(asOf: t)
            l.apply(Limits.merge(feeds, now: now), at: t, repliedAt: repliedAt, carriedWindows: carriedWindows)
            if l != limits {
                limits = l
                persist()
            }
        }
        sessions.sort { $0.usedPercentage > $1.usedPercentage }
        return FeedState(limits: limits, sessions: sessions, lastWriteAt: lastWrite, formatChanged: formatChanged)
    }

    func persist() {
        guard let limits else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        do {
            let d = try enc.encode(limits)
            try FileManager.default.createDirectory(at: limitsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try d.write(to: limitsFile, options: .atomic)
        } catch {
            FileLog.failed("limits.json", error)
        }
    }
}

/// When a write event in the sessions folder scans the feed. Every session's status line run writes a file, and with
/// many sessions open the events come in bursts. The first event after a quiet second scans at once; the events that
/// follow within `gap` of a scan are folded into one trailing scan at the end of the gap, so the last write is always
/// read, at most `gap` late. The 5 s timer scans as before and counts as a scan here.
public struct FeedPacer: Sendable, Equatable {
    public static let gap: TimeInterval = 1
    public enum Step: Sendable, Equatable { case scanNow, scanAt(Date), wait }

    var lastScan: Date?
    var trailing: Date?      // the trailing scan already set, which will read every write before it

    public init() {}

    /// A write event at `now`: scan now, set the trailing scan for a time, or wait for the one already set.
    public mutating func event(now: Date) -> Step {
        if trailing != nil { return .wait }
        guard let last = lastScan, now.timeIntervalSince(last) < Self.gap, now >= last else {
            // counted as a scan here: the scan itself runs in a task a moment later, and the events before it starts
            // fold into the trailing scan instead of each scanning now
            lastScan = now
            return .scanNow
        }
        let at = last.addingTimeInterval(Self.gap)
        trailing = at
        return .scanAt(at)
    }

    /// A scan starts at `now`, from an event, the timer or the trailing scan (`trailing: true`, which clears it).
    public mutating func scanned(at now: Date, trailing isTrailing: Bool = false) {
        lastScan = now
        if isTrailing { trailing = nil }
    }
}
