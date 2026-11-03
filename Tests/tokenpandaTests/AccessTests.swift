// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
import Text
import Feed
@testable import UI

/// 0.1.9: VoiceOver roles and the keyboard, text that fits the panel, the key hint contrast, several settings folders,
/// the hook script check, the zap safe remove and the smaller fixes.
struct AccessTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func screen(_ name: String) throws -> Screen {
        let input = try #require(Fixtures.all().first { $0.0 == name }?.1)
        return ScreenBuilder.screen(input)
    }

    // MARK: controls

    @Test func settingsControlsAreCheckboxesAndButtonsWithTheirState() throws {
        let lines = Grammar.popover(try screen("settings"))
        let c = Controls.extract(lines)
        // the tab strip: three tabs, Settings selected
        let tabs = c.filter { $0.kind == .tab }
        #expect(tabs.map(\.label) == ["Claude", "Mac", "Settings"])
        #expect(tabs.map(\.checked) == [false, false, true])
        // every setting is one checkbox (the box and the label together), with its state and its help
        let boxes = c.filter { $0.kind == .checkbox }
        #expect(boxes.map(\.label) == ["Open at login", "Mac figures in the bar", "Nudge at 80% and before the 5h end", "List price equivalent",
                                       "Keep the Mac awake while Claude works", "also while a session waits for you", "Reopen sessions after a restart"])
        #expect(boxes.map(\.checked) == [true, false, true, true, true, false, true])
        #expect(boxes.first { $0.label == "List price equivalent" }?.help == "tokens at list prices, not the plan price")
        #expect(boxes.allSatisfy { $0.cells == 4 + $0.label.count })
        // the plain buttons: Install and Quit, in reading order after the boxes
        let buttons = c.filter { $0.kind == .button }
        #expect(buttons.map(\.label) == ["Remove the status line entry", "Quit, command Q"])
        #expect(buttons.map(\.action) == [.uninstall, .quit])
        // keys are stable: the same screen gives the same keys
        #expect(Controls.extract(lines).map(\.key) == c.map(\.key))
    }

    @Test func theWarningTabIsOneControlWithItsSpokenName() {
        let c = Controls.extract(Grammar.header(line: "Live from Claude Code", tab: 0, warn: true))
        #expect(c.map(\.label) == ["Claude", "Mac, warning", "Settings"])
        #expect(c[1].cells == 7)   // " Mac ", the dot, " "
    }

    @Test func claudeTabControlsIncludeSectionsAndFigures() throws {
        let c = Controls.extract(Grammar.popover(try screen("claude-overpace")))
        #expect(c.filter { $0.action.map { if case .section = $0 { return true } else { return false } } ?? false }.map(\.label)
                == ["Models", "Projects", "Sessions"])
        // a session figure and the model rows: focusable, their readout is the help
        let figures = c.filter { $0.kind == .figure }
        #expect(figures.count >= 6)
        #expect(figures.allSatisfy { $0.action == nil })
        // the key figures come first: the window sections, said whole, for the Down key too
        #expect(figures.first?.label.hasPrefix("Weekly, all models.") == true)
        #expect(figures.contains { $0.label.hasPrefix("5h window.") })
        #expect(figures.contains { $0.label.hasPrefix("Week of ") })
        let session = figures.first { $0.help != nil }
        #expect(session?.label == "workspace, Fable 5.1, context 405.6 thousand of 1 million, 41% used")
    }

    @Test func downReachesTheMacFigures() throws {
        let c = Controls.extract(Grammar.popover(try screen("mac")))
        let labels = c.filter { $0.kind == .figure }.map(\.label)
        for p in ["CPU ", "GPU ", "Memory ", "Battery "] { #expect(labels.contains { $0.hasPrefix(p) }, "\(p)") }
    }

    // MARK: the view: VoiceOver elements, press, keyboard focus

    @Test @MainActor func viewExposesRolesValuesAndPress() throws {
        let v = LineView()
        var pressed: [Action] = []
        v.onAction = { pressed.append($0) }
        v.lines = Grammar.popover(try screen("settings"))
        let kids = try #require(v.accessibilityChildren() as? [NSAccessibilityElement])
        // the tab strip is a tab group of three tabs
        let group = try #require(kids.first { $0.accessibilityRole() == .tabGroup })
        let tabs = try #require(group.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(tabs.map { $0.accessibilityRole() } == [.radioButton, .radioButton, .radioButton])
        #expect(tabs.map { $0.accessibilitySubrole() } == [.tabButtonSubrole, .tabButtonSubrole, .tabButtonSubrole])
        #expect(tabs.map { ($0.accessibilityValue() as? NSNumber)?.intValue } == [0, 0, 1])
        // a checkbox with its state, label and help
        let boxes = kids.filter { $0.accessibilityRole() == .checkBox }
        #expect(boxes.count == 7)
        let price = try #require(boxes.first { $0.accessibilityLabel() == "List price equivalent" })
        #expect((price.accessibilityValue() as? NSNumber)?.intValue == 1)
        #expect(price.accessibilityHelp() == "tokens at list prices, not the plan price")
        // pressing runs the same action as a click
        #expect(price.accessibilityPerformPress())
        #expect(tabs[0].accessibilityPerformPress())
        let quit = try #require(kids.first { $0.accessibilityLabel() == "Quit, command Q" })
        #expect(quit.accessibilityRole() == .button)
        #expect(pressed == [.toggle("listPriceEquivalent"), .tab(0)])
        // text lines stay text, in reading order after the controls above them
        #expect(kids.contains { $0.accessibilityRole() == .staticText && $0.accessibilityLabel() == "This app makes no network calls. Usage comes" })
    }

    @Test @MainActor func elementsSurviveARenderSoTheCursorStays() throws {
        let v = LineView()
        let s = try screen("settings")
        v.lines = Grammar.popover(s)
        let before = try #require((v.accessibilityChildren() as? [NSAccessibilityElement])?.first { $0.accessibilityLabel() == "Mac figures in the bar" })
        var t = s.settings; t.macInBar = true
        var s2 = s; s2.settings = t
        v.lines = Grammar.popover(s2)
        let after = try #require((v.accessibilityChildren() as? [NSAccessibilityElement])?.first { $0.accessibilityLabel() == "Mac figures in the bar" })
        #expect(before === after)
        #expect((after.accessibilityValue() as? NSNumber)?.intValue == 1)
    }

    @Test func theNudgeRowNamesThe5hEndOnlyWhenThePlanHasIt() throws {
        var input = try #require(Fixtures.all().first { $0.0 == "settings" }?.1)
        #expect(Grammar.popover(ScreenBuilder.screen(input)).contains { $0.plain.contains("Nudge at 80% and before the 5h end") })
        input.feed.limits?.windows.removeValue(forKey: "five_hour")   // Ultra: weekly only
        let lines = Grammar.popover(ScreenBuilder.screen(input))
        #expect(lines.contains { $0.plain.hasSuffix("Nudge at 80%") })
        #expect(!lines.contains { $0.plain.contains("5h end") })
    }

    @Test @MainActor func macFiguresKeepTheirElementsWhenTheNumbersMove() throws {
        // CPU, memory and battery change every 2 s; VoiceOver's cursor must stay on the same element
        let v = LineView()
        let s = try screen("mac")
        v.lines = Grammar.popover(s)
        func find(_ p: String) -> NSAccessibilityElement? {
            (v.accessibilityChildren() as? [NSAccessibilityElement])?.first { ($0.accessibilityLabel() ?? "").hasPrefix(p) }
        }
        let cpu = try #require(find("CPU ")), mem = try #require(find("Memory ")), bat = try #require(find("Battery "))
        var m = s.mac; m.cpu += 7; m.cpuLine = "user 31%  system 9%  10 cores"
        if var b = m.battery { b.percent -= 3; m.battery = b }
        if var mm = m.memory { mm.usedCells = min(mm.usedCells + 9, 190); mm.usedLine = "27.1 of 36 GB (75%)"; m.memory = mm }
        var s2 = s; s2.mac = m
        v.lines = Grammar.popover(s2)
        #expect(find("CPU ") === cpu)
        #expect(find("Memory ") === mem)
        #expect(find("Battery ") === bat)
        #expect(cpu.accessibilityLabel()?.contains("user 31%") == true)
    }

    @Test @MainActor func keyboardFocusMovesInReadingOrderAndPresses() throws {
        let v = LineView()
        var pressed: [Action] = []
        v.onAction = { pressed.append($0) }
        v.lines = Grammar.popover(try screen("settings"))
        #expect(v.focus == nil && !v.focusVisible)
        // Space with nothing focused is left to the caller
        #expect(!v.moveFocus(.press))
        // down: the first control, the Claude tab; right along the strip; left back; right at the end stays
        #expect(v.moveFocus(.down))
        #expect(v.focus == 0 && v.focusVisible && v.controls[0].label == "Claude")
        #expect(v.moveFocus(.right) && v.controls[v.focus!].label == "Mac")
        #expect(v.moveFocus(.right) && v.controls[v.focus!].label == "Settings")
        #expect(v.moveFocus(.right) && v.controls[v.focus!].label == "Settings")
        #expect(v.moveFocus(.left) && v.controls[v.focus!].label == "Mac")
        // down from the strip goes into the tab, row by row; Space presses the focused checkbox
        _ = v.moveFocus(.right)
        #expect(v.moveFocus(.down) && v.controls[v.focus!].label == "Open at login")
        #expect(v.moveFocus(.down) && v.controls[v.focus!].label == "Mac figures in the bar")
        #expect(v.moveFocus(.press))
        #expect(pressed == [.toggle("macFiguresInBar")])
        // the focus follows its control through a render
        let key = v.controls[v.focus!].key
        v.lines = Grammar.popover(try screen("settings"))
        #expect(v.controls[v.focus!].key == key)
        // up from the top stays on the first control; the key map
        for _ in 0..<20 { _ = v.moveFocus(.up) }
        #expect(v.focus == 0)
        #expect(LineView.focusKey(forKeyCode: 49) == .press && LineView.focusKey(forKeyCode: 36) == .press && LineView.focusKey(forKeyCode: 76) == .press)
        #expect(LineView.focusKey(forKeyCode: 125) == .down && LineView.focusKey(forKeyCode: 126) == .up)
        #expect(LineView.focusKey(forKeyCode: 123) == .left && LineView.focusKey(forKeyCode: 124) == .right)
        #expect(LineView.focusKey(forKeyCode: 0) == nil)
        // focus(on:) puts it on the selected tab after Tab
        v.focus(on: .tab(2), visible: true)
        #expect(v.controls[v.focus!].label == "Settings")
    }

    @Test @MainActor func aControlThatGoesKeepsThePlaceInTheOrder() throws {
        let v = LineView()
        v.lines = Grammar.popover(try screen("claude-install-failed"))
        let install = try #require(v.controls.firstIndex { $0.action == .install })
        #expect(v.controls[install].kind == .button)
        v.focus(on: .install, visible: true)
        // after Install the button is gone: the focus stays at that place, on a control that exists
        v.lines = Grammar.popover(try screen("claude-overpace"))
        #expect(v.focus != nil && v.focus! < v.controls.count)
    }

    @Test func aLongTooltipBreaksOverLinesInsteadOfBeingCut() {
        let tip = "USD 38.20 list price equivalent  1240 added  310 removed  effort high"
        let rows = LineView.tipLines(tip, width: 47)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count <= 47 })
        #expect(rows.joined(separator: "  ") == tip)
        #expect(LineView.tipLines("short", width: 47) == ["short"])
    }

    // MARK: text that fits

    @Test func noLineInAnyFixtureRunsPastThePanel() throws {
        for (name, input) in Fixtures.all() {
            for tab in 0..<3 {
                var i = input; i.tab = tab
                for line in Grammar.popover(ScreenBuilder.screen(i)) {
                    #expect(line.cells <= Grammar.popCells + 1, "\(name) tab \(tab): \(line.plain)")
                }
            }
        }
    }

    @Test func wrapKeepsEveryWordAndFitsTheWidth() {
        #expect(Format.wrap("awake  2 sessions working", 42) == ["awake  2 sessions working"])
        let w = Format.wrap("Could not install the entry: cannot read settings.json: settings.json is not a JSON object", 46)
        #expect(w.allSatisfy { $0.count <= 46 })
        #expect(w.joined(separator: " ") == "Could not install the entry: cannot read settings.json: settings.json is not a JSON object")
        #expect(Format.wrap(String(repeating: "x", count: 50), 20) == [String(repeating: "x", count: 20), String(repeating: "x", count: 20), String(repeating: "x", count: 10)])
    }

    @Test func installErrorShowsOnTheClaudeTabWithItsReason() throws {
        let lines = Grammar.popover(try screen("claude-install-failed")).map(\.plain)
        let at = try #require(lines.firstIndex { $0.contains("Install the status line hook") })
        let text = lines[(at + 1)...].prefix { !$0.isEmpty }.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        #expect(text == "Could not install the entry: cannot read settings.json: settings.json is not a JSON object")
    }

    @Test func settingsNotesFit() {
        let lines = Grammar.settingsTab(SettingsTab(macInBar: false, nudges: true, listPrice: true, nudgeNote: "Notifications are off in System Settings",
                                                    restoreSessions: true))
        let plain = lines.map(\.plain)
        // the note under Nudge, and under Reopen while that is on: one line each, whole
        #expect(plain.filter { $0 == "     Notifications are off in System Settings" }.count == 2)
        #expect(plain.contains("     one entry in ~/.claude/settings.json"))
        #expect(plain.contains("     a closed lid on battery still sleeps"))
    }

    @Test func versionLineInSettings() throws {
        let plain = Grammar.popover(try screen("settings")).map(\.plain)
        #expect(plain.contains(" tokenpanda 0.1.9"))
        var i = Fixtures.input(tab: 2); i.version = nil
        #expect(!Grammar.popover(ScreenBuilder.screen(i)).map(\.plain).contains { $0.contains("tokenpanda 0") })
    }

    // MARK: first call, week label, spoken weekday

    @Test func firstCallSaysWaitingForTheFirstReply() throws {
        let input = try #require(Fixtures.all().first { $0.0 == "claude-firstreply" }?.1)
        #expect(ScreenBuilder.limitsView(input) == .firstReply)
        let plain = Grammar.limits(.firstReply).map(\.plain)
        #expect(plain.filter { $0 == " waiting for the first reply" }.count == 2)
        #expect(!plain.contains { $0.contains("open Claude Code once") })
        // no session open at all: still "open Claude Code once"
        var none = input; none.feed.sessions = []
        #expect(ScreenBuilder.limitsView(none) == .noSession)
    }

    @Test func aSundayEveningResetLabelsTheNewWeekByItsMonday() throws {
        let input = try #require(Fixtures.all().first { $0.0 == "claude-week-rolled" }?.1)
        let weeks = ScreenBuilder.weekViews(input)
        #expect(weeks.map(\.date) == ["28 Sep", "5 Oct", "12 Oct", "19 Oct"])
        #expect(weeks.last?.note == "last seen 61%")
        #expect(Set(weeks.map(\.date)).count == weeks.count)
    }

    @Test func theItemSaysTheWeekdayInFull() {
        let label = ScreenBuilder.item(Fixtures.input(weekly: 61)).label
        #expect(label.contains("resets Sunday 18:00"))
        #expect(!label.contains("sun "))
    }

    // MARK: key hint contrast

    func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    func lum(_ c: RGBA) -> Double { 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }
    func over(_ top: RGBA, _ ground: RGBA) -> RGBA {
        RGBA(r: top.r * top.a + ground.r * (1 - top.a), g: top.g * top.a + ground.g * (1 - top.a), b: top.b * top.a + ground.b * (1 - top.a))
    }
    func ratio(_ a: RGBA, _ b: RGBA) -> Double { let x = lum(a), y = lum(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }

    @Test func keyHintsPassAAEvenOverAWhiteDesktop() {
        // the tint over the draft's dark stage, and over pure white: the brightest ground the glass can have, since the
        // material under the tint only darkens what is behind it
        let dark = over(Tokens.tint, Tokens.stage), bright = over(Tokens.tint, Tokens.white)
        #expect(ratio(Tokens.quiet, dark) >= 4.5)
        #expect(ratio(Tokens.quiet, bright) >= 4.5)
        // still below the default text, so the foot stays quieter than the figures
        #expect(lum(Tokens.quiet) < lum(Tokens.text))
    }

    // MARK: several settings folders, the script check, the zap safe remove

    @Test func configFoldersFindsTheUsualPlacesAndTheEnvironment() throws {
        let home = try tempDir()
        let fm = FileManager.default
        // nothing there yet: ~/.claude
        #expect(ConfigFolders.find(home: home, environment: [:]).map(\.lastPathComponent) == [".claude"])
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude-work"), withIntermediateDirectories: true)
        try "{}".write(to: home.appendingPathComponent(".claude-work/settings.json"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: home.appendingPathComponent(".claude-backup/projects"), withIntermediateDirectories: true)   // a copy with transcripts only
        try fm.createDirectory(at: home.appendingPathComponent(".claude-empty"), withIntermediateDirectories: true)   // neither settings nor projects
        try fm.createDirectory(at: home.appendingPathComponent("elsewhere/cc"), withIntermediateDirectories: true)
        let env = ["CLAUDE_CONFIG_DIR": home.appendingPathComponent("elsewhere/cc").path]
        let found = ConfigFolders.find(home: home, environment: env)
        // Install goes only where settings live: the backup copy with transcripts only is left out
        #expect(found.map { ConfigFolders.display($0, home: home) } == ["~/.claude", "~/elsewhere/cc", "~/.claude-work"])
        let ids = found.map { ConfigFolders.id(for: $0, home: home) }
        #expect(ids[0] == nil && ids[1]?.hasPrefix("elsewhere-cc-") == true && ids[2]?.hasPrefix("claude-work-") == true)
        // its transcripts are still counted
        #expect(ConfigFolders.transcriptFolders(home: home, environment: env).map { ConfigFolders.display($0, home: home) }
                == ["~/.claude", "~/elsewhere/cc", "~/.claude-backup", "~/.claude-work"])
        // only a CLAUDE_CONFIG_DIR folder: ~/.claude is not created for it
        let home2 = try tempDir()
        try fm.createDirectory(at: home2.appendingPathComponent("cfg"), withIntermediateDirectories: true)
        #expect(ConfigFolders.find(home: home2, environment: ["CLAUDE_CONFIG_DIR": home2.appendingPathComponent("cfg").path]).map(\.lastPathComponent) == ["cfg"])
    }

    @Test func installAndRemoveInEverySettingsFolder() throws {
        let home = try tempDir(), data = try tempDir()
        let fm = FileManager.default
        let a = home.appendingPathComponent(".claude"), b = home.appendingPathComponent(".claude-work")
        for d in [a, b] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        // each folder has its own status line before
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"echo A\"}}".write(to: a.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"echo B\"},\"model\":\"x\"}".write(to: b.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let set = HookSet(folders: [a, b], dataDir: data, home: home)
        #expect(set.targets == ["~/.claude", "~/.claude-work"])
        #expect(!set.status().installed && !set.status().anyInstalled)
        let done = try set.install()
        #expect(done.count == 2)
        let st = set.status()
        #expect(st.installed && st.anyInstalled && st.targets == ["~/.claude", "~/.claude-work"])
        // two scripts, each chaining its own folder's command, writing to the one sessions folder
        let scriptA = try String(contentsOf: data.appendingPathComponent("hook.sh"), encoding: .utf8)
        let scriptB = try String(contentsOf: set.hooks[1].hookPath, encoding: .utf8)
        #expect(scriptA.contains("PREV='echo A'") && scriptB.contains("PREV='echo B'"))
        #expect(scriptA.contains(data.appendingPathComponent("sessions").path) && scriptB.contains(data.appendingPathComponent("sessions").path))
        // Remove puts both back and the sessions folder goes with the last one
        try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        let oa = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: a.appendingPathComponent("settings.json"))) as? [String: Any])
        let ob = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: b.appendingPathComponent("settings.json"))) as? [String: Any])
        #expect((oa["statusLine"] as? [String: Any])?["command"] as? String == "echo A")
        #expect((ob["statusLine"] as? [String: Any])?["command"] as? String == "echo B")
        #expect(ob["model"] as? String == "x")
        #expect(!fm.fileExists(atPath: data.appendingPathComponent("sessions").path))
        #expect(!fm.fileExists(atPath: set.hooks[1].hookPath.path))
    }

    @Test func aNewFolderLeavesTheOthersInstalledAndInstallAddsIt() throws {
        let home = try tempDir(), data = try tempDir()
        let a = home.appendingPathComponent(".claude"), b = home.appendingPathComponent(".claude-work")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        _ = try HookSet(folders: [a], dataDir: data, home: home).install()
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let both = HookSet(folders: [a, b], dataDir: data, home: home)
        let st = both.status()
        #expect(!st.installed && st.anyInstalled)
        let s = ScreenBuilder.screen(Fixtures.input(hook: st, tab: 2)).settings
        #expect(s.hookSomeInstalled && !s.hookInstalled)
        let plain = Grammar.settingsTab(s).map(\.plain)
        #expect(plain.contains(" Install the status line entry") && plain.contains(" Remove the status line entry"))
        #expect(try both.install().count == 1)
        #expect(both.status().installed)
    }

    @Test func removeDeletesTheSettingsFileInstallCreated() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("cfg/settings.json")
        let hook = Hook(settingsURL: settings, dataDir: dir)
        _ = try hook.install()
        #expect(FileManager.default.fileExists(atPath: settings.path))
        try hook.uninstall(previousCommand: nil)
        #expect(!FileManager.default.fileExists(atPath: settings.path))
        // a file that existed before stays, even when it ends up empty
        try "{}".write(to: settings, atomically: true, encoding: .utf8)
        _ = try hook.install()
        try hook.uninstall(previousCommand: nil)
        #expect(try String(contentsOf: settings, encoding: .utf8).contains("{"))
    }

    @Test func afterAZapTheStatusSaysTheScriptIsGoneAndInstallPutsItBack() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"echo mine\"}}".write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir)
        _ = try hook.install()
        // brew zap without the remove: the data folder with hook.sh and the backup is gone, settings.json still points at it
        try FileManager.default.removeItem(at: hook.hookPath)
        try FileManager.default.removeItem(at: hook.backupPath)
        let st = hook.status()
        #expect(!st.installed && st.scriptMissing)
        let lines = Grammar.settingsTab(ScreenBuilder.screen(Fixtures.input(hook: st, tab: 2)).settings).map(\.plain)
        #expect(lines.contains("     the hook script is gone, Install puts it"))
        // Install again: the script is back, chaining the command the app kept in its preferences
        let again = try hook.install(previousFallback: "echo mine")
        #expect(again.installed && again.previousCommand == "echo mine")
        #expect(try String(contentsOf: hook.hookPath, encoding: .utf8).contains("PREV='echo mine'"))
        #expect(hook.status().installed)
    }

    @Test func theCaskZapRunsTheAppsRemoveAndNotOnUpgrade() throws {
        let here = URL(fileURLWithPath: #filePath)
        let cask = try String(contentsOf: here.deletingLastPathComponent().appendingPathComponent("../../Casks/tokenpanda.rb").standardizedFileURL, encoding: .utf8)
        let zap = try #require(cask.range(of: "zap ")).lowerBound
        let flag = try #require(cask.range(of: "dev.tokenpanda.app/remove.sh")).lowerBound
        #expect(flag > zap)   // inside the zap stanza
        let uninstall = try #require(cask.range(of: "uninstall quit:"))
        #expect(!cask[uninstall.lowerBound..<zap].contains("remove.sh"))
        // the zap runs the script with /bin/sh, not the app binary, which Homebrew before 7.0.10 has deleted by then
        #expect(!cask[zap...].contains("MacOS/tokenpanda"))
    }

    // MARK: the .tmp leak

    @Test func scanDeletesTmpFilesACancelledHookLeft() async throws {
        let dir = try tempDir()
        let sessions = dir.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let now = Date()
        let old = sessions.appendingPathComponent("abc.json.tmp"), fresh = sessions.appendingPathComponent("def.json.tmp")
        for u in [old, fresh] { try "{".write(to: u, atomically: false, encoding: .utf8) }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: old.path)
        _ = await FeedReader(dataDir: dir).scan(now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))   // a hook run may be writing it right now
    }

    // MARK: 0.1.9 check: id collision, remove without the app

    @Test func dashAndUnderscoreFoldersNeverShareAScriptOrBackup() throws {
        let home = try tempDir(), data = try tempDir()
        let fm = FileManager.default
        let dash = home.appendingPathComponent(".claude-work"), under = home.appendingPathComponent(".claude_work")
        for d in [dash, under] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try "{\"model\":\"x\"}".write(to: dash.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"under.sh\"}}".write(to: under.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let set = HookSet(folders: [dash, under], dataDir: data, home: home)
        #expect(Set(set.hooks.map(\.hookPath)).count == 2 && Set(set.hooks.map(\.backupPath)).count == 2)
        // the id is stable: the same folder gives the same name every time
        #expect(ConfigFolders.id(for: dash, home: home) == ConfigFolders.id(for: dash, home: home))
        _ = try set.install()
        let sDash = try String(contentsOf: set.hooks[0].hookPath, encoding: .utf8), sUnder = try String(contentsOf: set.hooks[1].hookPath, encoding: .utf8)
        #expect(sDash.contains("PREV=''") && sUnder.contains("PREV='under.sh'"))
        try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        let od = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: dash.appendingPathComponent("settings.json"))) as? [String: Any])
        let ou = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: under.appendingPathComponent("settings.json"))) as? [String: Any])
        #expect(od["statusLine"] == nil && od["model"] as? String == "x")
        #expect((ou["statusLine"] as? [String: Any])?["command"] as? String == "under.sh")
    }

    func runSh(_ path: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [path.path]
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    @Test func removeScriptPutsEverythingBackWithoutTheApp() throws {
        let home = try tempDir(), data = try tempDir().appendingPathComponent("Application Support/dev.tokenpanda.app")
        let fm = FileManager.default
        let a = home.appendingPathComponent(".claude"), b = home.appendingPathComponent(".claude_work"), c = home.appendingPathComponent("it's here")
        for d in [a, b, c] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"echo A\",\"padding\":2,\"refreshInterval\":60},\"model\":\"x\"}".write(to: a.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "{\"other\":1}".write(to: b.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        // c has no settings.json: Install creates it, the script deletes it again
        let set = HookSet(folders: [a, b, c], dataDir: data, home: home)
        _ = try set.install()
        let script = try #require(set.removeScriptPath)
        #expect(fm.isExecutableFile(atPath: script.path))
        // zap on an old Homebrew: the app is gone, the data folder is still there, the script runs
        #expect(try runSh(script) == 0)
        let oa = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: a.appendingPathComponent("settings.json"))) as? [String: Any])
        let sl = try #require(oa["statusLine"] as? [String: Any])
        #expect(sl["command"] as? String == "echo A" && sl["padding"] as? Int == 2 && sl["refreshInterval"] as? Int == 60 && oa["model"] as? String == "x")
        let ob = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: b.appendingPathComponent("settings.json"))) as? [String: Any])
        #expect(ob["statusLine"] == nil && ob["other"] as? Int == 1)
        #expect(!fm.fileExists(atPath: c.appendingPathComponent("settings.json").path))
        // a statusLine the user changed since is left alone; running it twice changes nothing
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"mine.sh\"}}".write(to: b.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        #expect(try runSh(script) == 0)
        #expect(try String(contentsOf: b.appendingPathComponent("settings.json"), encoding: .utf8).contains("mine.sh"))
        // after Remove in the app, nothing is ours: the script goes
        _ = try set.install()
        try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        #expect(!fm.fileExists(atPath: script.path))
    }

    // MARK: 0.1.9 check: what VoiceOver reads instead of glyph names

    @MainActor func spokenTree(_ name: String, tab: Int? = nil) throws -> [(NSAccessibility.Role?, String, String?)] {
        let input = try #require(Fixtures.all().first { $0.0 == name }?.1)
        var i = input; if let tab { i.tab = tab }
        let v = LineView()
        v.lines = Grammar.popover(ScreenBuilder.screen(i))
        func walk(_ es: [NSAccessibilityElement]) -> [(NSAccessibility.Role?, String, String?)] {
            es.flatMap { e in [(e.accessibilityRole(), e.accessibilityLabel() ?? "", e.accessibilityHelp())] + walk((e.accessibilityChildren() as? [NSAccessibilityElement]) ?? []) }
        }
        return walk((v.accessibilityChildren() as? [NSAccessibilityElement]) ?? [])
    }

    static let glyphs: [Character] = ["\u{2588}", "\u{2589}", "\u{258A}", "\u{258B}", "\u{258C}", "\u{258D}", "\u{258E}", "\u{258F}", "\u{2590}",
                                      "\u{2594}", "\u{26C1}", "\u{26F6}", "\u{26DD}", "\u{2595}", "\u{2502}"]

    @Test @MainActor func noElementIsReadAsGlyphNames() throws {
        for (name, input) in Fixtures.all() {
            for tab in 0..<3 {
                var i = input; i.tab = tab
                let v = LineView()
                v.lines = Grammar.popover(ScreenBuilder.screen(i))
                func walk(_ es: [NSAccessibilityElement]) -> [String] {
                    es.flatMap { [$0.accessibilityLabel() ?? ""] + walk(($0.accessibilityChildren() as? [NSAccessibilityElement]) ?? []) }
                }
                for label in walk((v.accessibilityChildren() as? [NSAccessibilityElement]) ?? []) {
                    #expect(!label.contains { Self.glyphs.contains($0) }, "\(name) tab \(tab): \(label)")
                }
            }
        }
    }

    @Test @MainActor func sectionsWeeksAndTheGridSayTheStyleGuidesLabels() throws {
        let claude = try spokenTree("claude-overpace").map(\.1)
        #expect(claude.contains("Weekly, all models. 61% used. Resets Sunday 18:00, in 3 days 3 hours. Over pace, limit Sunday 01:20 at this rate. 0.5% an hour left."))
        #expect(claude.contains("Week of 28 September, 100%, hit the limit Thursday 16:10"))
        #expect(claude.contains("Week of 12 October, 61%, so far"))
        #expect(claude.contains("Fable 5.1, 1.02 billion tokens, 49% of 7 days"))
        #expect(claude.contains("list price equivalent, 1,140 US dollars"))
        // the section's other lines are not read a second time
        #expect(!claude.contains { $0.hasPrefix("Resets Sun") || $0 == "0.5% an hour left" })
        let mac = try spokenTree("mac")
        let grid = try #require(mac.first { $0.0 == .image })
        #expect(grid.1 == "Memory 25.5 of 36 gigabytes, 71%, free 10.5 gigabytes, swap 0.9 gigabytes, pressure normal")
        #expect(mac.filter { $0.0 == .image }.count == 1)
        #expect(mac.contains { $0.1.hasPrefix("CPU ") && $0.1.contains("% , ") == false && $0.1.contains("cores") })
        #expect(mac.contains { $0.1.hasPrefix("Battery ") && $0.1.contains("cycles") })
        // a process row says its figure once, and no help repeats it
        let row = try #require(mac.first { $0.1.contains("% CPU") })
        #expect(row.2 == nil)
    }

    @Test @MainActor func checkboxHelpIsSaidOnceAndTheRuleIsSilent() throws {
        let t = try spokenTree("settings")
        let price = try #require(t.first { $0.1 == "List price equivalent" })
        #expect(price.2 == "tokens at list prices, not the plan price")
        #expect(!t.contains { $0.0 == .staticText && $0.1 == "tokens at list prices, not the plan price" })
        #expect(!t.contains { $0.1.contains("\u{2594}") })
    }

    @Test @MainActor func thePointerLandsOnTheElementUnderIt() throws {
        let v = LineView()
        v.lines = Grammar.popover(try screen("settings"))
        // the Settings tab: line 2 of the header, its cells from the controls
        let tab = try #require(v.controls.first { $0.label == "Settings" })
        let r = v.controlRect(tab)
        let e = try #require(v.element(atViewPoint: NSPoint(x: r.midX, y: r.midY)))
        #expect(e.accessibilityLabel() == "Settings" && e.accessibilityRole() == .radioButton)
        let box = try #require(v.controls.first { $0.label == "List price equivalent" })
        let rb = v.controlRect(box)
        #expect(v.element(atViewPoint: NSPoint(x: rb.midX, y: rb.midY))?.accessibilityRole() == .checkBox)
    }

    @Test @MainActor func wrappedTextIsReadOnceAndWhole() throws {
        let t = try spokenTree("claude-install-failed").map(\.1)
        #expect(t.contains("Could not install the entry: cannot read settings.json: settings.json is not a JSON object"))
        #expect(!t.contains { $0.hasPrefix("settings.json: settings.json") || $0 == "object" })
    }

    @Test @MainActor func aSessionsNameAndModelAreSaidOnce() throws {
        let t = try spokenTree("claude-overpace").map(\.1)
        #expect(t.contains("workspace, Fable 5.1, context 405.6 thousand of 1 million, 41% used"))
        #expect(!t.contains("workspace  Fable 5.1"))
        // a session that has not replied keeps its name line: it has no figure line to carry it
        #expect(try spokenTree("claude-firstreply").map(\.1).contains("workspace  Fable 5.1"))
    }

    @Test func theRemoveScriptIsWrittenForAnEntryAnOlderVersionInstalled() throws {
        let home = try tempDir(), data = try tempDir()
        let a = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        let set = HookSet(folders: [a], dataDir: data, home: home)
        _ = try set.install()
        // as 0.1.8 left it: the entry and hook.sh, no remove.sh
        let script = try #require(set.removeScriptPath)
        try FileManager.default.removeItem(at: script)
        set.writeRemoveScript()   // what launch does
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        // with no entry of ours, launch writes nothing
        try set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        set.writeRemoveScript()
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }
}
