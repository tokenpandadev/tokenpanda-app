// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed

/// How a session was started: Claude Code's session files, the process arguments, which options a reopen keeps,
/// when a session counts as ended, and the names the notifications list.
struct LaunchTests {
    let id = "3f1a9c2e-0000-4000-8000-000000000001"

    @Test func keepsTheSetupAndLeavesOutTheRest() {
        let argv = ["claude", "-n", "Notes", "--add-dir", "/a", "/b", "--append-system-prompt", "# rules\nline", "--model", "opus",
                    "--session-id", id, "--debug-file", "/l.log", "--remote-control", "--effort=high", "fix the bug"]
        #expect(LaunchOptions.kept(fromArguments: argv) == ["--add-dir", "/a", "/b", "--append-system-prompt", "# rules\nline",
                                                            "--model", "opus", "--debug-file", "/l.log", "--effort=high"])
    }

    @Test func aResumeAndAStartPromptAreLeftOut() {
        #expect(LaunchOptions.kept(fromArguments: ["claude", "--resume", id, "--model", "sonnet"]) == ["--model", "sonnet"])
        #expect(LaunchOptions.kept(fromArguments: ["claude", "-r"]) == [])
        #expect(LaunchOptions.kept(fromArguments: ["claude", "-c", "hello there"]) == [])
        #expect(LaunchOptions.kept(fromArguments: ["claude", "--verbose", "--", "--model", "x"]) == ["--verbose"])
    }

    @Test func printAndCloudRunsAreNotReopenedFromTheirOptions() {
        #expect(LaunchOptions.kept(fromArguments: ["claude", "-p", "hi"]) == nil)
        #expect(LaunchOptions.kept(fromArguments: ["claude", "--no-session-persistence"]) == nil)
        #expect(LaunchOptions.kept(fromArguments: ["bash", "x.sh"]) == nil)
    }

    @Test func anUnknownOptionIsKeptAloneAndTheNpmInstallIsRead() {
        #expect(LaunchOptions.kept(fromArguments: ["claude", "--new-thing", "word", "--model", "o"]) == ["--new-thing", "--model", "o"])
        #expect(LaunchOptions.kept(fromArguments: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--model", "o"]) == ["--model", "o"])
    }

    @Test func readsProcArgs() {
        var buf: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { buf += $0 }
        buf += Array("/usr/local/bin/claude".utf8) + [0, 0, 0, 0]
        for a in ["claude", "-n", "A b"] { buf += Array(a.utf8) + [0] }
        buf += Array("HOME=/Users/someone".utf8) + [0]
        #expect(ProcessTable.parseProcArgs(buf) == ["claude", "-n", "A b"])
        #expect(ProcessTable.parseProcArgs([1, 0]) == nil)
    }

    @Test func readsTheArgumentsOfThisProcess() throws {
        let args = try #require(ProcessTable.arguments(of: getpid()))
        #expect(args.count == CommandLine.arguments.count)
        #expect(ProcessTable.parent(of: getpid()) == getppid())
    }

    @Test func parsesASessionFile() throws {
        let d = Data(#"{"pid":4006,"sessionId":"\#(id)","cwd":"/Users/someone/project","kind":"interactive","entrypoint":"cli","name":"Docs","nameSource":"user"}"#.utf8)
        let s = try #require(LiveSession.parse(d))
        #expect(s == LiveSession(pid: 4006, sessionId: id, folder: "/Users/someone/project", name: "Docs"))
        let auto = Data(#"{"pid":5,"sessionId":"\#(id)","name":"fix-bug","nameSource":"auto"}"#.utf8)
        #expect(LiveSession.parse(auto)?.name == nil)
        #expect(LiveSession.parse(Data(#"{"pid":5,"sessionId":"\#(id)","kind":"sdk"}"#.utf8)) == nil)
        #expect(LiveSession.parse(Data(#"{"pid":5,"sessionId":"x; rm"}"#.utf8)) == nil)
    }

    @Test func aSessionIsGoneWhenItsProcessIsAndItDoesNotRunElsewhere() {
        var w = SessionWatch()
        let a = LiveSession(pid: 10, sessionId: id, folder: "/f", name: "Website")
        #expect(w.apply([a]) { _ in 9 }.isEmpty)
        #expect(w.byPid[10]?.parent == 9)
        let gone = w.apply([]) { _ in nil }
        #expect(gone.map(\.name) == ["Website"])
        #expect(gone.first?.parent == 9)
        // resumed at once under a new process: not gone
        _ = w.apply([a]) { _ in 9 }
        #expect(w.apply([LiveSession(pid: 11, sessionId: id, folder: "/f", name: "Website")]) { _ in 9 }.isEmpty)
    }

    @Test func namesTheSessions() {
        #expect(SessionNames.list(["Backend"], named: ["Backend"]) == "Backend")
        #expect(SessionNames.list(["Backend", "Docs"], named: ["Backend", "Docs"]) == "Backend and Docs")
        #expect(SessionNames.list(["Backend", "project", "project"], named: ["Backend"]) == "Backend and project (2)")
        let eleven = ["Backend", "Release notes", "Mobile app", "Web app", "Billing", "Docs", "Website", "Infra", "Support", "Design", "Misc"]
        #expect(SessionNames.list(eleven, named: Set(eleven)) == "Backend, Release notes, Mobile app, Web app and 7 more")
    }

    /// procStart is `ps -o lstart` in UTC with the C locale; a day under 10 is padded with a space.
    @Test func procStartIsReadAsUTC() throws {
        let d = try #require(LiveSession.parseProcStart("Thu Nov  5 10:12:33 2026"))
        #expect(d == Date(timeIntervalSince1970: 1_793_873_553))
        #expect(LiveSession.parseProcStart("Sat Oct 31 23:59:59 2026") == Date(timeIntervalSince1970: 1_793_491_199))
        #expect(LiveSession.parseProcStart("Mon Nov 31 10:12:33 2026") == nil)
        #expect(LiveSession.parseProcStart("1793873553") == nil)
        #expect(LiveSession.parseProcStart("") == nil)
        let file = Data(#"{"pid":4006,"sessionId":"\#(id)","kind":"interactive","entrypoint":"cli","procStart":"Thu Nov  5 10:12:33 2026"}"#.utf8)
        #expect(LiveSession.parse(file)?.procStart == d)
    }

    /// A session file whose pid now belongs to another process (the pid was given out again) is not a running session.
    @Test func aReusedPidIsNotTheSession() {
        let started = Date(timeIntervalSince1970: 1_793_873_553)
        let s = LiveSession(pid: 4006, sessionId: id, folder: nil, name: nil, procStart: started)
        #expect(s.isRunning(startTime: { _ in started.addingTimeInterval(0.4) }, running: { _ in true }))
        #expect(!s.isRunning(startTime: { _ in started.addingTimeInterval(3600) }, running: { _ in true }))
        #expect(!s.isRunning(startTime: { _ in started }, running: { _ in false }))
        // an older file without procStart, or a process whose start cannot be read: as before, it runs
        let old = LiveSession(pid: 4006, sessionId: id, folder: nil, name: nil)
        #expect(old.isRunning(startTime: { _ in started.addingTimeInterval(3600) }, running: { _ in true }))
        #expect(s.isRunning(startTime: { _ in nil }, running: { _ in true }))
    }

    /// The real process table: this test process with its own start time is read, with a start an hour off it is not.
    @Test func theSessionFilesAreCheckedAgainstTheProcessStart() throws {
        let me = getpid()
        let start = try #require(ProcessTable.startTime(of: me))
        #expect(abs(start.timeIntervalSinceNow) < 24 * 3600)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        func lstart(_ d: Date) -> String {
            // ps pads the day to two places with a space
            let parts = f.string(from: d).split(separator: " ").map(String.init)
            return [parts[0], parts[1], parts[2].count == 1 ? " " + parts[2] : parts[2], parts[3], parts[4]].joined(separator: " ")
        }
        let folder = TestTemp.root.appendingPathComponent("tokenpanda-live-\(UUID().uuidString)", isDirectory: true)
        let dir = folder.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func put(_ procStart: String) throws {
            let d: [String: Any] = ["pid": Int(me), "sessionId": id, "cwd": "/tmp", "kind": "interactive", "entrypoint": "cli",
                                    "procStart": procStart]
            try JSONSerialization.data(withJSONObject: d).write(to: dir.appendingPathComponent("\(me).json"))
        }
        try put(lstart(start))
        #expect(LiveSession.read(settingsFolders: [folder]).map(\.pid) == [me])
        var cache = LiveSessionCache()
        #expect(cache.read(settingsFolders: [folder]).map(\.pid) == [me])
        try put(lstart(start.addingTimeInterval(-3600)))
        #expect(LiveSession.read(settingsFolders: [folder]).isEmpty)
        #expect(cache.read(settingsFolders: [folder]).isEmpty)
    }

    @Test func theExecutablePathOfThisProcessIsRead() throws {
        let path = try #require(ProcessTable.executablePath(of: getpid()))
        #expect(path.hasPrefix("/"))
        #expect(ProcessTable.executablePath(of: -5) == nil)
    }

    /// Reopen's temp folder follows TMPDIR, so a test in a throwaway home never cleans the user's real one (05.11.2026).
    @Test func reopenTempFolderFollowsTMPDIR() {
        let dir = TestTemp.root.appendingPathComponent("tp-tmpdir-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Reopen.tempFolder(environment: ["TMPDIR": dir.path + "/"]).path == dir.path)
        let system = FileManager.default.temporaryDirectory
        #expect(Reopen.tempFolder(environment: [:]) == system)
        #expect(Reopen.tempFolder(environment: ["TMPDIR": ""]) == system)
        #expect(Reopen.tempFolder(environment: ["TMPDIR": "relative/path"]) == system)
        #expect(Reopen.tempFolder(environment: ["TMPDIR": dir.path + "/missing"]) == system)
        // cleanup in that folder: an old Reopen folder goes, the user's real temp folder is not looked at
        let old = dir.appendingPathComponent(Reopen.folderPrefix + "old", isDirectory: true)
        try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let removed = Reopen.removeLeftovers(in: Reopen.tempFolder(environment: ["TMPDIR": dir.path]), now: Date().addingTimeInterval(3600))
        #expect(removed == [Reopen.folderPrefix + "old"])
    }
}
