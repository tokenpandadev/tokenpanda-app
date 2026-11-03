// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import MacStats

/// The process list's names.
struct MacSamplerTests {
    @Test func claudeCodeIsNamedByItsVersionsFolderNotItsVersion() {
        let path = "/Users/me/.local/share/claude/versions/2.1.317"
        #expect(MacSampler.displayName(procName: "2.1.317", executablePath: path, argv0: nil) == "Claude Code")
        // started as claude through the ~/.local/bin link
        #expect(MacSampler.displayName(procName: "2.1.317", executablePath: nil, argv0: "claude") == "Claude Code")
        #expect(MacSampler.displayName(procName: "2.1.317", executablePath: nil, argv0: "/Users/me/.local/bin/claude") == "Claude Code")
    }

    @Test func otherProcessesKeepTheirNameEvenWithAVersionLikeName() {
        // a version shaped name alone is not Claude Code
        #expect(MacSampler.displayName(procName: "2.1.317", executablePath: "/opt/tool/versions/2.1.317", argv0: "2.1.317") == "2.1.317")
        #expect(MacSampler.displayName(procName: "Safari", executablePath: "/Applications/Safari.app/Contents/MacOS/Safari", argv0: "Safari") == "Safari")
        #expect(MacSampler.displayName(procName: nil, executablePath: "/usr/bin/top", argv0: nil) == "top")
        #expect(MacSampler.displayName(procName: nil, executablePath: nil, argv0: nil) == nil)
    }

    @Test func argv0IsReadFromProcArgs() {
        var buf: [UInt8] = [2, 0, 0, 0]
        buf += Array("/Users/me/.local/share/claude/versions/2.1.317".utf8) + [0, 0, 0]
        buf += Array("claude".utf8) + [0] + Array("--resume".utf8) + [0]
        #expect(MacSampler.argv0(fromProcArgs: buf) == "claude")
        #expect(MacSampler.argv0(fromProcArgs: [1, 0, 0]) == nil)
    }

    @Test func thisProcessHasAName() {
        #expect(!MacSampler.name(of: getpid()).hasPrefix("pid "))
    }
}
