// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Prices

public struct TokenGroup: Sendable, Equatable {
    public var name: String
    public var key: String        // the model id, the project name or the session id
    public var tokens: Int
    public var share: Int         // percent of the list's total
    public init(name: String, key: String, tokens: Int, share: Int) { self.name = name; self.key = key; self.tokens = tokens; self.share = share }
}

public struct TokenSummary: Sendable, Equatable {
    public var byModel7d: [TokenGroup]
    public var byProject7d: [TokenGroup]
    public var bySessionToday: [TokenGroup]
    public var agentShare7d: Int          // percent
    public var listPrice7d: Double
    public var unpricedModels: Int
    public var tokensToday: Int
    public var tokens7d: Int
    public var tokens30d: Int
    /// The first time after which these figures are out of date with no new record: a record leaves the 7 or the 30 day
    /// window, or one dated after now enters. nil when no record will ever cross an edge. (0.1.15, audit F-3)
    public var nextEdge: Date?
    public init(byModel7d: [TokenGroup], byProject7d: [TokenGroup], bySessionToday: [TokenGroup], agentShare7d: Int,
                listPrice7d: Double, unpricedModels: Int, tokensToday: Int, tokens7d: Int, tokens30d: Int,
                nextEdge: Date? = nil) {
        self.byModel7d = byModel7d; self.byProject7d = byProject7d; self.bySessionToday = bySessionToday
        self.agentShare7d = agentShare7d; self.listPrice7d = listPrice7d; self.unpricedModels = unpricedModels
        self.tokensToday = tokensToday; self.tokens7d = tokens7d; self.tokens30d = tokens30d
        self.nextEdge = nextEdge
    }
}

public enum Aggregator {
    public static let maxRows = 5

    /// Groups from sums, key to tokens, sorted by the figure, largest first; more than five becomes four and "other".
    /// (The form that took records had no caller in the app and lives in the tests since 0.1.19.)
    static func groups(sums: [String: Int], name: (String) -> String) -> [TokenGroup] {
        let total = sums.values.reduce(0) { $0.saturatingAdd($1) }
        guard total > 0 else { return [] }
        var sorted = sums.map { ($0.key, $0.value) }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        var out: [TokenGroup] = []
        if sorted.count > maxRows {
            let rest = sorted[(maxRows - 1)...].reduce(0) { $0.saturatingAdd($1.1) }
            sorted = Array(sorted.prefix(maxRows - 1))
            out = sorted.map { TokenGroup(name: name($0.0), key: $0.0, tokens: $0.1, share: Int((Double($0.1) / Double(total) * 100).rounded())) }
            out.append(TokenGroup(name: "other", key: "other", tokens: rest, share: Int((Double(rest) / Double(total) * 100).rounded())))
        } else {
            out = sorted.map { TokenGroup(name: name($0.0), key: $0.0, tokens: $0.1, share: Int((Double($0.1) / Double(total) * 100).rounded())) }
        }
        return out
    }

    public static let weekLength: TimeInterval = 7 * 24 * 3600
    public static let monthLength: TimeInterval = 30 * 24 * 3600

    /// One pass over the records (0.1.18): every window, sum, group and the list price at once, the price row looked up
    /// once per model. Until 0.1.17 the records were filtered three times, grouped three times and priced by a search of
    /// the table for every record, which on a month of heavy use cost most of a pass. Same results, in the same order
    /// of addition, so the figures do not move by a cent (Tests: AggregatorOnePassTests against the old way).
    public static func summarize(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current) -> TokenSummary {
        let midnight = calendar.startOfDay(for: now)
        let d7 = now.addingTimeInterval(-weekLength)
        let d30 = now.addingTimeInterval(-monthLength)
        var total7 = 0, agent7 = 0, today = 0, month = 0
        var price = 0.0
        var unpriced: Set<String> = []
        var rows: [String: PriceRow?] = [:]
        var byModel: [String: Int] = [:], byProject: [String: Int] = [:], bySession: [String: Int] = [:]
        var oldest7: Date?, oldest30: Date?, ahead: Date?
        for r in records {
            let t = r.timestamp
            if t > now { if ahead == nil || t < ahead! { ahead = t }; continue }
            guard t >= d30 else { continue }
            let n = r.usage.total
            month = month.saturatingAdd(n)
            if oldest30 == nil || t < oldest30! { oldest30 = t }
            guard t >= d7 else { continue }
            total7 = total7.saturatingAdd(n)
            if r.isAgent { agent7 = agent7.saturatingAdd(n) }
            if oldest7 == nil || t < oldest7! { oldest7 = t }
            let row: PriceRow?
            if let known = rows[r.model] { row = known } else { row = PriceTable.row(forModel: r.model); rows[r.model] = row }
            if let row { price += row.cost(r.usage) } else { unpriced.insert(r.model) }
            byModel[r.model, default: 0] = byModel[r.model, default: 0].saturatingAdd(n)
            byProject[r.project, default: 0] = byProject[r.project, default: 0].saturatingAdd(n)
            if t >= midnight {
                today = today.saturatingAdd(n)
                bySession[r.session, default: 0] = bySession[r.session, default: 0].saturatingAdd(n)
            }
        }
        // the oldest record of each window leaves it at its time plus the window; a record dated after now enters at its time
        let edges = [oldest7.map { $0.addingTimeInterval(Self.weekLength) }, oldest30.map { $0.addingTimeInterval(Self.monthLength) }, ahead]
        return TokenSummary(
            byModel7d: groups(sums: byModel, name: { PriceTable.displayName(forModel: $0) }),
            byProject7d: groups(sums: byProject, name: { $0 }),
            bySessionToday: groups(sums: bySession, name: { String($0.prefix(8)) }),
            agentShare7d: total7 > 0 ? Int((Double(agent7) / Double(total7) * 100).rounded()) : 0,
            listPrice7d: price, unpricedModels: unpriced.count,
            tokensToday: today, tokens7d: total7, tokens30d: month,
            nextEdge: edges.compactMap { $0 }.min())
    }
}
