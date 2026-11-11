// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
#if DEBUG
// Sample data for the debug snapshot flag only; release builds do not contain it.
import Foundation
import Text
import Pace
import Prices
import Feed
import Transcripts
import MacStats

/// The sample (Thursday 15 October 2026, 14:20, in the sample zone UTC) as live inputs, for the snapshot flag.
/// Every name and figure is invented sample data; nothing here comes from a real machine.
public enum Fixtures {
    public static let timeZone = TimeZone.gmt   // the sample zone
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }

    public static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) ?? Date(timeIntervalSince1970: 0)
    }

    public static let now = date(2026, 10, 15, 14, 20)
    public static let weeklyReset = date(2026, 10, 18, 18, 0)
    public static let fiveReset = date(2026, 10, 15, 17, 45)

    public static func limits(weekly: Double, five: Double = 24, asOf: Date = now.addingTimeInterval(-60)) -> Limits {
        Limits(windows: ["seven_day": .init(used: weekly, resetsAt: weeklyReset, previousResetsAt: nil, contradicts: false),
                         "five_hour": .init(used: five, resetsAt: fiveReset, previousResetsAt: nil, contradicts: false)], asOf: asOf)
    }

    static func snapshot(_ sid: String, project: String, model: String, modelId: String, tokens: Int, used: Double, cost: Double, added: Int, removed: Int) -> Snapshot {
        var s = Snapshot(sessionId: sid, writtenAt: now.addingTimeInterval(-2))
        s.projectDir = "/Users/someone/" + project
        s.modelDisplayName = model; s.modelId = modelId; s.effortLevel = "high"
        s.contextWindowSize = 1_000_000; s.contextUsedPercentage = used; s.currentUsageTokens = tokens
        s.totalCostUSD = cost; s.linesAdded = added; s.linesRemoved = removed
        s.rateLimits = ["seven_day": LimitWindow(key: "seven_day", usedPercentage: 61, resetsAt: weeklyReset),
                        "five_hour": LimitWindow(key: "five_hour", usedPercentage: 24, resetsAt: fiveReset)]
        return s
    }

    public static let openSessions: [OpenSession] = [
        OpenSession(snapshot: snapshot("3f1a9c2e-0000-4000-8000-000000000001", project: "workspace", model: "Fable 5.1", modelId: "claude-fable-5-1",
                                       tokens: 405_600, used: 41, cost: 38.20, added: 112, removed: 9)),
        OpenSession(snapshot: snapshot("7b2d4e6f-0000-4000-8000-000000000002", project: "tooling", model: "Opus 5.5", modelId: "claude-opus-5-5",
                                       tokens: 88_400, used: 9, cost: 6.10, added: 0, removed: 0)),
    ]

    public static let tokens = TokenSummary(
        byModel7d: [TokenGroup(name: "Fable 5.1", key: "claude-fable-5-1", tokens: 1_020_000_000, share: 49),
                    TokenGroup(name: "Opus 5.5", key: "claude-opus-5-5", tokens: 710_000_000, share: 34),
                    TokenGroup(name: "Sonnet 5.5", key: "claude-sonnet-5-5", tokens: 240_000_000, share: 11),
                    TokenGroup(name: "Haiku 4.5", key: "claude-haiku-4-5-20251001", tokens: 130_000_000, share: 6)],
        byProject7d: [TokenGroup(name: "workspace", key: "workspace", tokens: 1_460_000_000, share: 70),
                      TokenGroup(name: "website", key: "website", tokens: 420_000_000, share: 20),
                      TokenGroup(name: "tooling", key: "tooling", tokens: 140_000_000, share: 7),
                      TokenGroup(name: "other", key: "other", tokens: 80_000_000, share: 4)],
        bySessionToday: [TokenGroup(name: "3f1a9c2e", key: "3f1a9c2e-0000-4000-8000-000000000001", tokens: 31_200_000, share: 43),
                         TokenGroup(name: "7b2d4e6f", key: "7b2d4e6f-0000-4000-8000-000000000002", tokens: 18_000_000, share: 25),
                         TokenGroup(name: "c91e0a44", key: "c91e0a44-0000-4000-8000-000000000003", tokens: 12_600_000, share: 17),
                         TokenGroup(name: "other", key: "other", tokens: 10_600_000, share: 15)],
        agentShare7d: 44, listPrice7d: 1140, unpricedModels: 0,
        tokensToday: 72_400_000, tokens7d: 2_100_000_000, tokens30d: 9_800_000_000, total7d: 2_100_000_000, totalToday: 72_400_000)

    public static let weeks: WeekRecords = {
        var w = WeekRecords()
        w.records = [
            WeekRecord(resetsAt: date(2026, 9, 27, 18, 0), lastUsed: 88, lastSeenAt: date(2026, 9, 27, 17, 50)),
            WeekRecord(resetsAt: date(2026, 10, 4, 18, 0), lastUsed: 100, lastSeenAt: date(2026, 10, 1, 16, 10), hitAt: date(2026, 10, 1, 16, 10)),
            WeekRecord(resetsAt: date(2026, 10, 11, 18, 0), lastUsed: 96, lastSeenAt: date(2026, 10, 11, 17, 58)),
            WeekRecord(resetsAt: weeklyReset, lastUsed: 61, lastSeenAt: now.addingTimeInterval(-60)),
        ]
        return w
    }()

    public static func mac(health: BatteryHealth? = .normal, hog: Bool = false) -> MacSample {
        let gb: UInt64 = 1_073_741_824
        let procs = [ProcessSample(pid: 501, name: "Safari", cpuPercent: 6.1, footprint: UInt64(6.2 * Double(gb))),
                     ProcessSample(pid: 502, name: "Xcode", cpuPercent: 2.3, footprint: UInt64(1.4 * Double(gb))),
                     ProcessSample(pid: 503, name: "WindowServer", cpuPercent: 1.4, footprint: 512 * 1_048_576),
                     ProcessSample(pid: 504, name: "Terminal", cpuPercent: 0.8, footprint: 128 * 1_048_576),
                     ProcessSample(pid: 505, name: "Music", cpuPercent: 0.6, footprint: UInt64(2.1 * Double(gb)))]
        let battery = BatterySample(percent: 75, charging: true, charged: false, onAC: true, minutesToFull: 51, minutesToEmpty: nil,
                                    adapterWatts: 94, watts: 47.6, cycles: 316, health: health)
        var sample = MacSample(cpuBusy: 9, cpuUser: 5, cpuSystem: 4, cores: 10, gpuUtilisation: 11,
                         memoryUsed: UInt64(25.5 * Double(gb)), memoryTotal: 36 * gb, pressureLevel: hog ? 2 : 1, swapUsed: UInt64(0.9 * Double(gb)),
                         battery: battery, processes: procs, processError: nil, hogPid: nil)
        sample.processTotalCPU = 9
        return sample
    }

    public static func input(weekly: Double = 61, stale: Bool = false, feedState: FeedState? = nil, hook: HookStatus = HookStatus(installed: true, previousCommand: nil),
                             warn: Bool = false, tab: Int = 0, section: Int = 0, health: BatteryHealth? = .normal, hog: Bool = false) -> LiveInput {
        let feed = feedState ?? FeedState(limits: limits(weekly: weekly, asOf: stale ? date(2026, 10, 15, 13, 5) : now.addingTimeInterval(-60)),
                                          sessions: stale ? [] : openSessions, lastWriteAt: stale ? date(2026, 10, 15, 13, 5) : now.addingTimeInterval(-2))
        var w = weeks
        w.records[3].lastUsed = weekly
        return LiveInput(feed: feed, hook: hook, tokens: tokens, transcriptsRootsExist: true, transcriptsError: nil,
                         mac: mac(health: health, hog: hog), weeks: w, macInBar: false, nudges: true, listPrice: true, nudgeNote: nil,
                         warn: warn, tab: tab, section: section, now: now, timeZone: timeZone, calendar: calendar)
    }

    /// The version of the bundle the snapshot runs in: tokenpanda's own, never a number written here (0.1.19; the
    /// fixture said 0.1.15 in every later build). nil in a bare debug binary and in the tests, as in the app.
    public static var bundleVersion: String? {
        guard Bundle.main.bundleIdentifier == "dev.tokenpanda.app" else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Inputs past the sample's edges, for the width tests and a look: long, wide (CJK, emoji) and huge figures. Invented.
    public static func stress() -> [(String, LiveInput)] {
        let long = "an-extremely-long-project-folder-name-that-goes-on-and-on"
        let cjk = "日本語のプロジェクト名前テスト"
        let emoji = "emoji\u{1F43C}panda"
        let longModel = "Opus 5.5 with an unusually long display name of fifty"
        var names = [
            snapshot("a0000000-0000-4000-8000-000000000001", project: long, model: "Fable 5.1", modelId: "claude-fable-5-1",
                     tokens: 999_960, used: 99.6, cost: 1234.5, added: 12_345, removed: 6789),
            snapshot("a0000000-0000-4000-8000-000000000002", project: "tooling", model: longModel, modelId: "claude-opus-5-5",
                     tokens: 405_600, used: 41, cost: 1.498, added: 3, removed: 1),
            snapshot("a0000000-0000-4000-8000-000000000003", project: cjk, model: "Zeta 1", modelId: "claude-zeta-1",
                     tokens: 88_400, used: 9, cost: 0.4, added: 0, removed: 0),
            snapshot("a0000000-0000-4000-8000-000000000004", project: emoji, model: "Sonnet 5.5", modelId: "claude-sonnet-5-5",
                     tokens: 1_000_000, used: 100, cost: 6.1, added: 0, removed: 0),
            snapshot("a0000000-0000-4000-8000-000000000005", project: "x", model: String(repeating: "\u{6A21}", count: 30), modelId: "other-model",
                     tokens: 12_000, used: 1, cost: 0, added: 0, removed: 0),
        ]
        names[0].contextWindowSize = 999_600
        let open = names.map { OpenSession(snapshot: $0) } + (6...9).map { k in
            OpenSession(snapshot: snapshot("b000000\(k)-0000-4000-8000-00000000000\(k)", project: "more", model: "Haiku 4.5", modelId: "claude-haiku-4-5",
                                           tokens: 1000, used: 0.1, cost: 0, added: 0, removed: 0)) }
        let big = TokenSummary(
            byModel7d: [TokenGroup(name: "Fable 5.1", key: "claude-fable-5-1", tokens: 123_456_000_000, share: 91),
                        TokenGroup(name: "Opus 5.5", key: "claude-opus-5-5", tokens: 10_000_000_000, share: 7),
                        TokenGroup(name: "Zeta 1", key: "claude-zeta-1", tokens: 3_000_000, share: 0),
                        TokenGroup(name: "Unpriced thing with a long name", key: "gpt-x", tokens: 999_999_999, share: 1),
                        TokenGroup(name: "other", key: "other", tokens: 4_000, share: 0)],
            byProject7d: [TokenGroup(name: cjk, key: cjk, tokens: 999_999_999, share: 60),
                          TokenGroup(name: emoji, key: emoji, tokens: 99_960, share: 30),
                          TokenGroup(name: long, key: long, tokens: 999_950, share: 10)],
            bySessionToday: [TokenGroup(name: "a0000000", key: "a0000000-0000-4000-8000-000000000001", tokens: 31_200_000, share: 50),
                             TokenGroup(name: "a0000000", key: "a0000000-0000-4000-8000-000000000003", tokens: 18_000_000, share: 30),
                             TokenGroup(name: "c91e0a44", key: "c91e0a44-0000-4000-8000-000000000003", tokens: 12_600_000, share: 20)],
            agentShare7d: 100, listPrice7d: 1.498, unpricedModels: 2,
            tokensToday: 999_999_999, tokens7d: 133_459_003_999, tokens30d: 9_999_999_999_999, total7d: 0, totalToday: 0)
        var lim = limits(weekly: 100, five: 99.5)
        lim.windows["seven_day_opus_extra_long_key_that_runs_well_past_the_panel_edge"] = .init(used: 12, resetsAt: weeklyReset)
        var wide = input(feedState: FeedState(limits: lim, sessions: open, lastWriteAt: now.addingTimeInterval(-2)))
        wide.tokens = big
        wide.sessionNames = ["a0000000-0000-4000-8000-000000000002": "renamed " + cjk + " " + emoji]
        var m = mac()
        m.memoryUsed = m.memoryTotal; m.swapUsed = 12 * 1_073_741_824
        m.processes = [ProcessSample(pid: 1, name: cjk, cpuPercent: 1000.5, footprint: 40 * 1_073_741_824),
                       ProcessSample(pid: 2, name: emoji, cpuPercent: 123.4, footprint: 1),
                       ProcessSample(pid: 3, name: long, cpuPercent: 99.96, footprint: 512)]
        m.processTotalCPU = 1224
        wide.mac = m
        var huge = wide
        huge.tokens = TokenSummary(
            byModel7d: [TokenGroup(name: "Fable 5.1", key: "claude-fable-5-1", tokens: Int.max, share: 100),
                        TokenGroup(name: "Opus 5.5", key: "claude-opus-5-5", tokens: 1, share: 0)],
            byProject7d: [TokenGroup(name: long, key: long, tokens: Int.max / 3, share: 100)],
            bySessionToday: [TokenGroup(name: "a0000000", key: "a0000000", tokens: Int.max, share: 100)],
            agentShare7d: 0, listPrice7d: 123_456_789.5, unpricedModels: 12,
            tokensToday: Int.max, tokens7d: Int.max, tokens30d: Int.max, total7d: 0, totalToday: 0)
        var hugeSessions = open
        hugeSessions[0].snapshot.currentUsageTokens = Int.max
        hugeSessions[0].snapshot.contextWindowSize = Int.max
        hugeSessions[0].snapshot.contextUsedPercentage = 1e300
        huge.feed.sessions = hugeSessions
        var planless = input(feedState: FeedState(limits: Limits(asOf: now.addingTimeInterval(-60), planless: true),
                                                  sessions: openSessions, lastWriteAt: now.addingTimeInterval(-2)))
        planless.weeks = WeekRecords()
        var none = input()
        none.transcriptsRootsExist = false
        none.transcriptFolders = ["~/.claude/projects", "~/.config/claude/projects", "~/.claude-work/projects", "/Volumes/Some Disk/claude/" + long + "/projects"]
        var failed = input()
        failed.tokens = nil
        failed.transcriptsError = "The file \u{201C}projects\u{201D} couldn\u{2019}t be opened because you don\u{2019}t have permission to view it."
        failed.transcriptFolders = none.transcriptFolders
        var sampling = input(tab: 1)
        sampling.mac = nil
        var procError = input(tab: 1)
        procError.mac?.processes = []
        procError.mac?.processError = "The process list could not be read: an error that is long enough to run past the panel edge twice over"
        var priceOff = input()
        priceOff.listPrice = false
        return [
            ("stress-wide", wide), ("stress-wide-projects", { var i = wide; i.section = 1; return i }()),
            ("stress-wide-sessions", { var i = wide; i.section = 2; return i }()), ("stress-wide-mac", { var i = wide; i.tab = 1; return i }()),
            ("stress-huge", huge), ("stress-huge-mac", { var i = huge; i.tab = 1; return i }()),
            ("stress-planless", planless), ("stress-no-transcripts", none), ("stress-transcripts-error", failed),
            ("stress-sampling", sampling), ("stress-process-error", procError), ("stress-price-off", priceOff),
        ]
    }

    /// Every state the docs show, by the shot names in docs/shots/app.
    public static func all() -> [(String, LiveInput)] {
        let fresh = FeedState(limits: nil, sessions: [], lastWriteAt: nil)
        var noLimitsSnap = openSessions
        noLimitsSnap = noLimitsSnap.map { var o = $0; o.snapshot.rateLimits = nil; return o }
        let noLimits = FeedState(limits: nil, sessions: noLimitsSnap, lastWriteAt: now.addingTimeInterval(-2))
        var passedWeeks = weeks
        passedWeeks.records[3].lastUsed = 61
        let passed = FeedState(limits: Limits(windows: ["seven_day": .init(used: 61, resetsAt: date(2026, 10, 11, 18, 0), previousResetsAt: nil, contradicts: false),
                                                        "five_hour": .init(used: 24, resetsAt: date(2026, 10, 11, 17, 45), previousResetsAt: nil, contradicts: false)],
                                              asOf: date(2026, 10, 11, 13, 5)), sessions: [], lastWriteAt: date(2026, 10, 11, 13, 5))
        var resetPassed = input(feedState: passed)
        resetPassed.weeks = passedWeeks
        var settings = input(tab: 2)
        settings.keepAwake = true; settings.awake = .working(2)   // the sample's two open sessions, both working
        settings.login = .on
        settings.restoreSessions = true
        settings.version = bundleVersion
        // the first call: two sessions open, neither has replied, no rate_limits yet
        let waitingSnap = openSessions.map { var o = $0; o.snapshot.rateLimits = nil; o.snapshot.currentUsageTokens = nil; o.snapshot.totalCostUSD = 0; return o }
        let firstReply = input(feedState: FeedState(limits: nil, sessions: waitingSnap, lastWriteAt: now.addingTimeInterval(-2)))
        // Install refused: settings.json is not valid JSON
        var installFailed = input(feedState: fresh, hook: HookStatus(installed: false, previousCommand: nil))
        installFailed.hookError = "Could not install the entry: cannot read settings.json: settings.json is not valid JSON"
        // two settings folders, the entry in one, its script gone in the other, and the error of the last Install
        var folders = input(hook: HookStatus(installed: false, previousCommand: nil, scriptMissing: true, anyInstalled: true,
                                             targets: ["~/.claude", "~/.claude-work"]), tab: 2)
        folders.hookError = "Could not install the entry: ~/.claude-work: cannot write settings.json: You don\u{2019}t have permission"
        folders.nudgeNote = "Notifications are off in System Settings"
        folders.restoreSessions = true
        folders.reopenApp = .ghostty   // the pop-up on Ghostty, with the line that says it asks
        folders.removeScriptError = "You don\u{2019}t have permission"
        // the weekly reset on Sunday 18:00 passed half an hour ago with no session: the row after 12 Oct says 19 Oct
        var rolled = input(feedState: FeedState(limits: limits(weekly: 61, asOf: date(2026, 10, 18, 17, 40)), sessions: [], lastWriteAt: date(2026, 10, 18, 17, 40)))
        rolled.now = date(2026, 10, 18, 18, 30)
        return [
            ("claude-overpace", input(weekly: 61)),
            ("claude-ahead", input(weekly: 45)),
            ("claude-onpace", input(weekly: 57)),
            ("claude-stale", input(weekly: 61, stale: true)),
            ("claude-nohook", input(feedState: fresh, hook: HookStatus(installed: false, previousCommand: nil))),
            ("claude-nosession", input(feedState: fresh)),
            ("claude-nolimits", input(feedState: noLimits)),
            ("claude-resetpassed", resetPassed),
            ("claude-projects", input(section: 1)),
            ("claude-sessions", input(section: 2)),
            ("mac", input(tab: 1)),
            ("mac-warning", input(warn: true, tab: 1)),
            ("mac-pressure-warn", input(warn: true, tab: 1, hog: true)),   // memory pressure warn, as pop-mac-warning.html draws it
            ("mac-no-health", input(tab: 1, health: nil)),
            ("mac-health-other", input(tab: 1, health: .other)),
            ("settings", settings),
            ("claude-firstreply", firstReply),
            ("claude-install-failed", installFailed),
            ("claude-week-rolled", rolled),
            ("settings-folders", folders),
        ]
    }
}
#endif
