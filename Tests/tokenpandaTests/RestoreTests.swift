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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).json")
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
        #expect(s == "#!/bin/zsh -l\nrm -f -- \"$0\"\ncd '/tmp' || exit 1\n'claude' '--resume' '\(id)'\nexec \"${SHELL:-/bin/zsh}\" -l\n")
        #expect(Reopen.quote("it's") == "'it'\\''s'")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        let r = try #require(RestoreRecord.load(from: url))
        #expect(r.entries.first?.name == nil && r.entries.first?.options == nil)
    }

    @Test func remoteControlIsReadFromTheTranscript() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"type\":\"user\"}\n".utf8).write(to: url)
        #expect(!Reopen.hadRemoteControl(transcript: url.path))
        try Data("{\"type\":\"user\"}\n{\"type\":\"bridge-session\",\"x\":1}\n".utf8).write(to: url)
        #expect(Reopen.hadRemoteControl(transcript: url.path))
        #expect(!Reopen.hadRemoteControl(transcript: nil))
    }
}
