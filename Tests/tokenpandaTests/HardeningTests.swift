// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed
import Text
import Prices
@testable import Transcripts

/// Files the app writes and reads that are not its own: a linked settings.json, paths with shell characters.
struct HardeningTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func mode(_ url: URL) throws -> Int {
        try #require((try FileManager.default.attributesOfItem(atPath: url.path))[.posixPermissions] as? Int)
    }

    func isLink(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    // MARK: a linked settings.json

    @Test func installAndRemoveWriteThroughALinkedSettingsFile() throws {
        let dir = try tempDir()
        let dotfiles = dir.appendingPathComponent("dotfiles", isDirectory: true)
        let claude = dir.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let real = dotfiles.appendingPathComponent("claude-settings.json")
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"/usr/local/bin/other\"},\"env\":{\"KEY\":\"secret\"}}"
            .write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        let link = claude.appendingPathComponent("settings.json")
        // a relative link, as dotfile managers make them
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../dotfiles/claude-settings.json")
        let hook = Hook(settingsURL: link, dataDir: dir.appendingPathComponent("data"))

        let st = try hook.install()
        #expect(isLink(link))
        #expect(try mode(real) == 0o600)
        let obj = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: real)) as? [String: Any])
        #expect((obj["statusLine"] as? [String: Any])?["command"] as? String == hook.hookCommand)
        #expect((obj["env"] as? [String: String])?["KEY"] == "secret")
        // no temporary file is left next to it
        #expect(try FileManager.default.contentsOfDirectory(atPath: dotfiles.path) == ["claude-settings.json"])

        try hook.uninstall(previousCommand: st.previousCommand)
        #expect(isLink(link))
        #expect(try mode(real) == 0o600)
        let back = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: real)) as? [String: Any])
        #expect((back["statusLine"] as? [String: Any])?["command"] as? String == "/usr/local/bin/other")
    }

    @Test func aWriteKeepsTheModeAndANewFileIsOwnerOnly() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try "{}".write(to: settings, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: settings.path)
        let hook = Hook(settingsURL: settings, dataDir: dir.appendingPathComponent("data"))
        _ = try hook.install()
        #expect(try mode(settings) == 0o640)

        let fresh = try tempDir().appendingPathComponent("new/settings.json")
        let h2 = Hook(settingsURL: fresh, dataDir: dir.appendingPathComponent("data2"))
        _ = try h2.install()
        #expect(try mode(fresh) == 0o600)
    }

    @Test func aLinkToAFileNotYetThereCreatesTheTarget() throws {
        let dir = try tempDir()
        let target = dir.appendingPathComponent("elsewhere.json")
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        let hook = Hook(settingsURL: link, dataDir: dir.appendingPathComponent("data"))
        // a dangling link reads as no settings.json: Install makes the file the link names, owner only
        _ = try hook.install()
        #expect(isLink(link))
        #expect(try mode(target) == 0o600)
        #expect(hook.status().installed)
    }

    // MARK: the hook script's data folder

    @Test func hookScriptQuotesAnyDataFolderPath() throws {
        let dir = try tempDir()
        // $, a backtick, a double and a single quote and a space: none may expand or end the quoting
        let weird = dir.appendingPathComponent("a $HOME `touch pwned` \"q\" it's", isDirectory: true)
        let sessions = weird.appendingPathComponent("sessions").path
        let text = HookScript.render(sessionsDir: sessions, previousCommand: nil)
        #expect(text.contains("DIR='" + sessions.replacingOccurrences(of: "'", with: "'\\''") + "'"))
        let script = dir.appendingPathComponent("hook.sh")
        try text.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        p.currentDirectoryURL = dir
        let inPipe = Pipe()
        p.standardInput = inPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data("{\"session_id\":\"3f1a9c2e-0000-4000-8000-000000000001\"}".utf8))
        inPipe.fileHandleForWriting.closeFile()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: sessions + "/3f1a9c2e-0000-4000-8000-000000000001.json"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("pwned").path))
    }

    // MARK: numbers out of range, files over the size limits

    @Test func feedNumbersOutOfRangeAreIgnoredNotTrapped() throws {
        let json = """
        {"session_id":"3f1a9c2e-0000-4000-8000-000000000001",
         "context_window":{"context_window_size":1e300,"used_percentage":1e300,
           "current_usage":{"input_tokens":9223372036854775807,"output_tokens":1e300,"cache_creation_input_tokens":-5,"cache_read_input_tokens":7}},
         "cost":{"total_cost_usd":1e300,"total_lines_added":1e300,"total_lines_removed":-1},
         "rate_limits":{"seven_day":{"used_percentage":1e300,"resets_at":1e300},"five_hour":{"used_percentage":40,"resets_at":1e300},
                        "other":{"used_percentage":12,"resets_at":1800000000}}}
        """
        let s = try #require(SnapshotParser.parse(Data(json.utf8), writtenAt: Date()))
        #expect(s.contextWindowSize == nil)
        #expect(s.contextUsedPercentage == nil)
        #expect(s.currentUsageTokens == 7)            // the counts out of range are left out of the sum
        #expect(s.totalCostUSD == nil && s.linesAdded == nil && s.linesRemoved == nil)
        #expect(s.rateLimits?.keys.sorted() == ["other"])
    }

    @Test func storedLimitsAndWeeksOutOfRangeAreDropped() async throws {
        let dir = try tempDir()
        let weeks = dir.appendingPathComponent("weeks.json")
        try #"{"records":[{"resetsAt":1e300,"lastUsed":5,"lastSeenAt":0},{"resetsAt":1800000000,"lastUsed":1e300,"lastSeenAt":0},{"resetsAt":1800000000,"lastUsed":12,"lastSeenAt":0}]}"#
            .write(to: weeks, atomically: true, encoding: .utf8)
        #expect(WeekRecords.load(from: weeks).records.map(\.lastUsed) == [12])
        try #"{"windows":{"seven_day":{"used":1e300,"resetsAt":1800000000}},"asOf":1800000000}"#
            .write(to: dir.appendingPathComponent("limits.json"), atomically: true, encoding: .utf8)
        let limits = await FeedReader(dataDir: dir).scan(now: Date()).limits
        #expect(limits == nil)
    }

    @Test func transcriptCountsNearIntMaxNeitherTrapNorCount() {
        // one line with counts past the range is skipped; sums of counts in range saturate instead of trapping
        let big = #"{"type":"assistant","timestamp":"2026-10-13T14:14:25.753Z","sessionId":"s","message":{"id":"m1","model":"claude-fable-5-1","usage":{"input_tokens":9223372036854775807,"output_tokens":9223372036854775807}}}"#
        let file = TranscriptFile(url: URL(fileURLWithPath: "/tmp/x.jsonl"), projectFolder: "-tmp", sessionId: "s", isAgent: false, size: 0, modified: Date())
        #expect(TranscriptParser.parse(line: Data(big.utf8), file: file) == nil)
        let u = Usage(input: Int.max, output: Int.max, cacheRead: 1, cacheWrite: 1)
        #expect(u.total == Int.max)
        #expect(u.promptSize == Int.max)
        let now = Date()
        let recs = (0..<3).map { UsageRecord(timestamp: now.addingTimeInterval(-60), model: "claude-fable-5-1", project: "p", session: "s\($0)", isAgent: false, usage: u) }
        let s = Aggregator.summarize(recs, now: now)
        #expect(s.tokens7d == Int.max)
        #expect(s.byProject7d.first?.tokens == Int.max)
    }

    @Test func snapshotFilesOverOneMegabyteAreSkipped() async throws {
        let dir = try tempDir()
        let sessions = dir.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let small = #"{"session_id":"3f1a9c2e-0000-4000-8000-000000000001","workspace":{"project_dir":"/tmp/a"}}"#
        try small.write(to: sessions.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        let padded = #"{"session_id":"3f1a9c2e-0000-4000-8000-000000000002","pad":""# + String(repeating: "x", count: SafeFile.jsonLimit) + #""}"#
        try padded.write(to: sessions.appendingPathComponent("b.json"), atomically: true, encoding: .utf8)
        let st = await FeedReader(dataDir: dir).scan(now: Date())
        #expect(st.sessions.map(\.snapshot.sessionId) == ["3f1a9c2e-0000-4000-8000-000000000001"])
    }

    @Test func sessionFilesAreSizeCheckedBeforeTheyAreRead() throws {
        let dir = try tempDir()
        let folder = dir.appendingPathComponent(".claude", isDirectory: true)
        let sessions = folder.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let me = getpid()
        try #"{"pid":\#(me),"sessionId":"3f1a9c2e-0000-4000-8000-000000000001","cwd":"/tmp"}"#
            .write(to: sessions.appendingPathComponent("\(me).json"), atomically: true, encoding: .utf8)
        #expect(LiveSession.read(settingsFolders: [folder]).count == 1)
        try (#"{"pid":\#(me),"sessionId":"3f1a9c2e-0000-4000-8000-000000000001","pad":""# + String(repeating: "x", count: 2 << 20) + #""}"#)
            .write(to: sessions.appendingPathComponent("\(me).json"), atomically: true, encoding: .utf8)
        #expect(LiveSession.read(settingsFolders: [folder]).isEmpty)
        // a FIFO is never opened: a read would block
        let fifo = sessions.appendingPathComponent("fifo.json")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(SafeFile.read(fifo) == nil)
        #expect(LiveSession.read(settingsFolders: [folder]).isEmpty)
    }

    @Test func aSettingsFileOverOneMegabyteIsRefusedWithAReason() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try (#"{"pad":""# + String(repeating: "x", count: SafeFile.jsonLimit) + #""}"#).write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir.appendingPathComponent("data"))
        #expect(throws: HookError.self) { try hook.install() }
        do { _ = try hook.install() } catch { #expect("\(error)".contains("over 1 MB")) }
    }

    @Test func transcriptPathIsOpenedOnlyWhenItIsARegularFile() throws {
        let dir = try tempDir()
        let t = dir.appendingPathComponent("t.jsonl")
        try #"{"type":"bridge-session"}"#.write(to: t, atomically: true, encoding: .utf8)
        #expect(Reopen.hadRemoteControl(transcript: t.path))
        let fifo = dir.appendingPathComponent("fifo.jsonl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(!Reopen.hadRemoteControl(transcript: fifo.path))     // returns at once instead of blocking
        #expect(!Reopen.hadRemoteControl(transcript: dir.path))
    }

    @Test func aTranscriptLineOverTheLimitIsSkippedTheNextOneCounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-transcripts-\(UUID().uuidString)/projects", isDirectory: true)
        let project = root.appendingPathComponent("-Users-someone-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        func line(_ id: String, pad: Int = 0) -> String {
            #"{"type":"assistant","timestamp":"2026-10-13T14:14:25.753Z","sessionId":"s","pad":""# + String(repeating: "x", count: pad)
                + #"","message":{"id":""# + id + #"","model":"claude-fable-5-1","usage":{"input_tokens":5,"output_tokens":5}}}"#
        }
        let file = project.appendingPathComponent("11111111-0000-4000-8000-000000000001.jsonl")
        // with a 4 KB limit and a 1 KB chunk: the long line spans many reads and is dropped without being held whole
        try (line("m1") + "\n" + line("long", pad: 10_000) + "\n" + line("m2") + "\n").write(to: file, atomically: true, encoding: .utf8)
        let store = TranscriptStore(roots: [root])
        let now = ISO8601DateFormatter().date(from: "2026-10-13T16:00:00Z") ?? Date()
        let r = await store.refresh(now: now, chunk: 1024, maxLine: 4096)
        #expect(r.records.count == 2)
        // a long line still open at the end of the file: skipped up to its newline once it comes, the next line counts
        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: Data(line("long2", pad: 10_000).utf8))
        try h.close()
        #expect(await store.refresh(now: now, chunk: 1024, maxLine: 4096).records.count == 2)
        let h2 = try FileHandle(forWritingTo: file)
        try h2.seekToEnd()
        try h2.write(contentsOf: Data(("\n" + line("m3") + "\n").utf8))
        try h2.close()
        let after = await store.refresh(now: now, chunk: 1024, maxLine: 4096)
        #expect(after.records.count == 3)
    }

    // MARK: failed writes are said

    @Test func aRemoveScriptThatCannotBeWrittenIsReported() throws {
        let dir = try tempDir()
        let data = dir.appendingPathComponent("data", isDirectory: true)
        let set = HookSet(folders: [dir], dataDir: data, home: dir.appendingPathComponent("home"))
        _ = try set.install()
        let script = try #require(set.removeScriptPath)
        #expect(set.writeRemoveScript() == nil)
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        // a folder where the script goes: the write fails and says why
        try FileManager.default.removeItem(at: script)
        try FileManager.default.createDirectory(at: script, withIntermediateDirectories: true)
        try "x".write(to: script.appendingPathComponent("keep"), atomically: true, encoding: .utf8)
        let error = set.writeRemoveScript()
        #expect(error != nil)
    }

    @Test func theSettingsTabShowsTheRemoveScriptError() {
        let lines = Grammar.hookRow(installed: true, error: nil, removeScriptError: "permission denied")
        let text = lines.map { $0.pieces.map(\.text).joined() }.joined(separator: " ")
        #expect(text.contains("remove.sh"))
        #expect(text.contains("permission denied"))
        #expect(!Grammar.hookRow(installed: true, error: nil).map { $0.pieces.map(\.text).joined() }.joined().contains("remove.sh"))
    }

    @Test func recordsThatCannotBeWrittenReturnTheError() throws {
        let dir = try tempDir()
        let blocked = dir.appendingPathComponent("weeks.json", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked.appendingPathComponent("x"), withIntermediateDirectories: true)
        #expect(WeekRecords().save(to: blocked) != nil)
        #expect(RestoreRecord(lastScan: Date()).save(to: blocked) != nil)
        #expect(WeekRecords().save(to: dir.appendingPathComponent("ok.json")) == nil)
    }

    // MARK: packaging

    var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    @Test func thePrivacyManifestDeclaresNoTrackingAndTheReasons() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("Resources/PrivacyInfo.xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let types = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for t in types { reasons[t["NSPrivacyAccessedAPIType"] as? String ?? ""] = t["NSPrivacyAccessedAPITypeReasons"] as? [String] }
        #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1", "DDA9.1"])
        #expect(reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"])
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
    }

    @Test func theBuildShipsTheManifestAndNoHookResource() throws {
        let script = try String(contentsOf: repo.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("cp Resources/PrivacyInfo.xcprivacy \"$APP/Contents/Resources/PrivacyInfo.xcprivacy\""))
        #expect(!script.contains("Resources/hook.sh"))
    }
}
