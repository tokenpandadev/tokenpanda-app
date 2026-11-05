// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import Feed
import Text

/// The app Reopen opens the session files in: Terminal, iTerm or Ghostty, as picked in Settings. All three take the same
/// .command files through Launch Services, as a double click would, so no Apple events and no Automation permission.
/// Read 05.11.2026 with Terminal 2.15, iTerm 3.7.7 and Ghostty 1.4.0: each runs the file in a new window (Ghostty in a
/// new tab of its window), under login and a login shell. Ghostty asks "Allow Ghostty to execute ...?" for every file,
/// a check of its own since 1.2.0 that no setting turns off.
@MainActor
enum ReopenApp {
    static let terminalPath = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    /// Where Launch Services has the app, or nil when it is not installed.
    static func location(_ app: TerminalApp) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)
    }

    static func isInstalled(_ app: TerminalApp) -> Bool { app == .terminal || location(app) != nil }

    static var installed: Set<TerminalApp> { Set(TerminalApp.allCases.filter(isInstalled)) }

    /// The app to use now: the pick, or Terminal when the picked app is gone.
    static var current: TerminalApp {
        TerminalApp.resolve(setting: Settings.defaults.string(forKey: Settings.reopenApp), installed: isInstalled)
    }

    /// Opens the files in the current app.
    static func open(_ files: [URL]) {
        let app = current
        let url = location(app) ?? terminalPath
        NSWorkspace.shared.open(files, withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// The app whose window holds a process: the first of its parents that is Terminal, iTerm or Ghostty. Nil when none
    /// is found within a few steps (iTerm's session server outlives a restart of iTerm, and then has launchd as parent).
    static func windowApp(of pid: Int32) -> TerminalApp? {
        var p: Int32? = pid
        for _ in 0..<8 {
            guard let q = p, q > 1 else { return nil }
            if let a = TerminalApp(bundleId: NSRunningApplication(processIdentifier: q)?.bundleIdentifier) { return a }
            p = ProcessTable.parent(of: q)
        }
        return nil
    }

    /// The pop-up's menu: the three apps, the current one checked, one that is not installed shown but off.
    static func menu(target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let now = current, have = installed
        for app in TerminalApp.allCases {
            let item = NSMenuItem(title: app.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = app.rawValue
            item.state = app == now ? .on : .off
            item.isEnabled = have.contains(app)
            if !item.isEnabled { item.toolTip = "Not installed" }
            menu.addItem(item)
        }
        return menu
    }
}

extension Controller {
    /// The "Open sessions in" pop-up: the menu opens over the row, on the current app, as a pop-up button's does.
    func showReopenAppMenu() {
        guard let r = lineView.rect(of: .pickReopenApp) else { return }
        let menu = ReopenApp.menu(target: self, action: #selector(pickReopenApp(_:)))
        let current = menu.items.first { $0.state == .on }
        menu.popUp(positioning: current, at: NSPoint(x: r.minX, y: r.maxY), in: lineView)
    }

    @objc func pickReopenApp(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String else { return }
        Settings.defaults.set(TerminalApp(setting: raw).rawValue, forKey: Settings.reopenApp)
        render()
    }
}
