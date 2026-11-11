// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// When the token aggregate must be built from every record, not only when a transcript moved: the first time, on a
/// new day (the "today" window), and once a record has crossed the edge of the 7 or 30 day window (TokenSummary.nextEdge),
/// because those windows roll from now while no file changes. Until 0.1.14 only the day counted, so a quiet day kept up
/// to a day of records past the edge (audit F-3).
public enum TokenRefresh {
    public static func needsAllRecords(lastDay: Date?, today: Date, haveTokens: Bool, now: Date? = nil, nextEdge: Date? = nil) -> Bool {
        if !haveTokens || lastDay != today { return true }
        guard let now, let nextEdge else { return false }
        return now > nextEdge
    }

    /// One pass of the controller: whether to ask the store for changes only, and whether to build the aggregate anew
    /// from the records that pass returns (new records, or all of them on a new day or past an edge).
    public static func plan(lastDay: Date?, today: Date, haveTokens: Bool, now: Date? = nil,
                            nextEdge: Date? = nil) -> (onlyIfChanged: Bool, rebuildOnNewDay: Bool) {
        let all = needsAllRecords(lastDay: lastDay, today: today, haveTokens: haveTokens, now: now, nextEdge: nextEdge)
        return (!all, all)
    }

    public static func rebuild(plan: (onlyIfChanged: Bool, rebuildOnNewDay: Bool), versionMoved: Bool) -> Bool {
        versionMoved || plan.rebuildOnNewDay
    }
}

/// Which summary may replace the one on screen: two passes can overlap (launch, the popover opening and the timer each
/// start one), and the older one's summary can arrive last. Give it every result's sequence before assigning the summary
/// built from it; an older sequence is refused (0.1.19, review: the older summary replaced the newer one).
public struct RefreshOrder: Sendable, Equatable {
    public private(set) var lastApplied = -1
    public init() {}
    /// true when the result of this sequence is newer than the last one taken, and takes it.
    public mutating func accept(_ sequence: Int) -> Bool {
        guard sequence > lastApplied else { return false }
        lastApplied = sequence
        return true
    }
}

/// One transcript pass at a time, and none lost: a pass asked for while one runs (the one promised when a new settings
/// folder joins the roots, or a timer's) is remembered and run once when the running one ends. Until the second review of
/// 0.1.19 it was dropped at the busy guard, and the new folder's tokens waited for the next timer pass, up to 300 s.
public struct PassGate: Sendable, Equatable {
    public private(set) var busy = false
    public private(set) var pending = false
    public init() {}
    /// true when a pass may start now; false when one runs, which then runs once more when it ends.
    public mutating func begin() -> Bool {
        if busy { pending = true; return false }
        busy = true
        return true
    }
    /// The running pass ended: true when one was asked for meanwhile, to be run now (the gate stays closed for it).
    public mutating func end() -> Bool {
        if pending { pending = false; return true }
        busy = false
        return false
    }
}

