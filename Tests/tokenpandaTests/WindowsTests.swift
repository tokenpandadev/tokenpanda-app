// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed
import Text
import UI

/// The windows across several session files: the merge per key (latest reset, highest percentage, with the stored record)
/// and the retiring of a window the feed no longer carries (kept for the length check, hidden only after a reply without it).
struct WindowsTests {
    let t0 = Date(timeIntervalSince1970: 1793520000)            // Sun 1 Nov 2026 08:00 UTC
    var week: Date { t0.addingTimeInterval(3 * 86400) }          // the weekly reset ahead
    let utc = TimeZone(identifier: "UTC")!

    func tempDir() throws -> URL {
        let url = TestTemp.root.appendingPathComponent("tokenpanda-windows-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return url
    }

    /// One status line feed. `cost` stands for the figures that move with a reply; nil windows means a first call.
    func feed(_ sid: String, windows: [String: (Double, Date)]?, cost: Double = 1, tokens: Int? = 1000) -> Data {
        var d: [String: Any] = ["session_id": sid, "cost": ["total_cost_usd": cost]]
        var ctx: [String: Any] = ["context_window_size": 1_000_000, "used_percentage": 10]
        if let tokens { ctx["current_usage"] = ["input_tokens": tokens, "output_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0] }
        d["context_window"] = ctx
        if let windows {
            var r: [String: Any] = [:]
            for (k, (u, reset)) in windows { r[k] = ["used_percentage": u, "resets_at": reset.timeIntervalSince1970] }
            d["rate_limits"] = r
        }
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
    }

    func write(_ sid: String, _ data: Data, in dir: URL, at t: Date) throws {
        let url = dir.appendingPathComponent("sessions/\(sid).json")
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: t], ofItemAtPath: url.path)
    }

    func mode(_ key: String, _ l: Limits, _ now: Date) -> WindowMode {
        ScreenBuilder.windowView(key: key, limits: l, now: now, tz: utc).mode
    }

    func titles(_ l: Limits) -> [String] {
        guard case .windows(let ws, _) = ScreenBuilder.limitsView(Fixtures.input(feedState: FeedState(limits: l, lastWriteAt: Fixtures.now))) else { return [] }
        return ws.map(\.title)
    }

    func isLive(_ m: WindowMode) -> Bool { if case .live = m { return true } else { return false } }

    // MARK: the merge

    @Test func weeklyTakesTheHighestFigureWhicheverFileIsNewest() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        var seen: [Double] = []
        for k in 0..<4 {
            let now = t0.addingTimeInterval(Double(k) * 5)
            // the idle session at 12 and the busy one at 28 take turns as the newest file
            try write("busy", feed("busy", windows: ["seven_day": (28, week)]), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? -1 : 0))
            try write("idle", feed("idle", windows: ["seven_day": (12, week)]), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? 0 : -1))
            seen.append(await reader.scan(now: now).limits?.windows["seven_day"]?.used ?? -1)
        }
        #expect(seen == [28, 28, 28, 28])
    }

    @Test func theStoredFigureStaysWhenTheBusiestSessionCloses() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        try write("a", feed("a", windows: ["seven_day": (29, week)]), in: dir, at: t0)
        try write("b", feed("b", windows: ["seven_day": (20, week)]), in: dir, at: t0)
        #expect(await reader.scan(now: t0).limits?.windows["seven_day"]?.used == 29)
        // a closes: its file goes after 60 s, the idle b keeps writing its older figure
        try write("b", feed("b", windows: ["seven_day": (20, week)]), in: dir, at: t0.addingTimeInterval(65))
        let st = await reader.scan(now: t0.addingTimeInterval(65))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("sessions/a.json").path))
        #expect(st.limits?.windows["seven_day"]?.used == 29)
        // and a new reader, from limits.json, keeps it too
        let again = FeedReader(dataDir: dir)
        try write("b", feed("b", windows: ["seven_day": (20, week)]), in: dir, at: t0.addingTimeInterval(70))
        #expect(await again.scan(now: t0.addingTimeInterval(70)).limits?.windows["seven_day"]?.used == 29)
    }

    @Test func weekOverWeekKeepsTheHighestValuePerWeek() {
        var w = WeekRecords()
        w.apply(LimitWindow(key: "seven_day", usedPercentage: 29, resetsAt: week), at: t0)
        w.apply(LimitWindow(key: "seven_day", usedPercentage: 12, resetsAt: week), at: t0.addingTimeInterval(5))
        #expect(w.records.count == 1)
        #expect(w.records[0].lastUsed == 29)
        #expect(w.records[0].lastSeenAt == t0.addingTimeInterval(5))
        w.apply(LimitWindow(key: "seven_day", usedPercentage: 3, resetsAt: week.addingTimeInterval(604800)), at: week)
        #expect(w.records.map(\.lastUsed) == [29, 3])
    }

    @Test func mergeTakesTheLatestResetAndIgnoresPassedOnes() {
        let old = LimitWindow(key: "seven_day", usedPercentage: 91, resetsAt: t0.addingTimeInterval(-60))
        let new = LimitWindow(key: "seven_day", usedPercentage: 2, resetsAt: week)
        let other = LimitWindow(key: "seven_day", usedPercentage: 40, resetsAt: week.addingTimeInterval(-86400))
        let m = Limits.merge([["seven_day": old], ["seven_day": other], ["seven_day": new]], now: t0)
        #expect(m["seven_day"] == new)
        #expect(Limits.merge([["seven_day": old]], now: t0).isEmpty)
    }

    @Test func twoAccountsOnOneMacStayStable() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let other = week.addingTimeInterval(-2 * 86400)   // the second account's week resets two days earlier
        var seen: [Date?] = []
        for k in 0..<4 {
            let now = t0.addingTimeInterval(Double(k) * 5)
            try write("one", feed("one", windows: ["seven_day": (30, week)]), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? -1 : 0))
            try write("two", feed("two", windows: ["seven_day": (70, other)]), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? 0 : -1))
            let l = await reader.scan(now: now).limits
            seen.append(l?.windows["seven_day"]?.resetsAt)
            #expect(l?.isUnknown("seven_day") == false)
            #expect(l?.windows["seven_day"]?.used == 30)
        }
        #expect(Set(seen.compactMap { $0 }) == [week])
    }

    // MARK: retiring a window

    @Test func ultraFiveHourGoesQuietThenHidesAfterAReplyPastItsReset() async throws {
        let dir = try tempDir()
        let five = t0.addingTimeInterval(2 * 3600)
        let reader = FeedReader(dataDir: dir)
        // the last feed with a 5h window, at 100%
        try write("s", feed("s", windows: ["seven_day": (24, week), "five_hour": (100, five)], cost: 1), in: dir, at: t0)
        var l = try #require(await reader.scan(now: t0).limits)
        #expect(ScreenBuilder.eyes(l, now: t0) == .fiveHourLimit)
        // the feed stops carrying it, an idle rewrite: kept, retired, no eyes, the row quiet (figure, no pace)
        try write("s", feed("s", windows: ["seven_day": (24, week)], cost: 1), in: dir, at: t0.addingTimeInterval(5))
        l = try #require(await reader.scan(now: t0.addingTimeInterval(5)).limits)
        #expect(l.windows["five_hour"]?.retired == true)
        #expect(l.active("five_hour") == nil)
        #expect(ScreenBuilder.eyes(l, now: t0.addingTimeInterval(5)) == .normal)
        #expect(mode("five_hour", l, t0.addingTimeInterval(5)) == .quiet)
        // a reply without it before its reset: still quiet, not hidden
        try write("s", feed("s", windows: ["seven_day": (25, week)], cost: 2), in: dir, at: t0.addingTimeInterval(10))
        l = try #require(await reader.scan(now: t0.addingTimeInterval(10)).limits)
        #expect(!l.hidden.contains("five_hour"))
        #expect(titles(l) == ["Weekly (all models)", "5h window"])
        #expect(ScreenBuilder.item(Fixtures.input(feedState: FeedState(limits: l, lastWriteAt: t0))).label.contains("5h") == false)
        // a reply without it after its reset: the plan no longer has the window, the row goes, the record stays
        let after = five.addingTimeInterval(60)
        try write("s", feed("s", windows: ["seven_day": (26, week)], cost: 3), in: dir, at: after)
        l = try #require(await reader.scan(now: after).limits)
        #expect(l.hidden.contains("five_hour"))
        #expect(l.windows["five_hour"]?.resetsAt == five)
        #expect(titles(l) == ["Weekly (all models)"])
    }

    @Test func aRetiredWindowBeforeTheFirstReplyDrawsNoPace() async throws {
        let dir = try tempDir()
        // limits.json holds a 5h window at 63% two hours from its reset, an over pace figure if drawn live
        let five = t0.addingTimeInterval(2 * 3600)
        let stored = """
        {"asOf":\(t0.timeIntervalSince1970 - 60),"windows":{"five_hour":{"contradicts":false,"used":63,"resetsAt":\(five.timeIntervalSince1970)},"seven_day":{"contradicts":false,"used":24,"resetsAt":\(week.timeIntervalSince1970)}}}
        """
        try Data(stored.utf8).write(to: dir.appendingPathComponent("limits.json"))
        let reader = FeedReader(dataDir: dir)
        try write("s", feed("s", windows: ["seven_day": (24, week)], cost: 1), in: dir, at: t0)
        let l = try #require(await reader.scan(now: t0).limits)
        #expect(mode("five_hour", l, t0) == .quiet)
        let lines = Grammar.windowSection(ScreenBuilder.windowView(key: "five_hour", limits: l, now: t0, tz: utc)).map(\.plain)
        #expect(lines.contains(" not in the last feed"))
        #expect(!lines.joined().contains("pace"))
        #expect(!lines.joined().contains("Resets"))
    }

    @Test func aReplyLandingAtTheResetKeepsTheRow() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(30)
        try write("s", feed("s", windows: ["seven_day": (30, week), "five_hour": (80, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // a reply written just before the reset, scanned just after it: its 5h window has passed and merges away
        try write("s", feed("s", windows: ["seven_day": (31, week), "five_hour": (82, five)], cost: 2), in: dir, at: five.addingTimeInterval(-1))
        let l = try #require(await reader.scan(now: five.addingTimeInterval(2)).limits)
        #expect(!l.hidden.contains("five_hour"))
        #expect(mode("five_hour", l, five.addingTimeInterval(2)) == .nextReply(reset: "Reset 08:00"))
    }

    @Test func anAccountSwitchWithAnEarlierResetTakesTheNewWindow() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let tuesday = week, sunday = t0.addingTimeInterval(86400)
        try write("s", feed("s", windows: ["seven_day": (70, tuesday)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // /login to another account: the old file goes, the new account's week resets earlier
        try FileManager.default.removeItem(at: dir.appendingPathComponent("sessions/s.json"))
        for k in 1...3 {
            let now = t0.addingTimeInterval(Double(k) * 5)
            try write("n", feed("n", windows: ["seven_day": (5 + Double(k), sunday)], cost: Double(k)), in: dir, at: now)
            _ = await reader.scan(now: now)
        }
        let l = try #require(await reader.scan(now: t0.addingTimeInterval(16)).limits)
        let rec = try #require(l.active("seven_day"))
        #expect(rec.used == 8 && rec.resetsAt == sunday && !rec.contradicts)
        #expect(isLive(mode("seven_day", l, t0.addingTimeInterval(16))))
    }

    @Test func maxIdleAndWorkingSessionsDoNotFlicker() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(3 * 3600)
        try write("work", feed("work", windows: ["seven_day": (30, week), "five_hour": (10, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        var present: [Bool] = []
        for k in 1...4 {
            let now = t0.addingTimeInterval(Double(k) * 5)
            // the idle session's 5h reset passed, so Claude Code dropped the key there; the working one has the new window
            try write("idle", feed("idle", windows: ["seven_day": (22, week)], cost: 9), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? 0 : -1))
            try write("work", feed("work", windows: ["seven_day": (30, week), "five_hour": (10 + Double(k), five)], cost: 1 + Double(k)),
                      in: dir, at: now.addingTimeInterval(k % 2 == 0 ? -1 : 0))
            let l = try #require(await reader.scan(now: now).limits)
            present.append(l.active("five_hour") != nil && isLive(mode("five_hour", l, now)))
        }
        #expect(present == [true, true, true, true])
    }

    @Test func weeklyResetWithIdleSessionsWaitsForTheNextReply() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let reset = t0.addingTimeInterval(60)
        try write("s", feed("s", windows: ["seven_day": (91, reset)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // the reset passes, the idle session keeps writing the passed window
        let after = reset.addingTimeInterval(30)
        try write("s", feed("s", windows: ["seven_day": (91, reset)], cost: 1), in: dir, at: after)
        var l = try #require(await reader.scan(now: after).limits)
        #expect(l.windows["seven_day"]?.retired == true)
        #expect(!l.hidden.contains("seven_day"))
        #expect(mode("seven_day", l, after) == .nextReply(reset: "Reset Sun 08:01"))
        let line = try #require(Grammar.windowSection(ScreenBuilder.windowView(key: "seven_day", limits: l, now: after, tz: utc)).last)
        #expect(line.plain == " Reset Sun 08:01  new window on the next reply")
        #expect(line.cells <= Grammar.popCells)
        // the next reply brings the new week; the length check still sees the old reset
        let next = reset.addingTimeInterval(604800)
        try write("s", feed("s", windows: ["seven_day": (1, next)], cost: 2), in: dir, at: after.addingTimeInterval(5))
        l = try #require(await reader.scan(now: after.addingTimeInterval(5)).limits)
        let rec = try #require(l.windows["seven_day"])
        #expect(rec.used == 1 && rec.resetsAt == next && rec.previousResetsAt == reset && !rec.contradicts && !rec.retired)
        #expect(isLive(mode("seven_day", l, after.addingTimeInterval(5))))
    }

    @Test func aFirstCallKeepsEveryWindow() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(3600)
        try write("a", feed("a", windows: ["seven_day": (30, week), "five_hour": (40, five)]), in: dir, at: t0)
        let before = try #require(await reader.scan(now: t0).limits)
        // a new session's first call: no rate_limits, no current_usage; it changes nothing
        try write("b", feed("b", windows: nil, tokens: nil), in: dir, at: t0.addingTimeInterval(5))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("sessions/a.json"))
        let l = try #require(await reader.scan(now: t0.addingTimeInterval(5)).limits)
        #expect(l == before)
        #expect(l.active("five_hour") != nil)
    }

    @Test func launchWithAStaleFiveHourInLimitsJSON() async throws {
        let dir = try tempDir()
        // limits.json as 0.1.7 wrote it: no retired, no hidden; the 5h reset passed hours ago
        let stored = """
        {"asOf":\(t0.timeIntervalSince1970 - 600),"windows":{\
        "five_hour":{"contradicts":false,"previousResetsAt":\(t0.timeIntervalSince1970 - 32400),"used":1,"resetsAt":\(t0.timeIntervalSince1970 - 14400)},\
        "seven_day":{"contradicts":false,"used":28,"resetsAt":\(week.timeIntervalSince1970)}}}
        """
        try Data(stored.utf8).write(to: dir.appendingPathComponent("limits.json"))
        let reader = FeedReader(dataDir: dir)
        // an Ultra feed, seen for the first time: not a reply, so the 5h row waits instead of vanishing
        try write("s", feed("s", windows: ["seven_day": (29, week)], cost: 5), in: dir, at: t0)
        var l = try #require(await reader.scan(now: t0).limits)
        #expect(l.windows["seven_day"]?.used == 29)
        #expect(l.windows["five_hour"]?.retired == true)
        #expect(!l.hidden.contains("five_hour"))
        #expect(mode("five_hour", l, t0) == .nextReply(reset: "Reset 04:00"))
        // the first reply without it hides it
        try write("s", feed("s", windows: ["seven_day": (30, week)], cost: 6), in: dir, at: t0.addingTimeInterval(5))
        l = try #require(await reader.scan(now: t0.addingTimeInterval(5)).limits)
        #expect(titles(l) == ["Weekly (all models)"])
        // and it is persisted in the new shape
        let again = FeedReader(dataDir: dir)
        #expect(await again.scan(now: t0.addingTimeInterval(6)).limits?.hidden == ["five_hour"])
    }

    // MARK: edge cases

    @Test func aMaxFeedThatBrieflyOmitsFiveHourKeepsTheRow() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(3 * 3600)
        try write("s", feed("s", windows: ["seven_day": (30, week), "five_hour": (41, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // one write without five_hour, no reply in it: the row stays live
        try write("s", feed("s", windows: ["seven_day": (30, week)], cost: 1), in: dir, at: t0.addingTimeInterval(5))
        var l = try #require(await reader.scan(now: t0.addingTimeInterval(5)).limits)
        #expect(!l.hidden.contains("five_hour"))
        #expect(mode("five_hour", l, t0.addingTimeInterval(5)) == .quiet)
        #expect(titles(l) == ["Weekly (all models)", "5h window"])
        // a reply that leaves it out before its reset: the row stays, quiet
        try write("s", feed("s", windows: ["seven_day": (30, week)], cost: 1.5), in: dir, at: t0.addingTimeInterval(7))
        l = try #require(await reader.scan(now: t0.addingTimeInterval(7)).limits)
        #expect(titles(l) == ["Weekly (all models)", "5h window"])
        // it comes back: no longer retired, the figure carries on
        try write("s", feed("s", windows: ["seven_day": (31, week), "five_hour": (42, five)], cost: 2), in: dir, at: t0.addingTimeInterval(10))
        l = try #require(await reader.scan(now: t0.addingTimeInterval(10)).limits)
        #expect(l.active("five_hour")?.used == 42)
        // with a second session that still carries it, a reply without it in the first changes nothing
        try write("t", feed("t", windows: ["seven_day": (31, week), "five_hour": (42, five)], cost: 7), in: dir, at: t0.addingTimeInterval(15))
        try write("s", feed("s", windows: ["seven_day": (32, week)], cost: 3), in: dir, at: t0.addingTimeInterval(15))
        l = try #require(await reader.scan(now: t0.addingTimeInterval(15)).limits)
        #expect(l.active("five_hour")?.used == 42)
    }

    @Test func aMaxFiveHourResetWaitsAndTheReplyBringsTheNewWindow() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(30)
        try write("s", feed("s", windows: ["seven_day": (30, week), "five_hour": (80, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        let after = five.addingTimeInterval(10)
        try write("s", feed("s", windows: ["seven_day": (30, week)], cost: 1), in: dir, at: after)
        var l = try #require(await reader.scan(now: after).limits)
        #expect(mode("five_hour", l, after) == .nextReply(reset: "Reset 08:00"))
        let next = five.addingTimeInterval(5 * 3600)
        try write("s", feed("s", windows: ["seven_day": (31, week), "five_hour": (2, next)], cost: 2), in: dir, at: after.addingTimeInterval(5))
        l = try #require(await reader.scan(now: after.addingTimeInterval(5)).limits)
        #expect(l.active("five_hour")?.used == 2)
        #expect(l.windows["five_hour"]?.previousResetsAt == five)
        #expect(l.windows["five_hour"]?.contradicts == false)
    }

    @Test func aReplyWithNoWindowsAtAllShowsNoPlanLimits() {
        // a weekly whose reset passed, then a reply with an empty rate_limits object
        var l = Limits(windows: ["seven_day": .init(used: 5, resetsAt: t0.addingTimeInterval(-60))], asOf: t0)
        l.apply([:], at: t0, repliedAt: t0)
        let v = ScreenBuilder.limitsView(Fixtures.input(feedState: FeedState(limits: l, lastWriteAt: Fixtures.now)))
        #expect(v == .noLimits)
    }

    // MARK: accounts, providers, settings (0.1.8 command sweep)

    @Test func anAccountSwitchWithALaterResetIsNotUnknown() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(3600), week1 = t0.addingTimeInterval(86400)
        try write("s", feed("s", windows: ["seven_day": (70, week1), "five_hour": (50, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // /login to an account whose windows reset later, both while the stored ones still run
        try write("s", feed("s", windows: ["seven_day": (6, week), "five_hour": (3, five.addingTimeInterval(2 * 3600))], cost: 2), in: dir, at: t0.addingTimeInterval(5))
        let l = try #require(await reader.scan(now: t0.addingTimeInterval(5)).limits)
        #expect(l.windows["seven_day"]?.used == 6 && l.windows["five_hour"]?.used == 3)
        #expect(!l.isUnknown("seven_day") && !l.isUnknown("five_hour"))
        #expect(isLive(mode("seven_day", l, t0.addingTimeInterval(5))) && isLive(mode("five_hour", l, t0.addingTimeInterval(5))))
    }

    @Test func anAccountSwitchWithAnEarlierFiveHourResetTakesIt() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(4 * 3600)
        try write("s", feed("s", windows: ["seven_day": (70, week), "five_hour": (90, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        try write("s", feed("s", windows: ["seven_day": (8, week.addingTimeInterval(-86400)), "five_hour": (4, t0.addingTimeInterval(1800))], cost: 2), in: dir, at: t0.addingTimeInterval(5))
        let l = try #require(await reader.scan(now: t0.addingTimeInterval(5)).limits)
        #expect(l.active("five_hour")?.used == 4 && !l.isUnknown("five_hour"))
        #expect(l.active("seven_day")?.used == 8 && !l.isUnknown("seven_day"))
    }

    @Test func twoAccountsOpenAtOnceWithTheSecondLaterAreNotUnknown() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let early = week.addingTimeInterval(-2 * 86400)
        try write("one", feed("one", windows: ["seven_day": (70, early)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        for k in 1...4 {
            let now = t0.addingTimeInterval(Double(k) * 5)
            try write("one", feed("one", windows: ["seven_day": (70, early)], cost: 1), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? 0 : -1))
            try write("two", feed("two", windows: ["seven_day": (30, week)], cost: Double(k)), in: dir, at: now.addingTimeInterval(k % 2 == 0 ? -1 : 0))
            let l = try #require(await reader.scan(now: now).limits)
            #expect(!l.isUnknown("seven_day"))
            #expect(l.windows["seven_day"]?.resetsAt == week && l.windows["seven_day"]?.used == 30)
        }
    }

    @Test func aRolloverStillChecksTheWindowLength() {
        var l = Limits(asOf: t0)
        let first = t0.addingTimeInterval(600)
        l.apply(["five_hour": LimitWindow(key: "five_hour", usedPercentage: 10, resetsAt: first)], at: t0)
        // the stored window has passed when the next one arrives, only one hour later: the key's length is wrong
        l.apply(["five_hour": LimitWindow(key: "five_hour", usedPercentage: 2, resetsAt: first.addingTimeInterval(3600))], at: first.addingTimeInterval(60))
        #expect(l.isUnknown("five_hour"))
    }

    @Test func anAPIKeyAfterSubscriptionUseShowsNoPlanLimits() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        try write("s", feed("s", windows: ["seven_day": (100, week), "five_hour": (20, t0.addingTimeInterval(3600))], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // the same session goes on with an API key: replies come without rate_limits
        try write("s", feed("s", windows: nil, cost: 2), in: dir, at: t0.addingTimeInterval(5))
        let st = await reader.scan(now: t0.addingTimeInterval(5))
        let l = try #require(st.limits)
        #expect(l.planless)
        let input = Fixtures.input(feedState: FeedState(limits: l, sessions: st.sessions, lastWriteAt: Fixtures.now))
        #expect(ScreenBuilder.limitsView(input) == .noLimits)
        #expect(ScreenBuilder.eyes(l, now: t0.addingTimeInterval(5)) == .normal)
        #expect(ScreenBuilder.item(input).used == nil)
        #expect(l.active("seven_day") == nil)
        // a subscription reply brings the windows back
        try write("s", feed("s", windows: ["seven_day": (100, week)], cost: 3), in: dir, at: t0.addingTimeInterval(10))
        let back = try #require(await reader.scan(now: t0.addingTimeInterval(10)).limits)
        #expect(!back.planless && back.active("seven_day")?.used == 100)
    }

    @Test func aRenamedRateLimitFieldSaysTheFormatChanged() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        try write("s", feed("s", windows: ["seven_day": (30, week)], cost: 1), in: dir, at: t0)
        let before = try #require(await reader.scan(now: t0).limits)
        let renamed = Data("{\"session_id\":\"s\",\"context_window\":{\"current_usage\":{\"input_tokens\":5}},\"cost\":{\"total_cost_usd\":2},\"rate_limits\":{\"seven_day\":{\"used_pct\":31,\"reset_time\":1}}}".utf8)
        try write("s", renamed, in: dir, at: t0.addingTimeInterval(5))
        let st = await reader.scan(now: t0.addingTimeInterval(5))
        #expect(st.formatChanged)
        #expect(st.limits?.windows == before.windows && st.limits?.planless == false)
        #expect(ScreenBuilder.limitsView(Fixtures.input(feedState: st)) == .formatChanged)
        // a spend limit alone is a known shape: no windows, not a format change
        let spend = SnapshotParser.parse(Data("{\"session_id\":\"x\",\"rate_limits\":{\"spend_limit\":{\"used\":1}}}".utf8), writtenAt: t0)
        #expect(spend?.rateLimitsUnreadable == false && spend?.rateLimits?.isEmpty == true)
    }

    @Test func aRenamedResetOrAPercentAsTextSaysTheFormatChanged() throws {
        func snap(_ rate: String) throws -> Snapshot {
            try #require(SnapshotParser.parse(Data("{\"session_id\":\"s\",\"rate_limits\":\(rate)}".utf8), writtenAt: t0))
        }
        let changed = [#"{"seven_day":{"used_percentage":40,"reset_time":1800000000}}"#,
                       #"{"seven_day":{"used_percentage":"40","resets_at":1800000000}}"#,
                       #"{"seven_day":{"used_percentage":40,"resets_at":"1800000000"}}"#,
                       #"{"seven_day":40}"#]
        for raw in changed {
            let s = try snap(raw)
            #expect(s.rateLimitsUnreadable, "\(raw)")
            #expect(s.rateLimits == nil, "\(raw)")
        }
        // the known shapes stay readable: a null reset, a window absent, a spend limit alone, one window read
        for raw in [#"{"five_hour":{"used_percentage":0,"resets_at":null}}"#, #"{}"#, #"{"spend_limit":{"used":1}}"#,
                    #"{"five_hour":null}"#,
                    #"{"seven_day":{"used_percentage":40,"resets_at":1800000000},"five_hour":{"used_percentage":"9","resets_at":1}}"#] {
            #expect(!(try snap(raw)).rateLimitsUnreadable, "\(raw)")
        }
    }

    // MARK: the record time

    @Test func anIdleSessionGoesStaleAnHourAfterItsLastReply() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        try write("s", feed("s", windows: ["seven_day": (30, week)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // a reply at t0 + 5
        let replied = t0.addingTimeInterval(5)
        try write("s", feed("s", windows: ["seven_day": (31, week)], cost: 2), in: dir, at: replied)
        var st = await reader.scan(now: replied)
        #expect(st.limits?.asOf == replied)
        // then the session idles: the hook writes the same cached figures every 5 s, the file time moves, the reply does not
        var now = replied
        for _ in 0..<62 {
            now = now.addingTimeInterval(60)
            try write("s", feed("s", windows: ["seven_day": (31, week)], cost: 2), in: dir, at: now)
            st = await reader.scan(now: now)
        }
        let l = try #require(st.limits)
        #expect(l.asOf == replied)                       // the record carries the reply's time
        #expect(st.lastWriteAt == now)                   // the file time is kept for the live line only
        #expect(st.isLive(now: now))
        #expect(OpenSessionsRule.isStale(asOf: l.asOf, now: now))
        guard case .stale = mode("seven_day", l, now) else { Issue.record("no stale form an hour after the last reply"); return }
        // the next reply makes it live again, and the reply time is what is kept on disk
        let next = now.addingTimeInterval(5)
        try write("s", feed("s", windows: ["seven_day": (33, week)], cost: 3), in: dir, at: next)
        let back = try #require(await reader.scan(now: next).limits)
        #expect(back.asOf == next && isLive(mode("seven_day", back, next)))
        #expect(await FeedReader(dataDir: dir).scan(now: next.addingTimeInterval(1)).limits?.asOf == next)
    }

    @Test func aLimitsFileFromBeforeTheReplyTimeIsStillRead() async throws {
        // limits.json as 0.1.18 and earlier wrote it: asOf was the newest file time, no feed time of its own
        let dir = try tempDir()
        let stored = """
        {"asOf":\(t0.timeIntervalSince1970 - 600),"hidden":[],"planless":false,"windows":{"seven_day":{"contradicts":false,"retired":false,"used":28,"resetsAt":\(week.timeIntervalSince1970)}}}
        """
        try Data(stored.utf8).write(to: dir.appendingPathComponent("limits.json"))
        let reader = FeedReader(dataDir: dir)
        let first = try #require(await reader.scan(now: t0).limits)
        #expect(first.asOf == t0.addingTimeInterval(-600) && first.fedAt == first.asOf && first.windows["seven_day"]?.used == 28)
        // an idle session seen for the first time is no reply: its figure is taken, the record time stays
        try write("s", feed("s", windows: ["seven_day": (29, week)], cost: 5), in: dir, at: t0.addingTimeInterval(1))
        let l = try #require(await reader.scan(now: t0.addingTimeInterval(1)).limits)
        #expect(l.windows["seven_day"]?.used == 29)
        #expect(l.asOf == t0.addingTimeInterval(-600))
        #expect(l.fedAt == t0.addingTimeInterval(1))
    }

    @Test func disableAllHooksIsReported() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        let hook = Hook(settingsURL: settings, dataDir: dir)
        let obj: [String: Any] = ["disableAllHooks": true, "statusLine": ["type": "command", "command": hook.hookCommand]]
        try JSONSerialization.data(withJSONObject: obj).write(to: settings)
        try "#!/bin/sh\n".write(to: hook.hookPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.hookPath.path)
        let st = hook.status()
        #expect(st.installed && st.hooksDisabled)
        let v = ScreenBuilder.limitsView(Fixtures.input(feedState: FeedState(), hook: st))
        #expect(v == .hooksDisabled)
        #expect(Grammar.limits(v).allSatisfy { $0.cells <= Grammar.popCells })
    }

    @Test func aLongRefreshIntervalIsLoweredAndPutBack() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        let hook = Hook(settingsURL: settings, dataDir: dir)
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"~/bin/x\",\"refreshInterval\":30}}".write(to: settings, atomically: true, encoding: .utf8)
        _ = try hook.install()
        func interval() throws -> Int? {
            let o = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? [String: Any])
            return (o["statusLine"] as? [String: Any])?["refreshInterval"] as? Int
        }
        #expect(try interval() == 5)
        try hook.uninstall(previousCommand: nil)
        #expect(try interval() == 30)
        // a shorter one of the user's own stays
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"~/bin/x\",\"refreshInterval\":2}}".write(to: settings, atomically: true, encoding: .utf8)
        _ = try hook.install()
        #expect(try interval() == 2)
    }

    @Test func aCompactedSessionSaysTheNextReplyUpdatesIt() {
        var s = Snapshot(sessionId: "c", writtenAt: t0)
        s.projectDir = "/x/workspace"; s.totalCostUSD = 3.2; s.currentUsageTokens = nil
        var first = Snapshot(sessionId: "f", writtenAt: t0)
        first.projectDir = "/x/other"
        let input = Fixtures.input(feedState: FeedState(sessions: [OpenSession(snapshot: s), OpenSession(snapshot: first)], lastWriteAt: Fixtures.now))
        let lines = Grammar.sessionRows(ScreenBuilder.sessionViews(input).0, more: 0)
        #expect(lines.map(\.plain).contains(" compacted or resumed  next reply updates it"))
        #expect(lines.map(\.plain).contains(" waiting for the first reply"))
        #expect(lines.allSatisfy { $0.cells <= Grammar.popCells })
    }

    // MARK: re-check 3

    @Test func removeWithoutTheBackupPutsTheLongerIntervalBack() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        let hook = Hook(settingsURL: settings, dataDir: dir)
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"~/bin/my.sh\",\"refreshInterval\":60}}".write(to: settings, atomically: true, encoding: .utf8)
        #expect(hook.status().slowerRefresh == 60)
        let st = try hook.install()
        #expect(st.previousCommand == "~/bin/my.sh" && st.slowerRefresh == 60)
        // Application Support deleted: the backup is gone; the app's stored values are the fallback
        try FileManager.default.removeItem(at: hook.backupPath)
        try hook.uninstall(previousCommand: st.previousCommand, previousRefresh: st.slowerRefresh)
        let o = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? [String: Any])
        let sl = try #require(o["statusLine"] as? [String: Any])
        #expect(sl["command"] as? String == "~/bin/my.sh")
        #expect(sl["refreshInterval"] as? Int == 60)
    }

    @Test func theInstallTextSaysTheStatusLineThenRefreshesEveryFiveSeconds() {
        let slow = HookStatus(installed: false, previousCommand: "~/bin/my.sh", slowerRefresh: 60)
        let i = Fixtures.input(feedState: FeedState(), hook: slow)
        let v = ScreenBuilder.limitsView(i)
        #expect(v == .noHook(previous: "~/bin/my.sh", slowerRefresh: true))
        let claude = Grammar.limits(v)
        #expect(claude.map(\.plain).contains(" your status line then refreshes every 5 s"))
        let settings = Grammar.settingsTab(ScreenBuilder.screen(i).settings)
        #expect(settings.map(\.plain).contains("     your status line then refreshes every 5 s"))
        #expect((claude + settings).filter { $0.plain.contains("every 5 s") }.allSatisfy { $0.cells <= Grammar.popCells })
        // without a longer interval of the user's own, no such line
        let plain = Grammar.limits(ScreenBuilder.limitsView(Fixtures.input(feedState: FeedState(), hook: HookStatus(installed: false, previousCommand: "~/bin/my.sh")))).map(\.plain)
        #expect(!plain.contains(" your status line then refreshes every 5 s"))
    }

    @Test func aReplyWhoseWindowsAllPassedIsNotPlanless() async throws {
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        let five = t0.addingTimeInterval(20)
        try write("s", feed("s", windows: ["seven_day": (30, week), "five_hour": (50, five)], cost: 1), in: dir, at: t0)
        _ = await reader.scan(now: t0)
        // a reply carrying only a 5h window that passed by the scan
        try write("s", feed("s", windows: ["five_hour": (51, five)], cost: 2), in: dir, at: five.addingTimeInterval(-1))
        let l = try #require(await reader.scan(now: five.addingTimeInterval(2)).limits)
        #expect(!l.planless)
        #expect(ScreenBuilder.limitsView(Fixtures.input(feedState: FeedState(limits: l, lastWriteAt: Fixtures.now))) != .noLimits)
    }

    @Test func aWindowWithANullResetIsNotAFormatChange() async throws {
        let raw = Data("{\"session_id\":\"s\",\"context_window\":{\"current_usage\":{\"input_tokens\":5}},\"cost\":{\"total_cost_usd\":2},\"rate_limits\":{\"five_hour\":{\"used_percentage\":0,\"resets_at\":null}}}".utf8)
        let snap = try #require(SnapshotParser.parse(raw, writtenAt: t0))
        #expect(!snap.rateLimitsUnreadable && snap.rateLimitsCarriedWindows)
        let dir = try tempDir()
        let reader = FeedReader(dataDir: dir)
        try write("s", raw, in: dir, at: t0)
        let st = await reader.scan(now: t0)
        #expect(!st.formatChanged)
        #expect(ScreenBuilder.limitsView(Fixtures.input(feedState: st)) != .formatChanged)
    }
}
