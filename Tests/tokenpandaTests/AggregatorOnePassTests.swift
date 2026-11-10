// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Prices
@testable import Transcripts

/// The one pass summary of 0.1.18 gives exactly what the three filters of 0.1.17 gave: the old way is kept here as the
/// reference and both run on random records, edges and odd values included.
struct AggregatorOnePassTests {
    /// Aggregator.summarize as it was until 0.1.17, word for word.
    static func reference(_ records: [UsageRecord], now: Date, calendar: Calendar) -> TokenSummary {
        let midnight = calendar.startOfDay(for: now)
        let d7 = now.addingTimeInterval(-Aggregator.weekLength)
        let d30 = now.addingTimeInterval(-Aggregator.monthLength)
        let today = records.filter { $0.timestamp >= midnight && $0.timestamp <= now }
        let week = records.filter { $0.timestamp >= d7 && $0.timestamp <= now }
        let month = records.filter { $0.timestamp >= d30 && $0.timestamp <= now }
        let total7 = week.reduce(0) { $0.saturatingAdd($1.usage.total) }
        let agent7 = week.filter(\.isAgent).reduce(0) { $0.saturatingAdd($1.usage.total) }
        var price = 0.0
        var unpriced: Set<String> = []
        for r in week {
            if let c = PriceTable.cost(model: r.model, usage: r.usage) { price += c } else { unpriced.insert(r.model) }
        }
        let edges = [week.map(\.timestamp).min().map { $0.addingTimeInterval(Aggregator.weekLength) },
                     month.map(\.timestamp).min().map { $0.addingTimeInterval(Aggregator.monthLength) },
                     records.lazy.map(\.timestamp).filter { $0 > now }.min()]
        return TokenSummary(
            byModel7d: Aggregator.groups(week, key: \.model, name: { PriceTable.displayName(forModel: $0) }),
            byProject7d: Aggregator.groups(week, key: \.project, name: { $0 }),
            bySessionToday: Aggregator.groups(today, key: \.session, name: { String($0.prefix(8)) }),
            agentShare7d: total7 > 0 ? Int((Double(agent7) / Double(total7) * 100).rounded()) : 0,
            listPrice7d: price, unpricedModels: unpriced.count,
            tokensToday: today.reduce(0) { $0.saturatingAdd($1.usage.total) }, tokens7d: total7,
            tokens30d: month.reduce(0) { $0.saturatingAdd($1.usage.total) },
            total7d: total7, totalToday: today.reduce(0) { $0.saturatingAdd($1.usage.total) },
            nextEdge: edges.compactMap { $0 }.min())
    }

    static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1", "claude-opus-4-1",
                         "claude-haiku-4-5-20251001", "claude-unknown-9", "<synthetic>", "", "claude-opus-5-5-20260101"]

    struct Rng: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    }

    static func records(_ n: Int, now: Date, seed: UInt64) -> [UsageRecord] {
        var g = Rng(s: seed)
        let edges: [TimeInterval] = [0, Aggregator.weekLength, Aggregator.monthLength, 1, -1, 3 * 3600]
        return (0..<n).map { i in
            // most within the month, some on an edge exactly, some older than the month, a few after now
            let age: TimeInterval
            switch Int.random(in: 0..<20, using: &g) {
            case 0: age = edges.randomElement(using: &g)!
            case 1: age = -TimeInterval.random(in: 1...86_400, using: &g)
            case 2: age = Aggregator.monthLength + TimeInterval.random(in: 1...864_000, using: &g)
            default: age = TimeInterval.random(in: 0...Aggregator.monthLength, using: &g)
            }
            let big = Int.random(in: 0..<200, using: &g) == 0
            let u = Usage(input: big ? Int.max / 3 : Int.random(in: 0...50_000, using: &g),
                          output: Int.random(in: 0...20_000, using: &g),
                          cacheRead: Int.random(in: 0...2_000_000, using: &g),
                          cacheWrite: Int.random(in: 0...200_000, using: &g),
                          cacheWrite5m: Bool.random(using: &g) ? Int.random(in: 0...100_000, using: &g) : nil,
                          cacheWrite1h: Bool.random(using: &g) ? Int.random(in: 0...100_000, using: &g) : nil)
            return UsageRecord(timestamp: now.addingTimeInterval(-age), model: models.randomElement(using: &g)!,
                               project: "p\(Int.random(in: 0..<9, using: &g))", session: "s\(Int.random(in: 0..<14, using: &g))-\(i % 3)",
                               isAgent: Bool.random(using: &g), usage: u)
        }
    }

    @Test func sameAsTheOldWayOnRandomRecords() {
        let now = Date(timeIntervalSince1970: 1_794_300_000)
        var zurich = Calendar(identifier: .gregorian); zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        var la = Calendar(identifier: .gregorian); la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for seed in UInt64(1)...300 {
            let recs = Self.records(Int(seed % 7 == 0 ? 0 : seed * 3), now: now, seed: seed)
            for cal in [zurich, la] {
                let t = now.addingTimeInterval(TimeInterval(seed % 24) * 3600)
                // records exactly on every edge of this moment: midnight, 7 and 30 days back, now, and a second either side
                var edged = recs
                for (k, at) in Self.edges(t, cal).enumerated() {
                    for d in [-1.0, 0, 1] {
                        edged.append(UsageRecord(timestamp: at.addingTimeInterval(d), model: Self.models[k % Self.models.count], project: "edge",
                                                 session: "e\(k)", isAgent: k % 2 == 0, usage: Usage(input: 7 + k, output: 3, cacheRead: 11, cacheWrite: 5)))
                    }
                }
                #expect(Aggregator.summarize(edged, now: t, calendar: cal) == Self.reference(edged, now: t, calendar: cal), "seed \(seed)")
            }
        }
    }

    static func edges(_ t: Date, _ cal: Calendar) -> [Date] {
        [cal.startOfDay(for: t), t.addingTimeInterval(-Aggregator.weekLength), t.addingTimeInterval(-Aggregator.monthLength), t]
    }

    @Test func emptyAndAllInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_794_300_000)
        let cal = Calendar(identifier: .gregorian)
        #expect(Aggregator.summarize([], now: now, calendar: cal) == Self.reference([], now: now, calendar: cal))
        let ahead = Self.records(50, now: now.addingTimeInterval(40 * 86_400), seed: 9)
        #expect(Aggregator.summarize(ahead, now: now, calendar: cal) == Self.reference(ahead, now: now, calendar: cal))
    }
}

/// Names in a record are plain Swift strings, never bridged path strings: a bridged name made every lookup of a summary
/// pass normalise it again, most of a pass on a month of records (0.1.18).
struct ParserNativeNamesTests {
    @Test func namesAreNativeUTF8() {
        let file = TranscriptFile(url: URL(fileURLWithPath: "/tmp/x.jsonl"), projectFolder: "-Users-someone-work-alpha", sessionId: "s-1",
                                  isAgent: false, size: 0, modified: Date())
        let line = #"{"type":"assistant","timestamp":"2026-11-10T10:00:00.000Z","cwd":"/Users/someone/work/alpha","sessionId":"abc-1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":2}}}"#
        guard let p = TranscriptParser.parse(line: Data(line.utf8), file: file) else { Issue.record("not parsed"); return }
        #expect(p.record.project == "alpha")
        for s in [p.record.project, p.record.session, p.record.model] {
            #expect(s.utf8.withContiguousStorageIfAvailable { _ in true } == true, "\(s) is not native UTF-8")
        }
    }
}