/// Reads transcripts incrementally: every file remembers its byte offset and the message ids it has seen.
/// A file that shrank is read again from the start. Nothing is ever loaded whole. Files are kept by device and inode,
/// so a file reached through a linked folder is read once (0.1.19). A message id is counted once across the whole store:
/// a copy of a transcript in another folder (a ~/.claude-backup) or a resumed session that carries earlier replies never
/// counts them twice (second audit of 0.1.19, F-70: ids were kept per file, and a backup copy doubled every figure).
public actor TranscriptStore {
    struct FileState {
        var url: URL? = nil          // the path it was read through; another path for the same id starts over
        var offset: UInt64 = 0
        var ids: Set<String> = []
        var records: [UsageRecord] = []
        var recordIds: [String] = []  // the message id of each record, for the count across files
        var skipping = false      // inside a line past maxLine: dropped up to its newline, also across reads
    }

    /// A transcript line longer than this is skipped. Claude Code's lines are kilobytes, a pasted image a few megabytes.
    public static let maxLine = 10 << 20

    public private(set) var roots: [URL]
    var files: [FileID: FileState] = [:]
    public private(set) var lastError: String?
    public private(set) var fileCount = 0
    public private(set) var version = 0      // moves when a record was added or a file was read again

    var sequence = 0

    public init(roots: [URL]) { self.roots = TranscriptLocator.unique(roots) }

    /// A new set of roots, for a settings folder made after launch. Files already read keep their offsets and records;
    /// a file under no root any more drops out at the next refresh. Returns whether the set changed (0.1.19).
    @discardableResult
    public func setRoots(_ roots: [URL]) -> Bool {
        let next = TranscriptLocator.unique(roots)
        guard next != self.roots else { return false }
        self.roots = next
        return true
    }

    public struct Result: Sendable {
        public var records: [UsageRecord]
        public var fileCount: Int
        public var rootsExist: Bool
        public var error: String?
        public var cause: (any Error)?   // the error itself, for the problem report's codes (never its text)
        public var version: Int
        /// Strictly increasing per refresh call, also when nothing moved: the order the passes ran in (RefreshOrder).
        public var sequence: Int
    }

    var lastReportedVersion = -1

    /// Enumerates the files and reads what is new. Returns every record kept; with onlyIfChanged the records
    /// come back empty when nothing moved since the last call, so the caller keeps its aggregate without a copy.
    public func refresh(now: Date = Date(), chunk: Int = 1 << 20, maxLine: Int = TranscriptStore.maxLine, onlyIfChanged: Bool = false) -> Result {
        sequence += 1
        let fm = FileManager.default
        let rootsExist = roots.contains { fm.fileExists(atPath: $0.path) }
        let found = TranscriptLocator.files(under: roots, now: now)
        let present = Set(found.map(\.id))
        for id in files.keys where !present.contains(id) { files.removeValue(forKey: id); version += 1 }
        var error: String? = nil   // this pass only: a later pass without an error clears it
        var cause: (any Error)? = nil
        for f in found {
            var st = files[f.id] ?? FileState(url: f.url)
            // truncated or rewritten, or the id now names a file at another path: start over
            if f.size < st.offset || st.url != f.url { st = FileState(url: f.url); version += 1 }
            if f.size > st.offset {
                do { try read(f, into: &st, chunk: chunk, maxLine: maxLine) } catch let e { error = e.localizedDescription; cause = e }
            }
            files[f.id] = st
        }
        lastError = error
        fileCount = found.count
        let unchanged = onlyIfChanged && version == lastReportedVersion
        lastReportedVersion = version
        let all = unchanged ? [] : counted()
        return Result(records: all, fileCount: found.count, rootsExist: rootsExist, error: error, cause: cause, version: version, sequence: sequence)
    }

    /// Every record kept, each message id once: the files of the first root first (the usual places come first), then by
    /// path, so the same copy wins every pass.
    func counted() -> [UsageRecord] {
        func rank(_ st: FileState) -> Int {
            guard let p = st.url?.path else { return roots.count }
            return roots.firstIndex { p.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") } ?? roots.count
        }
        let ordered = files.values.map { (rank($0), $0.url?.path ?? "", $0) }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        var seen = Set<String>()
        var out: [UsageRecord] = []
        out.reserveCapacity(files.values.reduce(0) { $0 + $1.records.count })
        for (_, _, st) in ordered {
            for (i, r) in st.records.enumerated() where seen.insert(st.recordIds[i]).inserted { out.append(r) }
        }
        return out
    }

    func read(_ f: TranscriptFile, into st: inout FileState, chunk: Int, maxLine: Int) throws {
        // POSIX read into one buffer: no Foundation file object holds the file's pages across the pass
        let fd = open(f.url.path, O_RDONLY)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
        defer { close(fd) }
        guard lseek(fd, off_t(st.offset), SEEK_SET) >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var buffer: [UInt8] = []
        buffer.reserveCapacity(chunk * 2)
        var piece = [UInt8](repeating: 0, count: chunk)
        while true {
            let n = piece.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, chunk) }
            if n < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
            if n == 0 { break }
            buffer.append(contentsOf: piece[0..<n])
            if st.skipping {
                // the rest of a line past the limit: drop it up to its newline
                guard let nl = buffer.firstIndex(of: 0x0A) else { st.offset += UInt64(buffer.count); buffer.removeAll(keepingCapacity: true); continue }
                st.offset += UInt64(nl + 1)
                buffer.removeFirst(nl + 1)
                st.skipping = false
            }
            var start = 0
            buffer.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                while start < ptr.count, let hit = memchr(base + start, 0x0A, ptr.count - start) {
                    let nl = UnsafePointer<UInt8>(hit.assumingMemoryBound(to: UInt8.self)) - base
                    consume(UnsafeBufferPointer(rebasing: ptr[start..<nl]), f, &st)
                    start = nl + 1
                }
            }
            st.offset += UInt64(start)
            buffer.removeFirst(start)
            if buffer.count > maxLine {
                // a line past the limit without its newline yet: it is never decoded, and never held whole
                st.offset += UInt64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                st.skipping = true
            }
        }
        // whatever is left has no newline yet; the offset stays before it and the line is read whole next time
    }

    static let marker = Array("\"type\":\"assistant\"".utf8)
    static let markerSpaced = Array("\"type\": \"assistant\"".utf8)

    /// A cheap scan for the assistant marker before any copy or decode.
    static func looksLikeAssistant(_ line: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = line.baseAddress, line.count > marker.count else { return false }
        return memmem(base, line.count, marker, marker.count) != nil || memmem(base, line.count, markerSpaced, markerSpaced.count) != nil
    }

    func consume(_ line: UnsafeBufferPointer<UInt8>, _ f: TranscriptFile, _ st: inout FileState) {
        guard !line.isEmpty, Self.looksLikeAssistant(line) else { return }
        consume(Data(buffer: line), f, &st)
    }

    func consume(_ line: Data, _ f: TranscriptFile, _ st: inout FileState) {
        guard !line.isEmpty, TranscriptParser.looksLikeAssistant(line) else { return }
        guard let p = TranscriptParser.parse(line: line, file: f) else { return }
        // one assistant line per content block, same id and same usage: keep the first, skip the repeats
        guard !st.ids.contains(p.messageId) else { return }
        st.ids.insert(p.messageId)
        st.records.append(p.record)
        st.recordIds.append(p.messageId)
        version += 1
    }
}
