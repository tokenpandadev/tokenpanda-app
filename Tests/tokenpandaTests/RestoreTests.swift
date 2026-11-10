// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed

/// Session restore: what counts as open at the last shutdown, and the Terminal file that resumes a session.
struct RestoreTests {
    let id = "3f1a9c2e-0000-4000-8000-000000000001"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func open(_ id: String, folder: String? = "/tmp") -> OpenSession {
        var s = Snapshot(sessionId: id, writtenAt: t0)
        s.projectDir = folder
        return OpenSession(snapshot: s)
    }

    @Test func offeredOnlyAfterABoot() {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id)], now: t0)
        #expect(r.lost(bootTime: t0.addingTimeInterval(-3600), now: t0.addingTimeInterval(10)).isEmpty)
        #expect(r.lost(bootTime: t0.addingTimeInterval(300), now: t0.addingTimeInterval(400)).map(\.id) == [id])
    }

    @Test func notOfferedAfterAWeek() {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id)], now: t0)
        #expect(r.lost(bootTime: t0.addingTimeInterval(60), now: t0.addingTimeInterval(8 * 24 * 3600)).isEmpty)
    }

    @Test func aClosedSessionDropsOutAfterTenMinutes() {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id)], now: t0)
        r.apply([], now: t0.addingTimeInterval(300))
        #expect(r.entries.count == 1)   // Terminal may close minutes before the app quits
        #expect(r.lost(bootTime: t0.addingTimeInterval(400), now: t0.addingTimeInterval(450)).map(\.id) == [id])
        r.apply([], now: t0.addingTimeInterval(601))
        #expect(r.entries.isEmpty)
    }

    @Test func aSessionWithoutAFolderIsNotKept() {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id, folder: nil)], now: t0)
        #expect(r.entries.isEmpty)
    }

    @Test func roundTripsOwnerOnly() throws {
        let url = TestTemp.root.appendingPathComponent("restore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id)], now: t0)
        r.save(to: url)
        #expect(RestoreRecord.load(from: url) == r)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func scriptValidatesAndQuotes() {
        #expect(Reopen.script(id: "not-a-uuid; rm -rf ~", folder: "/tmp", name: nil, options: nil, remoteControl: false) == nil)
        #expect(Reopen.script(id: id, folder: "/no/such/folder", name: nil, options: nil, remoteControl: false) == nil)
        let s = Reopen.script(id: id, folder: "/tmp", name: nil, options: nil, remoteControl: false)
        #expect(s == "#!/bin/zsh -l\nrm -f -- \"$0\"\nrmdir -- \"${0:h}\" 2>/dev/null\ncd '/tmp' || exit 1\n'claude' '--resume' '\(id)'\nexec \"${SHELL:-/bin/zsh}\" -l\n")
        #expect(Reopen.quote("it's") == "'it'\\''s'")
    }

    /// The scripts' first lines up to the cd, run by zsh: each file deletes itself, and the last one the folder (0.1.16).
    @Test func theLastScriptDeletesItsFolder() throws {
        let s = try #require(Reopen.script(id: id, folder: "/tmp", name: nil, options: nil, remoteControl: false))
        let head = s.split(separator: "\n", omittingEmptySubsequences: false).prefix(4).joined(separator: "\n") + "\n"
        let dir = TestTemp.root.appendingPathComponent(Reopen.folderPrefix + "test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.command"), b = dir.appendingPathComponent("b.command")
        for f in [a, b] { try Data(head.utf8).write(to: f) }
        func run(_ f: URL) throws -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-f", f.path]    // -f: no startup files, the login shell's own setup is not under test
            try p.run(); p.waitUntilExit()
            return p.terminationStatus
        }
        #expect(try run(a) == 0)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: dir.path))     // b is still there
        #expect(try run(b) == 0)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    /// At launch and before each Reopen: Reopen folders older than ten minutes go, nothing else in the temporary folder.
    @Test func leftoverReopenFoldersOlderThanTenMinutesAreDeleted() throws {
        let fm = FileManager.default
        let temp = TestTemp.root.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let now = Date()
        func folder(_ name: String, age: TimeInterval) throws -> URL {
            let u = temp.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: u, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: u.appendingPathComponent("s.command"))
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: u.path)
            return u
        }
        let old = try folder(Reopen.folderPrefix + "old", age: 11 * 60)
        let fresh = try folder(Reopen.folderPrefix + "fresh", age: 9 * 60)
        let other = try folder("someone-else", age: 3600)
        // a link with the name, to an old folder elsewhere: left alone, and what it points at too
        let target = try folder("target", age: 3600)
        let link = temp.appendingPathComponent(Reopen.folderPrefix + "link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let file = temp.appendingPathComponent(Reopen.folderPrefix + "file")
        try Data().write(to: file)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-3600)], ofItemAtPath: file.path)
        #expect(Reopen.removeLeftovers(in: temp, now: now) == [Reopen.folderPrefix + "old"])
        #expect(!fm.fileExists(atPath: old.path))
        for u in [fresh, other, target, file] { #expect(fm.fileExists(atPath: u.path)) }
        #expect((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(Reopen.leftoverAge == 600)
    }

    @Test func scriptStartsTheSessionAsItWasStarted() throws {
        let s = try #require(Reopen.script(id: id, folder: "/tmp", name: "Docs", options: ["--add-dir", "/a b", "--model", "opus"], remoteControl: true))
        let full = "'claude' '--resume' '\(id)' '--add-dir' '/a b' '--model' 'opus' '--name' 'Docs'"
        #expect(s.contains("t=$SECONDS\n" + full + " '--remote-control'\nif (( $? != 0 && SECONDS - t < 20 )); then\n"))
        #expect(s.contains("  t=$SECONDS\n  " + full + "\n  if (( $? != 0 && SECONDS - t < 20 )); then\n"))
        #expect(s.hasSuffix("    'claude' '--resume' '\(id)'\n  fi\nfi\nexec \"${SHELL:-/bin/zsh}\" -l\n"))
    }

    @Test func remoteControlFallsBackToAPlainResume() throws {
        let s = try #require(Reopen.script(id: id, folder: "/tmp", name: nil, options: nil, remoteControl: true))
        #expect(s.contains("'claude' '--resume' '\(id)' '--remote-control'\nif (( $? != 0 && SECONDS - t < 20 )); then\n  'claude' '--resume' '\(id)'\nfi\n"))
    }

    @Test func nameAndOptionsAreRecordedAndKept() {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id)], launches: [id: .init(name: "Backend", options: ["--add-dir", "/x"])], now: t0)
        #expect(r.entries.first?.name == "Backend")
        #expect(r.entries.first?.label == "Backend")
        // the session file is gone (the process ended first): the last name and options stay
        r.apply([open(id)], now: t0.addingTimeInterval(5))
        #expect(r.entries.first?.options == ["--add-dir", "/x"])
        #expect(r.entries.first?.name == "Backend")
        var u = RestoreRecord(lastScan: t0)
        u.apply([open(id, folder: "/Users/someone/project")], now: t0)
        #expect(u.entries.first?.label == "project")
    }

    @Test func anOldRecordStillLoads() throws {
        let json = #"{"entries":[{"id":"\#(id)","folder":"/tmp","lastSeen":1800000000}],"lastScan":1800000000}"#
        let url = TestTemp.root.appendingPathComponent("old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        let r = try #require(RestoreRecord.load(from: url))
        #expect(r.entries.first?.name == nil && r.entries.first?.options == nil)
    }

    @Test func remoteControlIsReadFromTheTranscript() throws {
        let url = TestTemp.root.appendingPathComponent("t-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"type\":\"user\"}\n".utf8).write(to: url)
        #expect(!Reopen.hadRemoteControl(transcript: url.path))
        try Data("{\"type\":\"user\"}\n{\"type\":\"bridge-session\",\"x\":1}\n".utf8).write(to: url)
        #expect(Reopen.hadRemoteControl(transcript: url.path))
        #expect(!Reopen.hadRemoteControl(transcript: nil))
    }
}
