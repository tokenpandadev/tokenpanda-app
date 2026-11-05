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
}
