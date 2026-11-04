// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Transcripts
import Prices

/// The transcript reader against a synthetic tree with decoys: one id written three times, a synthetic line,
/// a malformed line, a subagent file, and folders that must never be opened.
struct TranscriptsTests {
    let fm = FileManager.default

    // swiftlint:disable line_length
    func line(id: String, model: String = "claude-fable-5-1", ts: String = "2026-10-13T14:14:25.753Z", sidechain: Bool = false,
              session: String = "11111111-0000-4000-8000-000000000001", cwd: String = "/Users/someone/workspace",
              input: Int = 2, output: Int = 4, read: Int = 27543, write: Int = 17266, w5: Int = 0, w1: Int = 17266) -> String {
        """
        {"parentUuid":"x","isSidechain":\(sidechain),"message":{"model":"\(model)","id":"\(id)","type":"message","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(write),"cache_read_input_tokens":\(read),"output_tokens":\(output),"cache_creation":{"ephemeral_1h_input_tokens":\(w1),"ephemeral_5m_input_tokens":\(w5)}}},"requestId":"req_\(id)","type":"assistant","uuid":"u","timestamp":"\(ts)","cwd":"\(cwd)","sessionId":"\(session)","version":"2.1.296","toolUseResult":"must not be kept","accountUuid":"must not be kept"}
        """
    }
    // swiftlint:enable line_length

