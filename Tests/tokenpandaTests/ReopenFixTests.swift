// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed
import MacStats
import Transcripts
import UI

/// 0.1.19: Reopen, the restore record, settings.json and the background work. Every file is made under TestTemp.root.
struct ReopenFixTests {
    let id = "3f1a9c2e-0000-4000-8000-000000000001"
    let id2 = "3f1a9c2e-0000-4000-8000-000000000002"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func dir(_ name: String = "d") throws -> URL {
        let u = TestTemp.root.appendingPathComponent("reopenfix-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func open(_ id: String, folder: String?, transcript: String? = nil) -> OpenSession {
        var s = Snapshot(sessionId: id, writtenAt: t0)
        s.projectDir = folder
        s.transcriptPath = transcript
        return OpenSession(snapshot: s)
    }

    // MARK: 24.1 a skipped session is logged and told

    @Test func aSessionWhoseFolderIsGoneIsSkippedAndSaidSo() throws {
        // the VM case of flow test 11.3: the session ran in a folder under /tmp, which the restart emptied
        let data = try dir("data")
        let base = Reopen.baseFolder(dataDir: data)
        let gone = "/tmp/tokenpanda-test-gone-\(UUID().uuidString)"
        let e = RestoreRecord.Entry(id: id, folder: gone, transcript: nil, lastSeen: t0, name: "api work")
        let w = ReopenWrite.write([e], into: base, now: t0, remoteControl: { _ in false })
        #expect(w.files.isEmpty && w.folder == nil)
        #expect(w.skipped == [ReopenWrite.Skip(id: id, label: "api work", code: .folderGone)])
        #expect(w.counts == "folder-gone 1")
        // no empty folder is left behind
        #expect((try? FileManager.default.contentsOfDirectory(atPath: base.path))?.isEmpty ?? true)
        let notice = try #require(w.nothingOpened())
        #expect(notice.title == "api work did not reopen" && notice.body == "Its folder is gone.")
    }

    @Test func oneGoneOneThereOpensOneAndTellsNothing() throws {
        let data = try dir("data"), there = try dir("project")
        let entries = [RestoreRecord.Entry(id: id, folder: there.path, transcript: nil, lastSeen: t0),
                       RestoreRecord.Entry(id: id2, folder: "/tmp/tokenpanda-test-gone-\(UUID().uuidString)", transcript: nil, lastSeen: t0)]
        let w = ReopenWrite.write(entries, into: Reopen.baseFolder(dataDir: data), now: t0, remoteControl: { _ in false })
        #expect(w.files.count == 1 && w.skipped.map(\.code) == [.folderGone])
        #expect(w.nothingOpened() == nil)
    }

    @Test func aFolderThatCannotBeMadeIsSaidForEach() throws {
        let data = try dir("data"), there = try dir("project")
        // the data folder's reopen/ is a file: the Reopen folder cannot be made
        try Data("x".utf8).write(to: Reopen.baseFolder(dataDir: data))
        let entries = [RestoreRecord.Entry(id: id, folder: there.path, transcript: nil, lastSeen: t0),
                       RestoreRecord.Entry(id: id2, folder: there.path, transcript: nil, lastSeen: t0)]
        let w = ReopenWrite.write(entries, into: Reopen.baseFolder(dataDir: data), now: t0, remoteControl: { _ in false })
        #expect(w.files.isEmpty && w.skipped.map(\.code) == [.folderWrite, .folderWrite])
        let notice = try #require(w.nothingOpened())
        #expect(notice.title == "2 sessions did not reopen")
        #expect(notice.body == "Their start scripts could not be written to tokenpanda's data folder.")
    }

    // MARK: 24.2 a second settings folder

    @Test func aSessionOfASecondSettingsFolderReopensUnderIt() throws {
        let home = try dir("home"), project = try dir("project")
        let work = home.appendingPathComponent(".claude-work").path
        let s = try #require(Reopen.script(id: id, folder: project.path, name: "n", options: ["--model", "opus"], remoteControl: true,
                                           configDir: work, home: home))
        let claudeLines = s.split(separator: "\n").filter { $0.contains("claude") && $0.contains("--resume") }
        #expect(claudeLines.count == 3)
        #expect(claudeLines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("CLAUDE_CONFIG_DIR='\(work)' 'claude' '--resume'") })
        // ~/.claude, and no folder known: no prefix
        let plain = try #require(Reopen.script(id: id, folder: project.path, name: nil, options: nil, remoteControl: false,
                                               configDir: home.appendingPathComponent(".claude").path, home: home))
        #expect(!plain.contains("CLAUDE_CONFIG_DIR"))
        #expect(!(try #require(Reopen.script(id: id, folder: project.path, name: nil, options: nil, remoteControl: false, home: home))).contains("CLAUDE_CONFIG_DIR"))
        // a quote in the folder stays quoted
        #expect(Reopen.configPrefix("/x/it's", home: home) == "CLAUDE_CONFIG_DIR='/x/it'\\''s' ")
    }

    @Test func theSettingsFolderIsKeptPerEntryAndAnOldRecordReadsAsTheDefault() throws {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id, folder: "/p", transcript: "/Users/u/.claude-work/projects/-p/\(id).jsonl"), open(id2, folder: "/q")],
                launches: [id2: RestoreRecord.Launch(name: nil, options: nil, configDir: "/Users/u/.claude-other")], now: t0)
        #expect(r.entries.first { $0.id == id }?.configDir == "/Users/u/.claude-work")      // from the transcript's place
        #expect(r.entries.first { $0.id == id2 }?.configDir == "/Users/u/.claude-other")    // from Claude Code's session file
        // kept when the next scan has no launch for it
        r.apply([open(id2, folder: "/q")], now: t0.addingTimeInterval(5))
        #expect(r.entries.first { $0.id == id2 }?.configDir == "/Users/u/.claude-other")
        // restore.json of 0.1.18: no configDir key
        let url = try dir("old").appendingPathComponent("restore.json")
        try Data("{\"entries\":[{\"id\":\"\(id)\",\"folder\":\"/p\",\"lastSeen\":1800000000}],\"lastScan\":1800000000}".utf8).write(to: url)
        let old = try #require(RestoreRecord.load(from: url))
        #expect(old.entries.count == 1 && old.entries[0].configDir == nil)
        #expect(Reopen.configDir(fromTranscript: "/tmp/x.jsonl") == nil)
    }

    @Test func liveSessionsKnowTheirSettingsFolder() throws {
        let work = try dir("claude-work")
        let sessions = work.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let pid = getpid()   // a process that runs: this test's own
        try Data("{\"pid\":\(pid),\"sessionId\":\"\(id)\",\"cwd\":\"/p\",\"kind\":\"interactive\",\"entrypoint\":\"cli\"}".utf8)
            .write(to: sessions.appendingPathComponent("\(pid).json"))
        #expect(LiveSession.read(settingsFolders: [work]).map(\.settingsFolder) == [work.path])
        var cache = LiveSessionCache()
        #expect(cache.read(settingsFolders: [work]).map(\.settingsFolder) == [work.path])
        #expect(cache.read(settingsFolders: [work]).map(\.settingsFolder) == [work.path])   // from the cache too
    }

    // MARK: 24.3 only Reopen starts sessions

    @Test func onlyTheReopenButtonStartsSessionsTheBodyOpensThePanel() {
        let body = "com.apple.UNNotificationDefaultActionIdentifier"
        #expect(NotificationClick.decide(category: "reopen", action: body, id: "a") == .openPanel)
        #expect(NotificationClick.decide(category: "ended", action: body, id: "a") == .openPanel)
        #expect(NotificationClick.decide(category: "reopen", action: "reopen", id: "a") == .reopen)
        #expect(NotificationClick.decide(category: "ended", action: "reopen", id: "e1") == .reopenEnded("e1"))
        #expect(NotificationClick.decide(category: "ended", action: "com.apple.UNNotificationDismissActionIdentifier", id: "a") == .nothing)
        #expect(NotificationClick.decide(category: "", action: body, id: "weekly-1") == .nothing)
    }

    // MARK: 24.4 the last scan stays current

    @Test func aSessionOpenUnchangedForEightDaysIsStillOffered() {
        // the app scans every 5 s; here every minute for eight days, the file written as the Controller writes it
        var r = RestoreRecord(lastScan: t0)
        var saved: RestoreRecord? = nil
        var savedKey: [String] = [], savedAt: Date? = nil
        var writes = 0
        var now = t0
        while now <= t0.addingTimeInterval(8 * 24 * 3600) {
            r.apply([open(id, folder: "/p")], now: now)
            if RestoreRecord.shouldSave(key: r.saveKey, savedKey: savedKey, lastScan: r.lastScan, savedScan: savedAt) {
                saved = r; savedKey = r.saveKey; savedAt = r.lastScan; writes += 1
            }
            now = now.addingTimeInterval(60)
        }
        // the Mac restarts a minute after the last scan
        let lost = saved?.lost(bootTime: now, now: now.addingTimeInterval(30)) ?? []
        #expect(lost.map(\.id) == [id])
        // at most one write per five minutes when nothing changed
        #expect(writes <= 8 * 24 * 12 + 1)
        // a change writes at once
        #expect(RestoreRecord.shouldSave(key: ["b"], savedKey: ["a"], lastScan: t0, savedScan: t0))
        #expect(!RestoreRecord.shouldSave(key: ["a"], savedKey: ["a"], lastScan: t0.addingTimeInterval(299), savedScan: t0))
    }

    // MARK: 24.5 the Reopen folders live under the data folder

    @Test func reopenFoldersAreMadeUnderTheDataFolderAndCleanedThere() throws {
        let data = try dir("data"), project = try dir("project")
        let base = Reopen.baseFolder(dataDir: data)
        #expect(base.path == data.appendingPathComponent("reopen").path)
        // a leftover of a cancelled prompt, older than ten minutes
        let old = base.appendingPathComponent(Reopen.folderPrefix + "old", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: t0.addingTimeInterval(-3600)], ofItemAtPath: old.path)
        let w = ReopenWrite.write([RestoreRecord.Entry(id: id, folder: project.path, transcript: nil, lastSeen: t0)], into: base, now: t0,
                                  remoteControl: { _ in false })
        let folder = try #require(w.folder)
        #expect(folder.deletingLastPathComponent().path == base.path && folder.lastPathComponent.hasPrefix(Reopen.folderPrefix))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        for (path, mode) in [(base.path, 0o700), (folder.path, 0o700), (w.files[0].path, 0o700)] {
            #expect((try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) == mode, "\(path)")
        }
        #expect(w.files[0].lastPathComponent == id + ".command")
    }

    // MARK: 24.6 no inline JSON in restore.json or a script

    @Test func inlineJSONOptionValuesAreNeverKept() throws {
        let argv = ["claude", "--settings", "{\"apiKeyHelper\":\"echo sk-secret\"}", "--model", "opus",
                    "--mcp-config", "/Users/u/mcp.json", "{\"mcpServers\":{\"x\":{\"env\":{\"TOKEN\":\"t\"}}}}",
                    "--mcp-config={\"mcpServers\":{}}", "--agents", "[{\"name\":\"a\"}]", "--unknown={\"k\":1}",
                    "--settings", "/Users/u/settings.local.json"]
        let k = try #require(LaunchOptions.keptNoting(fromArguments: argv))
        #expect(k.options == ["--model", "opus", "--mcp-config", "/Users/u/mcp.json", "--settings", "/Users/u/settings.local.json"])
        #expect(k.dropped == ["--settings", "--mcp-config", "--mcp-config", "--agents", "--unknown"])
        #expect(!k.options.joined().contains("{") && !k.options.joined().contains("secret"))
        // a restore.json of 0.1.18 holding one: dropped when read, never in a script
        let url = try dir("old").appendingPathComponent("restore.json")
        let json = "{\"entries\":[{\"id\":\"\(id)\",\"folder\":\"/tmp\",\"lastSeen\":1800000000,\"options\":[\"--settings\",\"{\\\"apiKeyHelper\\\":\\\"x\\\"}\",\"--effort\",\"high\"]}],\"lastScan\":1800000000}"
        try Data(json.utf8).write(to: url)
        let r = try #require(RestoreRecord.load(from: url))
        #expect(r.entries[0].options == ["--effort", "high"])
        let s = try #require(Reopen.script(id: id, folder: "/tmp", name: nil, options: ["--settings", "{\"a\":1}"], remoteControl: false))
        #expect(!s.contains("{\"a\"") && !s.contains("--settings"))
    }

    // MARK: 24.7 only the statusLine member of settings.json changes

    let spelled = "{\n  \"zeta\": 1.50,\n  \"model\" :  \"opus\",\n  \"big\": 1e3,\n  \"list\": [1, 2.0]\n}\n"

    func installRemove(viaScript: Bool) throws -> (installed: String, removed: String) {
        let home = try dir("home"), data = try dir("data").appendingPathComponent("Application Support/dev.tokenpanda.app")
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let file = claude.appendingPathComponent("settings.json")
        try Data(spelled.utf8).write(to: file)
        let set = HookSet(folders: [claude], dataDir: data, home: home)
        _ = try set.install()
        let installed = try String(contentsOf: file, encoding: .utf8)
        if viaScript {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [try #require(set.removeScriptPath).path]
            p.standardOutput = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
            #expect(p.terminationStatus == 0)
        } else {
            try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        }
        return (installed, try String(contentsOf: file, encoding: .utf8))
    }

    @Test func installAndRemoveChangeOnlyTheStatusLineMember() throws {
        let (installed, removed) = try installRemove(viaScript: false)
        // the other members byte for byte, key order and number spelling included, statusLine added after them
        #expect(installed.hasPrefix("{\n  \"zeta\": 1.50,\n  \"model\" :  \"opus\",\n  \"big\": 1e3,\n  \"list\": [1, 2.0],\n  \"statusLine\""))
        #expect(installed.hasSuffix("\n}\n"))
        let sl = try #require((try JSONSerialization.jsonObject(with: Data(installed.utf8)) as? [String: Any])?["statusLine"] as? [String: Any])
        #expect(sl["type"] as? String == "command" && sl["refreshInterval"] as? Int == 5)
        // Remove gives back the very bytes
        #expect(removed == spelled)
    }

    @Test func theZapKeepsTheFileAsItWas() throws {
        let (_, removed) = try installRemove(viaScript: true)
        #expect(removed == spelled)   // until 0.1.18 plutil left it on one line, keys reordered, 1.50 as 1.5
    }

    @Test func anExistingStatusLineIsChangedInPlace() throws {
        let text = "{\n  \"a\": 1.0,\n  \"statusLine\": {\n    \"padding\": 2,\n    \"type\": \"command\",\n    \"command\": \"echo hi\"\n  },\n  \"z\": true\n}\n"
        var settings = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var sl = try #require(settings["statusLine"] as? [String: Any])
        sl["command"] = "'/x/hook.sh'"; sl["refreshInterval"] = 5
        settings["statusLine"] = sl
        let out = String(decoding: try #require(SettingsText.edit(Data(text.utf8), to: settings)), as: UTF8.self)
        #expect(out == "{\n  \"a\": 1.0,\n  \"statusLine\": {\n    \"padding\": 2,\n    \"type\": \"command\",\n    \"command\": \"'/x/hook.sh'\",\n    \"refreshInterval\": 5\n  },\n  \"z\": true\n}\n")
        // removing it cuts the member and its comma only
        settings.removeValue(forKey: "statusLine")
        let cut = String(decoding: try #require(SettingsText.edit(Data(text.utf8), to: settings)), as: UTF8.self)
        #expect(cut == "{\n  \"a\": 1.0,\n  \"z\": true\n}\n")
        // a duplicate key is not edited: the caller writes the file whole
        #expect(SettingsText.edit(Data("{\"statusLine\":1,\"statusLine\":2}".utf8), to: ["statusLine": 3]) == nil)
    }

    // MARK: 24.8 CLAUDE_CONFIG_DIR is one path

    @Test func claudeConfigDirIsOnePathWithItsCommaAndTilde() throws {
        let home = try dir("home")
        let odd = home.appendingPathComponent("acct,two", isDirectory: true)
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        let found = ConfigFolders.find(home: home, environment: ["CLAUDE_CONFIG_DIR": odd.path])
        #expect(found.map(\.path).contains(odd.path))
        #expect(!found.map(\.lastPathComponent).contains("two"))
        #expect(ConfigFolders.environmentFolder(["CLAUDE_CONFIG_DIR": "~/acct,two"])?.path == NSHomeDirectory() + "/acct,two")
        #expect(ConfigFolders.environmentFolder(["CLAUDE_CONFIG_DIR": "  "]) == nil)
    }

    // MARK: 24.9 a deleted hook script is noticed

    @Test func aDeletedHookScriptMovesTheStamp() throws {
        let home = try dir("home"), data = try dir("data")
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let set = HookSet(folders: [claude], dataDir: data, home: home)
        _ = try set.install()
        let before = set.stamp()
        #expect(set.status().installed)
        try FileManager.default.removeItem(at: set.hooks[0].hookPath)
        #expect(set.stamp() != before)                       // the next feed tick reads the status again
        #expect(set.status().scriptMissing)
    }

    // MARK: 24.10 background work

    @Test func theHomeFolderIsLookedAtOnceAMinuteOrWhenForced() {
        var c = FolderClock()
        let v1 = c.due(now: t0); #expect(v1)
        let v2 = c.due(now: t0.addingTimeInterval(5)); #expect(!v2)
        let v3 = c.due(now: t0.addingTimeInterval(59)); #expect(!v3)
        let forced = c.due(now: t0.addingTimeInterval(59), force: true); #expect(forced)     // the panel opens
        let v4 = c.due(now: t0.addingTimeInterval(100)); #expect(!v4)
        let v5 = c.due(now: t0.addingTimeInterval(120)); #expect(v5)
        let v6 = c.due(now: t0.addingTimeInterval(-10)); #expect(v6)                  // the clock went back
    }

    @Test func theSessionsFolderIsMadeOnlyWhileAnEntryIsInstalled() throws {
        let home = try dir("home"), data = try dir("data")
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let set = HookSet(folders: [claude], dataDir: data, home: home)
        let sessions = set.hooks[0].sessionsDir
        #expect(!set.prepareSessionsFolder())
        #expect(!FileManager.default.fileExists(atPath: sessions.path))   // after Remove, a launch leaves it deleted
        _ = try set.install()
        try FileManager.default.removeItem(at: sessions)
        #expect(set.prepareSessionsFolder())
        #expect(FileManager.default.fileExists(atPath: sessions.path))
    }

    @Test func aClosedPanelSampleLooksUpNoProcessNames() async {
        let sampler = MacSampler()
        _ = await sampler.sample(full: false)
        let closed = await sampler.sample(full: false)
        #expect(closed.processes.isEmpty)
        #expect(closed.processError == nil)
        let open = await sampler.sample(full: true)
        #expect(!open.processes.isEmpty && open.processes.allSatisfy { !$0.name.isEmpty })
    }

    // MARK: 24.11 a settings folder made after launch

    @Test func aSettingsFolderMadeAfterLaunchBecomesATranscriptRoot() async throws {
        let home = try dir("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        let first = ConfigFolders.scan(home: home, environment: [:])
        let store = TranscriptStore(roots: ConfigFolders.transcriptRoots(usual: [], folders: first.transcripts))
        #expect(await store.setRoots(ConfigFolders.transcriptRoots(usual: [], folders: first.transcripts)) == false)
        // a second account is set up while the app runs
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude-work/projects"), withIntermediateDirectories: true)
        let later = ConfigFolders.scan(home: home, environment: [:])
        let roots = ConfigFolders.transcriptRoots(usual: [], folders: later.transcripts)
        #expect(roots.map(\.path).contains(home.appendingPathComponent(".claude-work/projects").path))
        #expect(await store.setRoots(roots))
        #expect(await store.roots.count == 2)
    }

    @Test func anOlderPassNeverReplacesANewerSummary() {
        var order = RefreshOrder()
        let v7 = order.accept(2); #expect(v7)
        let v8 = order.accept(1); #expect(!v8)   // the older pass's summary came last: dropped
        let v9 = order.accept(3); #expect(v9)
    }

    // MARK: 24.12 an older permission read is dropped in authorize

    @Test @MainActor func authorizeDropsItsReadWhenANewerOneLanded() async {
        let r = AccessTests.Replies()
        let reader = PermissionReader(state: .denied, read: { await r.read() }, ask: { await r.ask() })
        let auth = Task { await reader.authorize() }
        #expect(await r.settle { r.reads.count == 1 })
        let later = Task { await reader.refresh() }
        #expect(await r.settle { r.reads.count == 2 })
        r.reads[1].resume(returning: .allowed)     // the later read answers first: turned on in System Settings
        #expect(await later.value)
        r.reads[0].resume(returning: .denied)      // authorize's own read, sent before the switch
        await auth.value
        #expect(reader.state == .allowed && r.asks.isEmpty)
    }

    // MARK: 24.13 the restart notice once more at the first panel open

    @Test func theRestartNoticeIsSaidOnceMoreAtTheFirstPanelOpen() {
        var o = OfferRepeat()
        let v10 = o.panelOpened(pending: true); #expect(!v10)     // not posted yet: it comes on its own
        o.didPost()
        let v11 = o.panelOpened(pending: false); #expect(!v11)    // Reopen was clicked already
        let v12 = o.panelOpened(pending: true); #expect(v12)
        let v13 = o.panelOpened(pending: true); #expect(!v13)     // once
    }
}
