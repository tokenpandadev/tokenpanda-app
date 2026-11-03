// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed

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
}