    func makeTree() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("tokenpanda-transcripts-\(UUID().uuidString)/projects", isDirectory: true)
        let project = root.appendingPathComponent("-Users-someone-workspace", isDirectory: true)
        let session = "11111111-0000-4000-8000-000000000001"
        let sessionDir = project.appendingPathComponent(session, isDirectory: true)
        try fm.createDirectory(at: sessionDir.appendingPathComponent("subagents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionDir.appendingPathComponent("tool-results"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.appendingPathComponent("memory"), withIntermediateDirectories: true)
        let main = [
            "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"private prompt\"},\"timestamp\":\"2026-10-13T14:14:20.000Z\"}",
            line(id: "msg_A"), line(id: "msg_A"), line(id: "msg_A"),                       // one message, three content blocks
            line(id: "msg_B", model: "<synthetic>"),                                      // skipped
            "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_broken\"",                   // malformed, skipped
            line(id: "msg_C", model: "claude-haiku-4-5-20251001", input: 1000, output: 500, read: 0, write: 0, w5: 0, w1: 0),
            line(id: "msg_D", ts: "2026-09-20T10:00:00.000Z", input: 10, output: 10, read: 0, write: 0, w5: 0, w1: 0),   // inside 30 days, outside 7
            "{\"type\":\"cost-state\",\"totalCostUSD\":0.5,\"modelUsage\":{}}",
        ].joined(separator: "\n") + "\n"
        try main.write(to: project.appendingPathComponent(session + ".jsonl"), atomically: true, encoding: .utf8)
        let agent = line(id: "msg_E", sidechain: true, input: 100, output: 100, read: 0, write: 0, w5: 0, w1: 0) + "\n"
        try agent.write(to: sessionDir.appendingPathComponent("subagents/agent-abc.jsonl"), atomically: true, encoding: .utf8)
        try "{}".write(to: sessionDir.appendingPathComponent("subagents/agent-abc.meta.json"), atomically: true, encoding: .utf8)
        // decoys: a transcript shaped file in every place the reader must never look
        for decoy in ["memory/notes.jsonl", "memory/MEMORY.md", "\(session)/tool-results/result.jsonl", "\(session)/custom-title.json", "\(session)/nested.jsonl"] {
            let url = project.appendingPathComponent(decoy)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (line(id: "msg_DECOY_" + decoy, input: 9_999_999) + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func enumeratorFindsOnlyTheTwoPatterns() throws {
        let root = try makeTree()
        let files = TranscriptLocator.files(under: [root])
        #expect(files.count == 2)
        let paths = files.map { $0.url.path }
        #expect(paths.contains { $0.hasSuffix("/-Users-someone-workspace/11111111-0000-4000-8000-000000000001.jsonl") })
        #expect(paths.contains { $0.hasSuffix("/subagents/agent-abc.jsonl") })
        #expect(!(paths.contains { $0.contains("memory") || $0.contains("tool-results") || $0.contains("nested") || $0.contains("meta") }))
        #expect(files.filter(\.isAgent).count == 1)
        #expect(files.first { !$0.isAgent }?.sessionId == "11111111-0000-4000-8000-000000000001")
    }

    @Test func dedupeAndSkips() async throws {
        let root = try makeTree()
        let store = TranscriptStore(roots: [root])
        let now = ISO8601DateFormatter().date(from: "2026-10-13T16:00:00Z")!
        let r = await store.refresh(now: now)
        #expect(r.error == nil)
        #expect(r.rootsExist)
        let ids = Set(r.records.map { "\($0.model)/\($0.usage.input)" })
        #expect(r.records.count == 4)       // A once, C, D, E; B synthetic and the broken line skipped
        #expect(ids.contains("claude-fable-5-1/2"))
        #expect(r.records.filter { $0.usage.input == 9_999_999 }.count == 0, "a decoy was read")
        let a = r.records.filter { $0.model == "claude-fable-5-1" && $0.usage.input == 2 }
        #expect(a.count == 1)
        #expect(a[0].usage.cacheWrite1h == 17266)
        #expect(a[0].project == "workspace")
        #expect(a[0].session == "11111111-0000-4000-8000-000000000001")
        #expect(!(a[0].isAgent))
        #expect(r.records.filter(\.isAgent).count == 1)
    }

    @Test func theTokenRowsSurviveMidnightWithoutANewTranscriptLine() async throws {
        // 0.1.0 to 0.1.13: on a new day with no transcript change the unchanged pass returned no records and every row
        // went empty until the next write. The rule asks for all records on a new day.
        let root = try makeTree()
        let store = TranscriptStore(roots: [root])
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let evening = ISO8601DateFormatter().date(from: "2026-10-13T23:59:00Z")!
        let after = ISO8601DateFormatter().date(from: "2026-10-14T00:01:00Z")!
        let day1 = cal.startOfDay(for: evening), day2 = cal.startOfDay(for: after)
        #expect(TokenRefresh.needsAllRecords(lastDay: nil, today: day1, haveTokens: false))
        let first = await store.refresh(now: evening, onlyIfChanged: true)
        let before = Aggregator.summarize(first.records, now: evening, calendar: cal)
        #expect(before.tokens7d > 0)
        // the same day, nothing changed: no records needed, the aggregate stays
        #expect(!TokenRefresh.needsAllRecords(lastDay: day1, today: day1, haveTokens: true))
        #expect(await store.refresh(now: evening, onlyIfChanged: true).records.isEmpty)
        // past midnight, nothing changed: all records, and the 7 day rows keep their figures
        #expect(TokenRefresh.needsAllRecords(lastDay: day1, today: day2, haveTokens: true))
        // the controller's pass, as it runs it: the plan asks for all records and rebuilds although no version moved;
        // the 0.1.13 call (changes only, rebuild on a new day) got no records and summed none
        let plan = TokenRefresh.plan(lastDay: day1, today: day2, haveTokens: true)
        #expect(plan.onlyIfChanged == false)
        let next = await store.refresh(now: after, onlyIfChanged: plan.onlyIfChanged)
        #expect(!next.records.isEmpty)
        #expect(TokenRefresh.rebuild(plan: plan, versionMoved: false))
        let same = TokenRefresh.plan(lastDay: day2, today: day2, haveTokens: true)
        #expect(same.onlyIfChanged && !TokenRefresh.rebuild(plan: same, versionMoved: false))
        #expect(TokenRefresh.rebuild(plan: same, versionMoved: true))
        let s = Aggregator.summarize(next.records, now: after, calendar: cal)
        #expect(s.tokens7d == before.tokens7d)
        #expect(s.byModel7d == before.byModel7d)
        #expect(s.tokensToday == 0)   // a new day: today starts empty, the week does not
    }

    @Test func theWeekAndMonthRowsDropARecordAtTheirEdgeWithoutANewLine() {
        // 0.1.0 to 0.1.14: the aggregate was built again only with a new record or a new day, so on a quiet day the
        // 7 and 30 day rows kept records past their edge (audit F-3). A fixed clock, the same day throughout.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z")!
        let hour: TimeInterval = 3600
        func rec(age: TimeInterval, _ tokens: Int, model: String = "claude-fable-5-1") -> UsageRecord {
            UsageRecord(timestamp: noon.addingTimeInterval(-age), model: model, project: "p", session: "s", isAgent: false,
                        usage: Usage(input: tokens, output: 0, cacheRead: 0, cacheWrite: 0))
        }
        let records = [rec(age: 7 * 24 * hour - hour, 100, model: "claude-opus-5-5"),   // leaves 7 days in an hour
                       rec(age: 30 * 24 * hour - 3 * hour, 10),                          // leaves 30 days in three
                       rec(age: 2 * hour, 1)]
        let day = cal.startOfDay(for: noon)
        let s0 = Aggregator.summarize(records, now: noon, calendar: cal)
        #expect(s0.tokens7d == 101 && s0.tokens30d == 111)
        #expect(s0.nextEdge == noon.addingTimeInterval(hour))
        // the controller's pass, as it runs it: before the edge, changes only and no rebuild
        let early = noon.addingTimeInterval(hour / 2)
        let p1 = TokenRefresh.plan(lastDay: day, today: day, haveTokens: true, now: early, nextEdge: s0.nextEdge)
        #expect(p1.onlyIfChanged && !TokenRefresh.rebuild(plan: p1, versionMoved: false))
        // past the 7 day edge: every record, rebuilt; the week drops the record, the month keeps it (20.2.1)
        let t1 = noon.addingTimeInterval(2 * hour)
        let p2 = TokenRefresh.plan(lastDay: day, today: day, haveTokens: true, now: t1, nextEdge: s0.nextEdge)
        #expect(!p2.onlyIfChanged && TokenRefresh.rebuild(plan: p2, versionMoved: false))
        let s1 = Aggregator.summarize(records, now: t1, calendar: cal)
        #expect(s1.tokens7d == 1 && s1.total7d == 1 && s1.tokens30d == 111)
        #expect(s1.byModel7d.map(\.key) == ["claude-fable-5-1"])
        #expect(s1.byProject7d.first?.tokens == 1)
        #expect(s1.listPrice7d < s0.listPrice7d)
        #expect(s1.nextEdge == noon.addingTimeInterval(3 * hour))
        // past the 30 day edge: the month drops the oldest record too (20.2.2)
        let t2 = noon.addingTimeInterval(4 * hour)
        #expect(TokenRefresh.needsAllRecords(lastDay: day, today: day, haveTokens: true, now: t2, nextEdge: s1.nextEdge))
        let s2 = Aggregator.summarize(records, now: t2, calendar: cal)
        #expect(s2.tokens30d == 101 && s2.tokens7d == 1)
        // the next edge is the newest record's, a week on; nothing crosses before it (20.2.3)
        #expect(s2.nextEdge == noon.addingTimeInterval(-2 * hour + 7 * 24 * hour))
        #expect(!TokenRefresh.needsAllRecords(lastDay: day, today: day, haveTokens: true, now: t2.addingTimeInterval(hour), nextEdge: s2.nextEdge))
        // a record dated after now (a clock moved back) enters at its time
        let ahead = Aggregator.summarize([rec(age: -hour, 5)], now: noon, calendar: cal)
        #expect(ahead.tokens7d == 0 && ahead.nextEdge == noon.addingTimeInterval(hour))
        #expect(Aggregator.summarize([], now: noon, calendar: cal).nextEdge == nil)
    }

    @Test func theWindowEdgesAreLengthsOfTimeAcrossSummerTime() {
        // spec 20.2.4: Lisbon left summer time on 25 Oct 2026, 02:00 back to 01:00. A record from 23 Oct 12:00 local
        // leaves the 7 day window exactly 168 hours later, 30 Oct 11:00 local, not at 12:00 by the calendar.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        let iso = ISO8601DateFormatter()
        let ts = iso.date(from: "2026-10-23T11:00:00Z")!            // 12:00 in summer time
        let r = UsageRecord(timestamp: ts, model: "claude-fable-5-1", project: "p", session: "s", isAgent: false,
                            usage: Usage(input: 5, output: 0, cacheRead: 0, cacheWrite: 0))
        let now = iso.date(from: "2026-10-30T09:00:00Z")!           // 09:00 in winter time
        let s = Aggregator.summarize([r], now: now, calendar: cal)
        #expect(s.tokens7d == 5)
        #expect(s.nextEdge == ts.addingTimeInterval(168 * 3600))
        #expect(cal.dateComponents([.hour], from: s.nextEdge!).hour == 11)
        let day = cal.startOfDay(for: now)
        #expect(!TokenRefresh.needsAllRecords(lastDay: day, today: day, haveTokens: true, now: s.nextEdge!, nextEdge: s.nextEdge))
        let past = s.nextEdge!.addingTimeInterval(1)
        #expect(TokenRefresh.needsAllRecords(lastDay: day, today: day, haveTokens: true, now: past, nextEdge: s.nextEdge))
        #expect(Aggregator.summarize([r], now: past, calendar: cal).tokens7d == 0)
        // the today rows start at local midnight, the day the clocks went back as well
        let back = iso.date(from: "2026-10-25T12:00:00Z")!
        #expect(cal.startOfDay(for: back) == iso.date(from: "2026-10-24T23:00:00Z")!)
    }

    @Test func aggregateWindowsAndAgentShare() async throws {
        let root = try makeTree()
        let store = TranscriptStore(roots: [root])
        let now = ISO8601DateFormatter().date(from: "2026-10-13T16:00:00Z")!
        let r = await store.refresh(now: now)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let s = Aggregator.summarize(r.records, now: now, calendar: cal)
        // 7 days: A (2+4+27543+17266 = 44815), C (1500), E (200); D is in September
        #expect(s.tokens7d == 44815 + 1500 + 200)
        #expect(s.tokensToday == 44815 + 1500 + 200)
        #expect(s.tokens30d == 44815 + 1500 + 200 + 20)
        #expect(s.agentShare7d == Int((200.0 / 46515 * 100).rounded()))
        #expect(s.byModel7d.map(\.name) == ["Fable 5.1", "Haiku 4.5"])
        #expect(s.byModel7d[0].tokens == 44815 + 200)
        #expect(s.byProject7d.map(\.name) == ["workspace"])
        #expect(s.bySessionToday.map(\.name) == ["11111111"])
        #expect(s.unpricedModels == 0)
        let expected = PriceTable.cost(model: "claude-fable-5-1", usage: Usage(input: 2, output: 4, cacheRead: 27543, cacheWrite: 17266, cacheWrite5m: 0, cacheWrite1h: 17266))!
            + PriceTable.cost(model: "claude-haiku-4-5-20251001", usage: Usage(input: 1000, output: 500, cacheRead: 0, cacheWrite: 0))!
            + PriceTable.cost(model: "claude-fable-5-1", usage: Usage(input: 100, output: 100, cacheRead: 0, cacheWrite: 0))!
        #expect(abs((s.listPrice7d) - (expected)) <= 1e-9)
    }

    @Test func crossCheckAgainstTheSessionCostState() throws {
        // the real captured session ("ok", one message) reported total_cost_usd 0.35242575 in its feed for exactly this usage
        let u = Usage(input: 2, output: 4, cacheRead: 27543, cacheWrite: 17266, cacheWrite5m: 0, cacheWrite1h: 17266)
        #expect(abs((PriceTable.cost(model: "claude-fable-5-1", usage: u)!) - (0.35242575)) <= 1e-6)
    }

    @Test func incrementalReadKeepsOffsetsAndRereadsAShrunkFile() async throws {
        let root = try makeTree()
        let store = TranscriptStore(roots: [root])
        let now = ISO8601DateFormatter().date(from: "2026-10-13T16:00:00Z")!
        _ = await store.refresh(now: now)
        let file = root.appendingPathComponent("-Users-someone-workspace/11111111-0000-4000-8000-000000000001.jsonl")
        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: Data((line(id: "msg_F", input: 7) + "\n").utf8))
        try h.close()
        let r2 = await store.refresh(now: now)
        #expect(r2.records.count == 5)
        #expect(r2.records.filter { $0.usage.input == 7 }.count == 1)
        // a partial last line without its newline is not consumed until it completes
        let h2 = try FileHandle(forWritingTo: file)
        try h2.seekToEnd()
        let full = line(id: "msg_G", input: 8) + "\n"
        try h2.write(contentsOf: Data(full.prefix(40).utf8))
        try h2.close()
        let partial = await store.refresh(now: now)
        #expect(partial.records.count == 5)
        let h3 = try FileHandle(forWritingTo: file)
        try h3.seekToEnd()
        try h3.write(contentsOf: Data(full.dropFirst(40).utf8))
        try h3.close()
        let completed = await store.refresh(now: now)
        #expect(completed.records.count == 6)
        // truncation: the file is read again from the start, nothing is double counted
        try (line(id: "msg_H", input: 9) + "\n").write(to: file, atomically: true, encoding: .utf8)
        let r4 = await store.refresh(now: now)
        #expect(r4.records.filter { !$0.isAgent }.count == 1)
    }

    @Test func topFiveAndOther() {
        let now = Date()
        let recs = (0..<8).map { i in
            UsageRecord(timestamp: now.addingTimeInterval(-60), model: "claude-fable-5-1", project: "p\(i)", session: "s", isAgent: false,
                        usage: Usage(input: 100 * (8 - i), output: 0, cacheRead: 0, cacheWrite: 0))
        }
        let g = Aggregator.groups(recs, key: \.project, name: { $0 })
        #expect(g.count == 5)
        #expect(g.last?.name == "other")
        #expect(g.last?.tokens == 400 + 300 + 200 + 100)
        #expect(g.reduce(0) { $0 + $1.tokens } == 3600)
    }

    @Test func rootsFromEnvironment() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let roots = TranscriptLocator.roots(home: home, environment: ["CLAUDE_CONFIG_DIR": "/tmp/a, /tmp/b"])
        #expect(roots.map(\.path) == ["/Users/someone/.claude/projects", "/Users/someone/.config/claude/projects", "/tmp/a/projects", "/tmp/b/projects"])
        #expect(TranscriptLocator.projectName(fromFolder: "-Users-someone-workspace") == "workspace")
    }
}
