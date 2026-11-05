// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed

/// The feed scan keeps a file's parse while the file does not change, and folder events are paced (0.1.16).
struct FeedCacheTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return url
    }

    /// As the hook writes: a new file moved over the old one.
    func write(_ name: String, _ data: Data, in dir: URL, at time: Date) throws {
        let url = dir.appendingPathComponent("sessions/\(name).json")
        let tmp = dir.appendingPathComponent("sessions/\(name).json.tmp")
        try data.write(to: tmp)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: tmp.path)
        _ = rename(tmp.path, url.path)
    }

    /// The sample with its token and cost figures moved, as after a reply.
    func replied(_ data: Data, extraTokens: Int) throws -> Data {
        var d = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var cw = try #require(d["context_window"] as? [String: Any])
        var cu = try #require(cw["current_usage"] as? [String: Any])
        cu["output_tokens"] = (cu["output_tokens"] as? Int ?? 0) + extraTokens
        cw["current_usage"] = cu
        d["context_window"] = cw
        return try JSONSerialization.data(withJSONObject: d)
    }

    @Test func unchangedFileIsNotParsedAgainAndChangedOneIs() async throws {
        let dir = try tempDir()
        let now = Date()
        let reader = FeedReader(dataDir: dir)
        try write("a", try fixture("feed-sample"), in: dir, at: now.addingTimeInterval(-1))
        try write("b", try fixture("feed-first"), in: dir, at: now.addingTimeInterval(-1))
        let first = await reader.scan(now: now)
        #expect(await reader.parseCount == 2)
        let second = await reader.scan(now: now.addingTimeInterval(1))
        #expect(await reader.parseCount == 2)        // nothing written: both parses kept
        #expect(second.sessions == first.sessions)
        try write("a", try fixture("feed-sample"), in: dir, at: now.addingTimeInterval(1.5))
        let third = await reader.scan(now: now.addingTimeInterval(2))
        #expect(await reader.parseCount == 3)        // only the rewritten file
        #expect(third.sessions.count == 2)
        #expect(third.lastWriteAt == now.addingTimeInterval(1.5))
    }

    @Test func unchangedFilesStillCloseAndExpireByTheClock() async throws {
        let dir = try tempDir()
        let now = Date()
        let reader = FeedReader(dataDir: dir)
        try write("a", try fixture("feed-sample"), in: dir, at: now)
        #expect(await reader.scan(now: now).sessions.count == 1)
        // no write since: the kept parse leaves the open list after 10 s and the file goes after 60 s
        let later = await reader.scan(now: now.addingTimeInterval(11))
        #expect(later.sessions.isEmpty)
        #expect(later.isLive(now: now.addingTimeInterval(11)))
        #expect(await reader.parseCount == 1)
        let gone = await reader.scan(now: now.addingTimeInterval(61))
        #expect(gone.sessions.isEmpty)
        #expect(gone.lastWriteAt == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("sessions/a.json").path))
        // written again after that: read afresh, the first sight again
        try write("a", try fixture("feed-sample"), in: dir, at: now.addingTimeInterval(62))
        #expect(await reader.scan(now: now.addingTimeInterval(62)).sessions.count == 1)
        #expect(await reader.parseCount == 2)
    }

    @Test func repliesAreStillToldWithKeptParses() async throws {
        // a session without rate_limits that replies makes the record planless; a kept parse is never a reply
        let dir = try tempDir()
        let now = Date(timeIntervalSince1970: 1791900924)
        let reader = FeedReader(dataDir: dir)
        var plain = try #require(try JSONSerialization.jsonObject(with: try fixture("feed-sample")) as? [String: Any])
        plain.removeValue(forKey: "rate_limits")
        let base = try JSONSerialization.data(withJSONObject: plain)
        try write("a", base, in: dir, at: now)
        #expect(await reader.scan(now: now).limits == nil)        // the first sight is not a reply
        #expect(await reader.scan(now: now.addingTimeInterval(1)).limits == nil)   // unchanged: kept, not a reply
        try write("a", try replied(base, extraTokens: 50), in: dir, at: now.addingTimeInterval(2))
        let st = await reader.scan(now: now.addingTimeInterval(2))
        #expect(st.limits?.planless == true)
        #expect(st.limits?.asOf == now.addingTimeInterval(2))
    }

    @Test func pacerScansAtOnceThenFoldsABurstIntoOneTrailingScan() {
        var p = FeedPacer()
        let t = Date(timeIntervalSince1970: 1_000_000)
        #expect(p.event(now: t) == .scanNow)
        p.scanned(at: t)
        #expect(p.event(now: t.addingTimeInterval(0.1)) == .scanAt(t.addingTimeInterval(FeedPacer.gap)))
        #expect(p.event(now: t.addingTimeInterval(0.2)) == .wait)
        #expect(p.event(now: t.addingTimeInterval(0.9)) == .wait)
        // the timer scanning meanwhile does not drop the trailing scan: a write after its read still needs one
        p.scanned(at: t.addingTimeInterval(0.5))
        #expect(p.event(now: t.addingTimeInterval(0.95)) == .wait)
        p.scanned(at: t.addingTimeInterval(FeedPacer.gap), trailing: true)
        // an event just after the trailing scan sets the next one; after a quiet gap the next event scans at once
        #expect(p.event(now: t.addingTimeInterval(FeedPacer.gap + 0.1)) == .scanAt(t.addingTimeInterval(2 * FeedPacer.gap)))
        p.scanned(at: t.addingTimeInterval(2 * FeedPacer.gap), trailing: true)
        #expect(p.event(now: t.addingTimeInterval(5)) == .scanNow)
    }

    @Test func pacerTreatsAClockStepBackAsQuiet() {
        var p = FeedPacer()
        let t = Date(timeIntervalSince1970: 1_000_000)
        p.scanned(at: t)
        #expect(p.event(now: t.addingTimeInterval(-30)) == .scanNow)
    }

    @Test func liveSessionCacheReadsLikeAFreshReadAndParsesOnlyChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-live-\(UUID().uuidString)", isDirectory: true)
        let dir = folder.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let me = getpid()
        func put(_ name: String?) throws {
            var d: [String: Any] = ["pid": Int(me), "sessionId": "3f1a9c2e-0000-4000-8000-000000000001", "cwd": "/tmp/w",
                                    "kind": "interactive", "entrypoint": "cli"]
            if let name { d["name"] = name; d["nameSource"] = "user" }
            let tmp = dir.appendingPathComponent("x.tmp")
            try JSONSerialization.data(withJSONObject: d).write(to: tmp)
            _ = rename(tmp.path, dir.appendingPathComponent("\(me).json").path)
        }
        try put("first")
        var cache = LiveSessionCache()
        let a = cache.read(settingsFolders: [folder])
        #expect(a == LiveSession.read(settingsFolders: [folder]))
        #expect(a.first?.name == "first")
        #expect(cache.parseCount == 1)
        _ = cache.read(settingsFolders: [folder])
        #expect(cache.parseCount == 1)
        try put("renamed")   // /rename writes the file again
        #expect(cache.read(settingsFolders: [folder]).first?.name == "renamed")
        #expect(cache.parseCount == 2)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("\(me).json"))
        #expect(cache.read(settingsFolders: [folder]).isEmpty)
    }
}
