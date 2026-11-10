// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Feed
import Text
import Prices
@testable import Transcripts

/// Files the app writes and reads that are not its own: a linked settings.json, paths with shell characters.
struct HardeningTests {
    func tempDir() throws -> URL {
        let url = TestTemp.root.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: links followed as the kernel follows them (0.1.15, audit F-2)

    /// A home under /tmp, itself a link to /private/tmp, so every test also walks a linked folder at the root.
    func tmpHome() throws -> URL {
        let url = TestTemp.root.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// realpath(3): what the kernel names, for a path that exists.
    func real(_ url: URL) throws -> String {
        let p = try #require(realpath(url.path, nil))
        defer { free(p) }
        return String(cString: p)
    }

    func sh(_ script: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    /// ~/.claude a link to dotfiles/claudedir, as stow or a dotfiles script makes it.
    func linkedClaude(_ home: URL) throws -> (claude: URL, dots: URL, claudedir: URL) {
        let fm = FileManager.default
        let dots = home.appendingPathComponent("dotfiles"), claudedir = dots.appendingPathComponent("claudedir")
        try fm.createDirectory(at: claudedir, withIntermediateDirectories: true)
        let claude = home.appendingPathComponent(".claude")
        try fm.createSymbolicLink(atPath: claude.path, withDestinationPath: "dotfiles/claudedir")
        return (claude, dots, claudedir)
    }

    /// Install, then Remove in the app or through remove.sh: the file the kernel names gets the entry and goes again,
    /// the link stays, and the file a text resolver named is never touched.
    func installAndRemove(home: URL, claude: URL, kernelTarget: String, untouched: URL, untouchedText: String) throws {
        let fm = FileManager.default
        for viaScript in [false, true] {
            let data = home.appendingPathComponent("data-\(viaScript)")
            let link = claude.appendingPathComponent("settings.json")
            #expect(try SettingsFile.resolve(link).path == kernelTarget)
            let set = HookSet(folders: [claude], dataDir: data, home: home)
            _ = try set.install()
            #expect(set.status().installed, "Claude Code reads the file Install wrote")
            let obj = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: kernelTarget))) as? [String: Any])
            #expect((obj["statusLine"] as? [String: Any])?["command"] as? String == set.hooks[0].hookCommand)
            #expect(try String(contentsOf: untouched, encoding: .utf8) == untouchedText)
            if viaScript { #expect(try sh(try #require(set.removeScriptPath)) == 0) }
            else { try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil }) }
            #expect(!fm.fileExists(atPath: kernelTarget), viaScript ? "script" : "app")
            #expect(isLink(link), viaScript ? "script" : "app")
            #expect(try String(contentsOf: untouched, encoding: .utf8) == untouchedText, viaScript ? "script" : "app")
            // the target's folder is the user's and stays; Install made no folder of its own (audit F-6)
            #expect(fm.fileExists(atPath: (kernelTarget as NSString).deletingLastPathComponent), viaScript ? "script" : "app")
        }
    }

    @Test func aRelativeLinkInALinkedFolderIsReadFromTheRealFolder() throws {
        // the audit's caseA, the verifier's V2: settings.json -> ../dotfiles/claude.json inside the linked ~/.claude.
        // The kernel counts .. from dotfiles/claudedir and names dotfiles/dotfiles/claude.json; 0.1.14 named
        // dotfiles/claude.json, the user's other file, and wrote over it whole.
        let home = try tmpHome()
        let (claude, dots, _) = try linkedClaude(home)
        try FileManager.default.createSymbolicLink(atPath: claude.appendingPathComponent("settings.json").path,
                                                   withDestinationPath: "../dotfiles/claude.json")
        let other = dots.appendingPathComponent("claude.json"), text = "{\"user\":\"my other config\",\"keep\":true}"
        try text.write(to: other, atomically: true, encoding: .utf8)
        // the kernel's file lies in dotfiles/dotfiles, which does not exist: Install says so and makes nothing (20.1.9;
        // 0.1.15 before the audit made that folder and Remove left it, audit F-6)
        let link = claude.appendingPathComponent("settings.json")
        #expect(try SettingsFile.resolve(link).path == (try real(dots)) + "/dotfiles/claude.json")
        let set = HookSet(folders: [claude], dataDir: home.appendingPathComponent("data"), home: home)
        do {
            _ = try set.install()
            Issue.record("Install wrote through a link into a missing folder")
        } catch {
            #expect("\(error)".contains("a folder that does not exist"))
        }
        #expect(!FileManager.default.fileExists(atPath: dots.appendingPathComponent("dotfiles").path))
        #expect(try String(contentsOf: other, encoding: .utf8) == text)
        #expect(isLink(link) && !set.status().installed)
        // nothing of Install is left: no script, no backup, no remove.sh
        #expect(!FileManager.default.fileExists(atPath: set.hooks[0].hookPath.path))
        #expect(!FileManager.default.fileExists(atPath: set.hooks[0].backupPath.path))
        #expect(!FileManager.default.fileExists(atPath: try #require(set.removeScriptPath).path))
        // once the user makes the folder, Install writes the file there and Remove takes it out again
        try FileManager.default.createDirectory(at: dots.appendingPathComponent("dotfiles"), withIntermediateDirectories: false)
        try installAndRemove(home: home, claude: claude, kernelTarget: try real(dots) + "/dotfiles/claude.json", untouched: other, untouchedText: text)
    }

    @Test func installMakesOnlyTheSettingsFolderItselfNeverAFolderALinkPointsInto() throws {
        // spec 20.1.9: a missing ~/.claude is made, as Claude Code makes it; a ~/.claude that is a link into a missing
        // folder, or a settings.json that links into one, is refused with the folder named
        let fm = FileManager.default
        let home = try tmpHome()
        let plain = home.appendingPathComponent("plain/.claude")
        _ = try Hook(settingsURL: plain.appendingPathComponent("settings.json"), dataDir: home.appendingPathComponent("d1")).install()
        #expect(fm.fileExists(atPath: plain.appendingPathComponent("settings.json").path))
        let dangling = home.appendingPathComponent(".claude")
        try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: "dotfiles/claudedir")
        let hook = Hook(settingsURL: dangling.appendingPathComponent("settings.json"), dataDir: home.appendingPathComponent("d2"))
        #expect(throws: HookError.self) { try hook.install() }
        #expect(!fm.fileExists(atPath: home.appendingPathComponent("dotfiles").path))
        #expect(!fm.fileExists(atPath: hook.hookPath.path) && !fm.fileExists(atPath: hook.backupPath.path))
        let reason = SettingsFile.reason(SettingsFile.MissingFolder(folder: URL(fileURLWithPath: NSHomeDirectory() + "/dotfiles/sub")))
        #expect(reason == "it is a link into ~/dotfiles/sub, a folder that does not exist")
    }

    @Test func aCorrectRelativeLinkFromTheDotfilesFolderWritesItsOwnTarget() throws {
        // the verifier's V1: settings.json -> ../claude.json, right for the real folder, its target not made yet.
        // The kernel names dotfiles/claude.json; 0.1.14 named claude.json in the home folder.
        let home = try tmpHome()
        let (claude, dots, _) = try linkedClaude(home)
        try FileManager.default.createSymbolicLink(atPath: claude.appendingPathComponent("settings.json").path, withDestinationPath: "../claude.json")
        let inHome = home.appendingPathComponent("claude.json"), text = "{\"mine\":1}"
        try text.write(to: inHome, atomically: true, encoding: .utf8)
        try installAndRemove(home: home, claude: claude, kernelTarget: try real(dots) + "/claude.json", untouched: inHome, untouchedText: text)
    }

    @Test func theResolverMatchesTheKernelForEveryLinkLayout() throws {
        let fm = FileManager.default
        let home = try tmpHome()
        let (claude, dots, claudedir) = try linkedClaude(home)
        let target = dots.appendingPathComponent("settings-real.json")
        try "{}".write(to: target, atomically: true, encoding: .utf8)
        func link(_ name: String, _ dest: String, in dir: URL) throws -> URL {
            let u = dir.appendingPathComponent(name)
            try fm.createSymbolicLink(atPath: u.path, withDestinationPath: dest)
            return u
        }
        // a target that exists: the same file as realpath, whatever the layout
        let existing = [
            try link("abs", target.path, in: claude),                         // absolute, through the linked folder
            try link("rel", "../settings-real.json", in: claude),             // relative, through the linked folder
            try link("plainrel", "dotfiles/settings-real.json", in: home),    // relative, no linked folder on the way
            try link("chain", "rel", in: claude),                             // a link to a link
            target,                                                           // no link at all
        ]
        for u in existing { #expect(try SettingsFile.resolve(u).path == (try real(u)), "\(u.lastPathComponent)") }
        // a target not made yet: the real folder it would be made in, plus its name
        let plainDir = home.appendingPathComponent("plain")
        try fm.createDirectory(at: plainDir, withIntermediateDirectories: true)
        #expect(try SettingsFile.resolve(plainDir.appendingPathComponent("settings.json")).path == (try real(plainDir)) + "/settings.json")
        let dangling = try link("dangling", "../new/settings.json", in: claude)
        #expect(try SettingsFile.resolve(dangling).path == (try real(dots)) + "/new/settings.json")
        #expect(try SettingsFile.resolve(claude.appendingPathComponent("missing.json")).path == (try real(claudedir)) + "/missing.json")
        // a loop: an error, never a hang
        _ = try link("a", "b", in: home)
        let loop = try link("b", "a", in: home)
        #expect(throws: POSIXError.self) { try SettingsFile.resolve(loop) }
    }

    @Test func aDotDotAfterAMissingFolderIsAnErrorAsInTheKernel() throws {
        // spec 20.1.6: d/settings.json -> nodir/../other.json, other.json next to it. The kernel opens nothing (ENOENT);
        // removing ".." by text named other.json, and Install wrote over it.
        let fm = FileManager.default
        let home = try tmpHome()
        let d = home.appendingPathComponent("d")
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        let other = d.appendingPathComponent("other.json"), text = "{\"keep\":true}"
        try text.write(to: other, atomically: true, encoding: .utf8)
        let link = d.appendingPathComponent("settings.json")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "nodir/../other.json")
        #expect(open(link.path, O_RDONLY) == -1 && errno == ENOENT)
        #expect(throws: POSIXError(.ENOENT)) { try SettingsFile.resolve(link) }
        let set = HookSet(folders: [d], dataDir: home.appendingPathComponent("data"), home: home)
        #expect(throws: (any Error).self) { try set.install() }
        #expect(try String(contentsOf: other, encoding: .utf8) == text)
        #expect(!set.status().installed)
    }

    @Test func onlyAMissingPartEndsTheWalkOtherErrorsAreThrown() throws {
        // spec 20.1.7: a file used as a folder is ENOTDIR, also before a ".."; a folder that cannot be read is EACCES
        let fm = FileManager.default
        let home = try tmpHome()
        let file = home.appendingPathComponent("file")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: POSIXError(.ENOTDIR)) { try SettingsFile.resolve(file.appendingPathComponent("settings.json")) }
        try fm.createSymbolicLink(atPath: home.appendingPathComponent("l").path, withDestinationPath: "file/../file")
        #expect(throws: POSIXError(.ENOTDIR)) { try SettingsFile.resolve(home.appendingPathComponent("l")) }
        let locked = home.appendingPathComponent("locked")
        try fm.createDirectory(at: locked.appendingPathComponent("inner"), withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(throws: POSIXError(.EACCES)) { try SettingsFile.resolve(locked.appendingPathComponent("inner/settings.json")) }
    }

    @Test func thirtyTwoLinksResolveTheThirtyThirdIsALoopAsInTheKernel() throws {
        // spec 20.1.8: /tmp is itself a link, so 31 links in the home plus /tmp are 32
        let fm = FileManager.default
        let home = try tmpHome()
        try "{}".write(to: home.appendingPathComponent("t"), atomically: true, encoding: .utf8)
        var prev = "t"
        for i in 1...32 {
            try fm.createSymbolicLink(atPath: home.appendingPathComponent("l\(i)").path, withDestinationPath: prev)
            prev = "l\(i)"
        }
        let ok = home.appendingPathComponent("l31"), loop = home.appendingPathComponent("l32")
        let fd = open(ok.path, O_RDONLY)
        #expect(fd >= 0)
        if fd >= 0 { close(fd) }
        #expect(try SettingsFile.resolve(ok).path == (try real(home)) + "/t")
        #expect(open(loop.path, O_RDONLY) == -1 && errno == ELOOP)
        #expect(throws: POSIXError(.ELOOP)) { try SettingsFile.resolve(loop) }
    }

    @Test func aFolderLeftBy0114InstallsIntoTheRightFileWithTheWrongOneKept() throws {
        // spec 20.1.5: 0.1.14 in the verifier's V1 layout wrote the entry into ~/claude.json and a backup with
        // createdSettings, and said not installed. 0.1.15 offers Install, writes dotfiles/claude.json, leaves
        // ~/claude.json as 0.1.14 left it, and Remove gives back the state before 0.1.15's Install.
        let fm = FileManager.default
        let home = try tmpHome()
        let (claude, dots, _) = try linkedClaude(home)
        let link = claude.appendingPathComponent("settings.json")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "../claude.json")
        let data = home.appendingPathComponent("data")
        let set = HookSet(folders: [claude], dataDir: data, home: home)
        let hook = set.hooks[0]
        // what 0.1.14's Install left: the entry in the wrong file, the script, the backup
        try fm.createDirectory(at: data.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let wrong = home.appendingPathComponent("claude.json")
        let wrongText = "{\n  \"statusLine\" : {\n    \"command\" : \"\(hook.hookCommand)\",\n    \"refreshInterval\" : 5,\n    \"type\" : \"command\"\n  }\n}"
        try wrongText.write(to: wrong, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nPREV=''\n".write(to: hook.hookPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.hookPath.path)
        try "{\"createdSettings\":true}".write(to: hook.backupPath, atomically: true, encoding: .utf8)
        #expect(!set.status().installed)   // Claude Code's path is still missing: Install is offered
        _ = try set.install()
        let right = try real(dots) + "/claude.json"
        #expect(set.status().installed)
        let obj = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: right))) as? [String: Any])
        #expect((obj["statusLine"] as? [String: Any])?["command"] as? String == hook.hookCommand)
        #expect(try String(contentsOf: wrong, encoding: .utf8) == wrongText)
        let backup = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: hook.backupPath)) as? [String: Any])
        #expect(backup["createdSettings"] as? Bool == true && backup["statusLine"] == nil)
        try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        #expect(!fm.fileExists(atPath: right) && isLink(link))
        #expect(try String(contentsOf: wrong, encoding: .utf8) == wrongText)
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

    @Test func aBrokenSettingsFileSaysItIsNotValidJSON() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try #"{"model": "opus""#.write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir.appendingPathComponent("data"))
        do { _ = try hook.install(); Issue.record("installed into a broken file") } catch { #expect("\(error)".contains("is not valid JSON")) }
        // valid JSON that is not an object keeps its own reason
        try "[1, 2]".write(to: settings, atomically: true, encoding: .utf8)
        do { _ = try hook.install(); Issue.record("installed into an array") } catch { #expect("\(error)".contains("is not a JSON object")) }
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
        let root = TestTemp.root.appendingPathComponent("tokenpanda-transcripts-\(UUID().uuidString)/projects", isDirectory: true)
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
