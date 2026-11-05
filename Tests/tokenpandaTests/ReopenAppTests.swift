// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
import Text
@testable import UI

/// The app Reopen opens the sessions in: the stored pick, Terminal when the pick is gone, and the pop-up in Settings.
struct ReopenAppTests {
    @Test func theSettingReadsTheThreeAppsAndAnythingElseIsTerminal() {
        #expect(TerminalApp(setting: "terminal") == .terminal)
        #expect(TerminalApp(setting: "iterm") == .iterm)
        #expect(TerminalApp(setting: "ghostty") == .ghostty)
        #expect(TerminalApp(setting: nil) == .terminal)
        #expect(TerminalApp(setting: "Ghostty") == .terminal)
        #expect(TerminalApp(setting: "") == .terminal)
        #expect(TerminalApp.settingKey == "reopenApp")
        #expect(TerminalApp.settingDefault == "terminal")
    }

    @Test func eachAppIsFoundByItsBundleId() {
        #expect(TerminalApp.allCases.map(\.bundleId) == ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"])
        #expect(TerminalApp.allCases.map(\.title) == ["Terminal", "iTerm", "Ghostty"])
        #expect(TerminalApp(bundleId: "com.googlecode.iterm2") == .iterm)
        #expect(TerminalApp(bundleId: "com.mitchellh.ghostty") == .ghostty)
        #expect(TerminalApp(bundleId: "com.apple.Terminal") == .terminal)
        #expect(TerminalApp(bundleId: "dev.warp.Warp-Stable") == nil)
        #expect(TerminalApp(bundleId: nil) == nil)
    }

    @Test func theInstalledPickIsUsed() {
        let all: (TerminalApp) -> Bool = { _ in true }
        #expect(TerminalApp.resolve(setting: "iterm", installed: all) == .iterm)
        #expect(TerminalApp.resolve(setting: "ghostty", installed: all) == .ghostty)
        #expect(TerminalApp.resolve(setting: nil, installed: all) == .terminal)
    }

    @Test func aPickThatIsNotInstalledFallsBackToTerminal() {
        let onlyTerminal: (TerminalApp) -> Bool = { $0 == .terminal }
        #expect(TerminalApp.resolve(setting: "iterm", installed: onlyTerminal) == .terminal)
        #expect(TerminalApp.resolve(setting: "ghostty", installed: onlyTerminal) == .terminal)
        let noGhostty: (TerminalApp) -> Bool = { $0 != .ghostty }
        #expect(TerminalApp.resolve(setting: "ghostty", installed: noGhostty) == .terminal)
        #expect(TerminalApp.resolve(setting: "iterm", installed: noGhostty) == .iterm)
        // Terminal comes with macOS: it is never looked up
        #expect(TerminalApp.resolve(setting: "terminal", installed: { _ in false }) == .terminal)
    }

    func settings(restore: Bool, app: TerminalApp) -> SettingsTab {
        var s = SettingsTab(macInBar: false, nudges: true, listPrice: true, restoreSessions: restore)
        s.reopenApp = app
        return s
    }

    @Test func thePopUpShowsUnderTheReopenSwitchOnlyWhileItIsOn() throws {
        let off = Grammar.settingsTab(settings(restore: false, app: .terminal)).map(\.plain)
        #expect(!off.contains { $0.contains("Open sessions in") })
        let on = Grammar.settingsTab(settings(restore: true, app: .terminal)).map(\.plain)
        let at = try #require(on.firstIndex { $0.contains("Reopen sessions after a restart") })
        let row = try #require(on.firstIndex { $0.contains("Open sessions in") })
        #expect(row > at)
        #expect(on[row] == "     Open sessions in Terminal \u{25BE}")
        #expect(on[row].count <= Grammar.popCells)
        #expect(!on.contains { $0.contains("Ghostty asks") })
        #expect(Grammar.settingsTab(settings(restore: true, app: .iterm)).map(\.plain).contains("     Open sessions in iTerm \u{25BE}"))
    }

