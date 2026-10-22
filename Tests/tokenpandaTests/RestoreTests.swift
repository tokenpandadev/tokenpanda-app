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

    @Test func aClosedSessionDropsOutAfterTwoMinutes() {
        var r = RestoreRecord(lastScan: t0)
        r.apply([open(id)], now: t0)
        r.apply([], now: t0.addingTimeInterval(60))
        #expect(r.entries.count == 1)   // Terminal may close a little before the app quits
        r.apply([], now: t0.addingTimeInterval(121))
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
        #expect(Reopen.script(id: "not-a-uuid; rm -rf ~", folder: "/tmp", remoteControl: false) == nil)
        #expect(Reopen.script(id: id, folder: "/no/such/folder", remoteControl: false) == nil)
        let s = Reopen.script(id: id, folder: "/tmp", remoteControl: false)
        #expect(s == "#!/bin/zsh -l\nrm -f -- \"$0\"\ncd '/tmp' || exit 1\nclaude --resume '\(id)'\n")
        #expect(Reopen.quote("it's") == "'it'\\''s'")
    }

    @Test func remoteControlFallsBackToAPlainResume() throws {
        let s = try #require(Reopen.script(id: id, folder: "/tmp", remoteControl: true))
        #expect(s.contains("claude --resume '\(id)' --remote-control || claude --resume '\(id)'\n"))
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
