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
        let argv = ["claude", "-n", "Pinned", "--add-dir", "/a", "/b", "--append-system-prompt", "# rules\nline", "--model", "opus",
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
}