    @Test func ghosttySaysItAsksBeforeItRunsEachOne() throws {
        let lines = Grammar.settingsTab(settings(restore: true, app: .ghostty))
        let plain = lines.map(\.plain)
        let row = try #require(plain.firstIndex(of: "     Open sessions in Ghostty \u{25BE}"))
        #expect(plain[row + 1] == "         Ghostty asks before it runs each one")
        // said once, as the pop-up's help
        let pop = try #require(Controls.extract(lines).first { $0.kind == .popUp })
        #expect(pop.help == "Ghostty asks before it runs each one")
        #expect(lines[row + 1].hidden)
    }

    /// iTerm 3.7.7 asks "OK to run ...?" for each file until "Suppress this message permanently" is ticked (VM test 05.11).
    @Test func iTermSaysItAsksUntilSuppressIsTicked() throws {
        let lines = Grammar.settingsTab(settings(restore: true, app: .iterm))
        let plain = lines.map(\.plain)
        let row = try #require(plain.firstIndex(of: "     Open sessions in iTerm \u{25BE}"))
        #expect(plain[row + 1] == "         iTerm asks until you tick Suppress")
        let pop = try #require(Controls.extract(lines).first { $0.kind == .popUp })
        #expect(pop.help == "iTerm asks until you tick Suppress")
        #expect(lines[row + 1].hidden)
    }

    @Test func thePopUpIsOneControlWithItsValue() throws {
        let controls = Controls.extract(Grammar.settingsTab(settings(restore: true, app: .iterm)))
        let pops = controls.filter { $0.kind == .popUp }
        #expect(pops.count == 1)
        let pop = try #require(pops.first)
        #expect(pop.action == .pickReopenApp)
        #expect(pop.label == "Open sessions in")
        #expect(pop.value == "iTerm")
        #expect(pop.cells == "Open sessions in iTerm \u{25BE}".count)
    }

    @Test @MainActor func voiceOverHearsAPopUpButtonWithTheApp() throws {
        let v = LineView()
        var pressed: [Action] = []
        v.onAction = { pressed.append($0) }
        v.lines = Grammar.settingsTab(settings(restore: true, app: .ghostty))
        let kids = try #require(v.accessibilityChildren() as? [NSAccessibilityElement])
        let pop = try #require(kids.first { $0.accessibilityRole() == .popUpButton })
        #expect(pop.accessibilityLabel() == "Open sessions in")
        #expect(pop.accessibilityValue() as? String == "Ghostty")
        #expect(pop.accessibilityHelp() == "Ghostty asks before it runs each one")
        #expect(pop.accessibilityPerformPress())
        #expect(pressed == [.pickReopenApp])
        // the menu opens over the row
        let r = try #require(v.rect(of: .pickReopenApp))
        #expect(r.height == LineView.lineHeight)
    }

    @Test func theSettingsSampleShowsTheTerminalPick() throws {
        let input = try #require(Fixtures.all().first { $0.0 == "settings" }?.1)
        #expect(ScreenBuilder.screen(input).settings.reopenApp == .terminal)
        let folders = try #require(Fixtures.all().first { $0.0 == "settings-folders" }?.1)
        #expect(ScreenBuilder.screen(folders).settings.reopenApp == .ghostty)
    }

    @Test func theAppIsFoundByItsExecutablePath() {
        #expect(TerminalApp(executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal") == .terminal)
        #expect(TerminalApp(executablePath: "/Applications/iTerm.app/Contents/MacOS/iTerm2") == .iterm)
        #expect(TerminalApp(executablePath: "/Users/someone/Library/Application Support/iTerm2/iTermServer-3.6.6") == .iterm)
        #expect(TerminalApp(executablePath: "/Applications/Ghostty.app/Contents/MacOS/ghostty") == .ghostty)
        #expect(TerminalApp(executablePath: "/usr/bin/login") == nil)
        #expect(TerminalApp(executablePath: "/bin/zsh") == nil)
        #expect(TerminalApp(executablePath: "/Users/someone/Terminal.app/notes.txt") == nil)
    }

