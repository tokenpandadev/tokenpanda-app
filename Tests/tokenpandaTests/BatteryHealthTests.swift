// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Darwin
import Foundation
import Testing
@testable import MacStats
import Text
import UI

/// The word from system_profiler: one key read, the rest let go; at most one read an hour; never without the Mac tab.
struct BatteryHealthTests {
    static func output(_ word: String?) -> Data {
        let health = word.map { #""sppower_battery_health" : "\#($0)","# } ?? ""
        return Data(#"""
        {"SPPowerDataType" : [{"_name" : "spbattery_information",
          "sppower_battery_health_info" : {"sppower_battery_cycle_count" : 316, \#(health) "sppower_battery_health_maximum_capacity" : "89%"},
          "sppower_battery_model_info" : {"sppower_battery_serial_number" : "SERIALNOTKEPT"}},
          {"_name" : "sppower_information", "AC Power" : {"Wake On LAN" : "Yes"}}]}
        """#.utf8)
    }

    @Test func goodIsNormalAndAnyOtherWordIsOther() {
        #expect(BatteryHealthReader.parse(Self.output("Good")) == .normal)
        #expect(BatteryHealthReader.parse(Self.output("Fair")) == .other)
        #expect(BatteryHealthReader.parse(Self.output("Service Recommended")) == .other)
        #expect(BatteryHealthReader.parse(Self.output("Normal")) == .normal)   // as System Settings words it; the tool on macOS 27 says Good
        #expect(BatteryHealthReader.parse(Self.output("good")) == .other)   // only the exact word counts as normal
    }

    @Test func noAnswerIsNil() {
        #expect(BatteryHealthReader.parse(Self.output(nil)) == nil)
        #expect(BatteryHealthReader.parse(Self.output("")) == nil)
        #expect(BatteryHealthReader.parse(Data()) == nil)
        #expect(BatteryHealthReader.parse(Data("not json".utf8)) == nil)
        #expect(BatteryHealthReader.parse(Data(#"{"SPPowerDataType":"x"}"#.utf8)) == nil)
        #expect(BatteryHealthReader.parse(Data(#"["Good"]"#.utf8)) == nil)
    }

    @Test func aHugeAnswerIsNotParsed() {
        var data = Self.output("Good")
        data.append(Data(repeating: 0x20, count: BatteryHealthReader.limit))
        #expect(BatteryHealthReader.parse(data) == nil)
    }

    /// The result is a two case enum, so the serial number cannot travel; the screen is checked as well. The problem report takes nothing from the battery.
    @Test func theSerialNumberNeverReachesTheScreen() throws {
        var input = Fixtures.input(tab: 1)
        input.mac?.battery?.health = BatteryHealthReader.parse(Self.output("Good"))
        let text = Grammar.popover(ScreenBuilder.screen(input)).map(\.plain).joined(separator: "\n")
        #expect(text.contains("health normal"))
        #expect(!text.contains("SERIALNOTKEPT"))
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.withLock { n } }
        func hit() { lock.withLock { n += 1 } }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var at = ContinuousClock.now
        var now: ContinuousClock.Instant { lock.withLock { at } }
        func advance(_ d: Duration) { lock.withLock { at = at.advanced(by: d) } }
    }

    static func power() -> BatterySample {
        BatterySample(percent: 75, charging: false, charged: false, onAC: true, minutesToFull: nil, minutesToEmpty: nil,
                      adapterWatts: nil, watts: nil, cycles: 316, health: nil)
    }
    static func sampler(_ counter: Counter, answer: Data? = output("Good"), battery: Bool = true, clock: Clock = Clock()) -> MacSampler {
        MacSampler(healthReader: { counter.hit(); return answer }, powerSource: { battery ? power() : nil }, clock: { clock.now })
    }

    @Test func atMostOneReadAnHourAndAFailedOneWaitsToo() async {
        let counter = Counter(), clock = Clock()
        let good = Self.sampler(counter, clock: clock)
        #expect(await good.refreshHealth() == HealthRead(word: .normal))
        clock.advance(.seconds(3599))
        #expect(await good.refreshHealth() == nil)   // no read ran: the caller changes nothing
        #expect(counter.count == 1)
        clock.advance(.seconds(1))
        #expect(await good.refreshHealth() == HealthRead(word: .normal))
        #expect(counter.count == 2)

        let failing = Counter(), later = Clock()
        let broken = Self.sampler(failing, answer: nil, clock: later)
        #expect(await broken.refreshHealth() == HealthRead(word: nil))
        later.advance(.seconds(60))
        #expect(await broken.refreshHealth() == nil)
        #expect(failing.count == 1)
        #expect(await broken.sample(full: true).battery?.health == nil)
    }

    /// The hour runs on the continuous clock: a date handed to a sample, or the Mac's clock set anywhere, moves nothing.
    @Test func settingTheClockDoesNotBringAReadForward() async {
        let counter = Counter()
        let sampler = Self.sampler(counter)
        _ = await sampler.refreshHealth()
        for hours in [-2.0, 2.0, 48.0] {
            _ = await sampler.sample(full: true, readHealth: true, now: Date().addingTimeInterval(hours * 3600))
        }
        #expect(await sampler.refreshHealth() == nil)
        #expect(counter.count == 1)
    }

    /// The review's finding: a sample straight after the open sample measured a few milliseconds and named the app itself as
    /// the top process. The read takes no sample of its own, and a word only goes on the screen that still shows it.
    @Test func theReadTakesNoSample() async {
        let sampler = Self.sampler(Counter())
        _ = await sampler.refreshHealth()
        #expect(await sampler.lastSampleAt == nil)
    }

    @Test func aWordIsShownOnlyOnAnOpenMacTab() {
        #expect(BatteryHealthReader.mayShow(panelShown: true, tab: 1))
        #expect(!BatteryHealthReader.mayShow(panelShown: false, tab: 1))
        #expect(!BatteryHealthReader.mayShow(panelShown: true, tab: 0))
        #expect(!BatteryHealthReader.mayShow(panelShown: true, tab: 2))
    }

    /// Without the Mac tab nothing is read and the last word stays; a closed panel never reads.
    @Test func theSamplerReadsOnlyWhenAskedAndOnlyOnce() async {
        let counter = Counter()
        let sampler = Self.sampler(counter)
        _ = await sampler.sample(full: false, readHealth: true)
        #expect(await sampler.sample(full: true, readHealth: false).battery?.health == nil)
        #expect(counter.count == 0)
        _ = await sampler.sample(full: true, readHealth: true)
        _ = await sampler.refreshHealth()
        _ = await sampler.sample(full: true, readHealth: true)
        #expect(counter.count == 1)
        #expect(await sampler.sample(full: true, readHealth: false).battery?.health == .normal)
        #expect(counter.count == 1)
    }

    @Test func aMacWithoutABatteryNeverRunsTheTool() async {
        let counter = Counter()
        let sampler = Self.sampler(counter, battery: false)
        #expect(await sampler.sample(full: true, readHealth: true).battery == nil)
        #expect(await sampler.refreshHealth() == nil)
        #expect(counter.count == 0)
    }

    /// Only the tab that shows the word reads it: the Mac tab, whichever index it has.
    @Test func onlyTheTabThatShowsTheBatteryMayRead() {
        for tab in 0..<3 {
            let text = Grammar.popover(ScreenBuilder.screen(Fixtures.input(tab: tab))).map(\.plain).joined(separator: "\n")
            #expect(BatteryHealthReader.mayRead(tab: tab) == text.contains("health normal"))
        }
    }

    /// A slow tool never holds a sample: the figures go on, and the word comes with the sample after the read.
    @Test func aSlowToolDoesNotHoldTheSamples() async {
        // against two samples with a quick tool on the same machine, not a fixed second: a busy CI runner took 1.9 to 2.5 s
        // for two full samples, the tool not counted (0.1.19 tag build)
        let quick = MacSampler(healthReader: { BatteryHealthTests.output("Good") }, powerSource: { BatteryHealthTests.power() })
        let q0 = Date()
        _ = await quick.sample(full: true, readHealth: true)
        _ = await quick.sample(full: true, readHealth: true)
        let base = Date().timeIntervalSince(q0)
        let sampler = MacSampler(healthReader: { usleep(1_500_000); return BatteryHealthTests.output("Good") }, powerSource: { BatteryHealthTests.power() })
        let began = Date()
        #expect(await sampler.sample(full: true, readHealth: true).battery?.health == nil)
        #expect(await sampler.sample(full: true, readHealth: true).battery?.health == nil)
        #expect(Date().timeIntervalSince(began) < base + 1.0)   // waiting for the tool would add 1.5 s
        #expect(await sampler.refreshHealth() == HealthRead(word: .normal))
        #expect(await sampler.sample(full: true).battery?.health == .normal)
    }

    func batteryLines(_ health: BatteryHealth?, onAC: Bool = true, cycles: Int? = 316) -> [String] {
        var input = Fixtures.input(tab: 1)
        input.mac?.battery?.health = health
        input.mac?.battery?.onAC = onAC
        input.mac?.battery?.charging = onAC
        input.mac?.battery?.minutesToEmpty = onAC ? nil : 250
        input.mac?.battery?.cycles = cycles
        let lines = Grammar.popover(ScreenBuilder.screen(input))
        let start = lines.firstIndex { $0.plain.hasPrefix(" Battery") } ?? 0
        let end = lines[start...].firstIndex { $0.plain.isEmpty } ?? lines.count
        return Array(lines[start..<end].map(\.plain).dropFirst(3))
    }

    @Test func theThreeLines() {
        #expect(batteryLines(.normal) == [" full in 51 min  health normal  316 cycles"])
        #expect(batteryLines(nil) == [" full in 51 min  316 cycles"])
        #expect(batteryLines(.other) == [" full in 51 min  health: see System Settings", " 316 cycles"])
    }

    /// "System Settings" is one thing: a break falls between the figures, never inside it.
    @Test func theSettingsWordsStayOnOneRow() {
        for (toFull, toEmpty) in [(51, 250), (90, 250), (599, 599)] {
            for onAC in [true, false] {
                var input = Fixtures.input(tab: 1)
                input.mac?.battery?.health = .other
                input.mac?.battery?.onAC = onAC
                input.mac?.battery?.charging = onAC
                input.mac?.battery?.minutesToFull = toFull
                input.mac?.battery?.minutesToEmpty = toEmpty
                let rows = Grammar.popover(ScreenBuilder.screen(input)).map(\.plain)
                #expect(rows.contains { $0.contains("health: see System Settings") })
            }
        }
        #expect(Format.wrap("full in 1 h 30 min  health: see System Settings  316 cycles", 42)
                == ["full in 1 h 30 min", "health: see System Settings  316 cycles"])
        #expect(Format.wrap("a  " + String(repeating: "x", count: 50), 20).allSatisfy { $0.count <= 20 })
        // a break eats the spaces at it, in a row of three or more spaces and at the end too (review 09.11.2026)
        for (s, w) in [("bb health: see System Settings    ccc   a  316 cycles", 39), ("    ccc   full in 1 h 30 min    ccc    a  316 cycles ", 25)] {
            let rows = Format.wrap(s, w)
            #expect(rows.allSatisfy { $0 == $0.trimmingCharacters(in: .whitespaces) && !$0.isEmpty && $0.count <= w })
            #expect(rows.joined(separator: " ").split(whereSeparator: \.isWhitespace) == s.split(whereSeparator: \.isWhitespace))
        }
    }

    @Test func noLineRunsOutOfThePanel() {
        for health in [BatteryHealth.normal, .other] {
            for line in batteryLines(health, onAC: false, cycles: 12_345) {
                #expect(line.count <= Grammar.popCells)
            }
        }
    }

    @Test func nothingLeftMeansNoEmptyLine() {
        #expect(batteryLines(nil, onAC: true, cycles: nil).filter { !$0.isEmpty }.count <= 1)
        var input = Fixtures.input(tab: 1)
        input.mac?.battery?.health = nil
        input.mac?.battery?.cycles = nil
        input.mac?.battery?.charging = false
        let screen = Grammar.popover(ScreenBuilder.screen(input))
        #expect(!screen.contains { ($0.label ?? "").hasSuffix(", ") })
    }

}

/// The tool runner itself, with small tools written for the test: nothing here runs system_profiler. One at a time: the
/// quit test stops every running tool.
@Suite(.serialized) struct BatteryToolTests {
    static func tool(_ body: String) throws -> (path: String, pidFile: String) {
        let dir = TestTemp.root.appendingPathComponent("fake-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pidFile = dir.appendingPathComponent("pid").path
        let file = dir.appendingPathComponent("tool")
        try Data("#!/bin/sh\necho $$ > '\(pidFile)'\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return (file.path, pidFile)
    }

    /// The limit for a tool that is expected to answer, wide for a slow machine; the tools expected to fail take the short one.
    static func run(_ path: String, answerSeconds: Double = 0.5) -> (Data?, TimeInterval) {
        let t = Date()
        let out = BatteryHealthReader.run(tool: path, arguments: [], answerSeconds: answerSeconds, stopSeconds: 0.3)
        return (out, Date().timeIntervalSince(t))
    }

    /// A tool stopped before its first line wrote no pid file: it is gone as well.
    static func gone(_ pidFile: String) -> Bool {
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
        for _ in 0..<40 where kill(pid, 0) == 0 { usleep(50_000) }
        return kill(pid, 0) != 0
    }

    @Test func theWholeLimitIsFiveSeconds() {
        #expect(BatteryHealthReader.answerSeconds + BatteryHealthReader.stopSeconds <= 5)
    }

    @Test func aGoodToolGivesItsOutput() throws {
        let t = try Self.tool("printf hello")
        let (out, _) = Self.run(t.path, answerSeconds: 5)
        #expect(out == Data("hello".utf8))
        #expect(BatteryHealthReader.running.count == 0)
    }

    @Test func aHungToolIsStopped() throws {
        let t = try Self.tool("exec sleep 300")
        let (out, took) = Self.run(t.path)
        #expect(out == nil)
        #expect(took < 5)
        #expect(Self.gone(t.pidFile))
    }

    @Test func aToolIgnoringTheStopSignalIsKilled() throws {
        let t = try Self.tool("trap '' TERM\nexec sleep 300")
        let (out, took) = Self.run(t.path)
        #expect(out == nil)
        #expect(took < 5)
        #expect(Self.gone(t.pidFile))
    }

    /// The fault the review found: stdout closed, tool still running. The limit covers the wait for its exit too.
    @Test func aToolThatClosesItsOutputAndStaysIsStopped() throws {
        let t = try Self.tool("exec >&-\nexec sleep 300")
        let (out, took) = Self.run(t.path)
        #expect(out == nil)
        #expect(took < 5)
        #expect(Self.gone(t.pidFile))
    }

    @Test func aFloodIsCutOff() throws {
        let t = try Self.tool("exec yes")
        let (out, took) = Self.run(t.path)
        #expect(out == nil)
        #expect(took < 5)
        #expect(Self.gone(t.pidFile))
    }

    @Test func aFailingToolGivesNothing() throws {
        let t = try Self.tool("printf hello\nexit 1")
        #expect(Self.run(t.path, answerSeconds: 5).0 == nil)
    }

    @Test func aMissingToolGivesNothing() {
        #expect(Self.run("/nonexistent/tool").0 == nil)
    }

    /// The tool has left, its child holds the pipe: the answer is given up at the limit, not when the child ends.
    @Test func aChildHoldingThePipeDoesNotHoldTheRead() throws {
        let t = try Self.tool("sleep 10 &\nexit 0")
        let (out, took) = Self.run(t.path)
        #expect(out == nil)
        #expect(took < 5)
    }

    @Test func aQuitStopsARunningTool() async throws {
        let t = try Self.tool("exec sleep 300")
        let tools = RunningTools()   // its own set: a quit stays quit, and the other tests run on
        let began = Date()
        let run = Task.detached { BatteryHealthReader.run(tool: t.path, arguments: [], answerSeconds: 20, stopSeconds: 1, tools: tools) }
        for _ in 0..<500 where tools.count != 1 { try await Task.sleep(for: .milliseconds(20)) }
        tools.killAll()
        #expect(await run.value == nil)
        #expect(Date().timeIntervalSince(began) < 10)
        #expect(Self.gone(t.pidFile))
    }

    /// The gap the review found: a quit after the start and before the tool is registered, or before a read starts.
    @Test func aQuitAlsoCoversToolsThatStartAfterIt() throws {
        let t = try Self.tool("exec sleep 300")
        let tools = RunningTools()
        tools.killAll()
        #expect(!tools.add(Process()))
        let began = Date()
        #expect(BatteryHealthReader.run(tool: t.path, arguments: [], answerSeconds: 20, stopSeconds: 1, tools: tools) == nil)
        #expect(Date().timeIntervalSince(began) < 5)
        #expect(!FileManager.default.fileExists(atPath: t.pidFile))   // it never started
    }

    /// Run only on purpose: the real tool on this Mac gives an answer in time and it parses.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TP_REAL_TOOL"] == "1")) func theRealTool() throws {
        let data = try #require(BatteryHealthReader.runTool())
        #expect(BatteryHealthReader.parse(data) != nil)
    }
}