    /// iTerm's shells hang under login under iTermServer, whose parent is launchd and which is no app: found by its path.
    @Test func theEndedNoticeFindsITermThroughItsSessionServer() {
        let parents: [Int32: Int32] = [500: 400, 400: 300, 300: 1, 700: 600, 600: 1]
        let paths: [Int32: String] = [500: "/bin/zsh", 400: "/usr/bin/login",
                                      300: "/Users/someone/Library/Application Support/iTerm2/iTermServer-3.6.6",
                                      700: "/bin/zsh", 600: "/usr/sbin/sshd"]
        let apps: [Int32: String] = [:]
        func find(_ pid: Int32, bundles: [Int32: String] = apps) -> TerminalApp? {
            TerminalApp.window(of: pid, parent: { parents[$0] }, bundleId: { bundles[$0] }, executablePath: { paths[$0] })
        }
        #expect(find(500) == .iterm)
        #expect(find(700) == nil)                      // a shell under sshd: no window app
        #expect(find(500, bundles: [400: "com.mitchellh.ghostty"]) == .ghostty)   // the bundle id is asked first
        // a chain longer than the steps ends with nil
        #expect(TerminalApp.window(of: 50, steps: 3, parent: { $0 + 1 }, bundleId: { _ in nil },
                                   executablePath: { $0 == 60 ? "/Applications/Ghostty.app/Contents/MacOS/ghostty" : nil }) == nil)
    }

    @Test @MainActor func aLaunchServicesAnswerInTheTrashOrGoneIsNotInstalled() {
        let all: (String) -> Bool = { _ in true }
        #expect(ReopenOpener.usable(URL(fileURLWithPath: "/Applications/iTerm.app"), exists: all)?.path == "/Applications/iTerm.app")
        #expect(ReopenOpener.usable(URL(fileURLWithPath: "/Users/someone/.Trash/iTerm.app"), exists: all) == nil)
        #expect(ReopenOpener.usable(URL(fileURLWithPath: "/Volumes/Disk/.Trashes/501/Ghostty.app"), exists: all) == nil)
        #expect(ReopenOpener.usable(URL(fileURLWithPath: "/Applications/iTerm.app"), exists: { _ in false }) == nil)
        #expect(ReopenOpener.usable(nil, exists: all) == nil)
    }

    /// A recording fake for the system: what was started and opened, in order. No app is started by the tests.
    @MainActor final class FakeSystem: ReopenSystem {
        var running: Set<String>
        var launches: Bool
        var calls: [String] = []
        init(running: Set<String>, launches: Bool = true) { self.running = running; self.launches = launches }
        func isRunning(bundleId: String) -> Bool { running.contains(bundleId) }
        func launch(appAt url: URL) async -> Bool {
            calls.append("launch \(url.lastPathComponent)")
            if launches { running.insert("com.googlecode.iterm2") }
            return launches
        }
        func open(_ files: [URL], withAppAt url: URL) {
            calls.append("open \(files.map(\.lastPathComponent).joined(separator: ",")) in \(url.lastPathComponent)")
        }
    }

    @Test @MainActor func iTermIsStartedFirstWhenItIsNotRunning() async {
        let files = [URL(fileURLWithPath: "/tmp/x/a.command"), URL(fileURLWithPath: "/tmp/x/b.command")]
        let iterm = URL(fileURLWithPath: "/Applications/iTerm.app")
        let cold = FakeSystem(running: [])
        await ReopenOpener.open(files, app: .iterm, at: iterm, system: cold)
        #expect(cold.calls == ["launch iTerm.app", "open a.command,b.command in iTerm.app"])
        let warm = FakeSystem(running: ["com.googlecode.iterm2"])
        await ReopenOpener.open(files, app: .iterm, at: iterm, system: warm)
        #expect(warm.calls == ["open a.command,b.command in iTerm.app"])
        // a start that fails still hands the files to Launch Services
        let failed = FakeSystem(running: [], launches: false)
        await ReopenOpener.open(files, app: .iterm, at: iterm, system: failed)
        #expect(failed.calls == ["launch iTerm.app", "open a.command,b.command in iTerm.app"])
        // Terminal and Ghostty get the files at once
        for (app, path) in [(TerminalApp.terminal, "/System/Applications/Utilities/Terminal.app"), (.ghostty, "/Applications/Ghostty.app")] {
            let s = FakeSystem(running: [])
            await ReopenOpener.open(files, app: app, at: URL(fileURLWithPath: path), system: s)
            #expect(s.calls == ["open a.command,b.command in \(URL(fileURLWithPath: path).lastPathComponent)"])
        }
    }
}
