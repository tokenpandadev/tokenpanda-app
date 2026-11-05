// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import Feed
import os
import Text
import UI

/// The app Reopen opens the session files in: Terminal, iTerm or Ghostty, as picked in Settings. All three take the same
/// .command files through Launch Services, as a double click would, so no Apple events and no Automation permission.
/// Read 05.11.2026 with Terminal 2.15, iTerm 3.7.7 and Ghostty 1.4.0: each runs the file in a new window (Ghostty in a
/// new tab of its window), under login and a login shell. Ghostty asks "Allow Ghostty to execute ...?" for every file,
/// a check of its own since 1.2.0 that no setting turns off.
@MainActor
enum ReopenApp {
    static let terminalPath = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    /// Where Launch Services has the app, or nil when it is not installed. A copy in the Trash, or one Launch Services
    /// still lists after it was deleted, counts as not installed.
    static func location(_ app: TerminalApp) -> URL? {
        ReopenOpener.usable(NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId))
    }

    static func isInstalled(_ app: TerminalApp) -> Bool { app == .terminal || location(app) != nil }

    static var installed: Set<TerminalApp> { Set(TerminalApp.allCases.filter(isInstalled)) }

    /// The app to use now: the pick, or Terminal when the picked app is gone.
    static var current: TerminalApp {
        TerminalApp.resolve(setting: Settings.defaults.string(forKey: Settings.reopenApp), installed: isInstalled)
    }

    static let system = WorkspaceReopenSystem()

    /// Opens the files in the current app.
    static func open(_ files: [URL]) async {
        let app = current
        let url = location(app) ?? terminalPath
        await ReopenOpener.open(files, app: app, at: url, system: system)
    }

    /// The app whose window holds a process: the first of its parents that is Terminal, iTerm or Ghostty, by bundle id
    /// or by executable path. iTerm's shells hang under its session server, iTermServer, which is no app and has
    /// launchd as parent: its path names it.
    static func windowApp(of pid: Int32) -> TerminalApp? {
        TerminalApp.window(of: pid, parent: ProcessTable.parent(of:),
                           bundleId: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
                           executablePath: ProcessTable.executablePath(of:))
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

/// ReopenSystem on NSWorkspace: the real starts and opens. A failed start or open goes to the unified log, the reason private.
@MainActor
final class WorkspaceReopenSystem: ReopenSystem {
    nonisolated static let log = Logger(subsystem: Paths.bundleId, category: "restore")
    static let launchWait: Duration = .seconds(20)

    func isRunning(bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    func launch(appAt url: URL) async -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            let end = ContinuousClock.now + Self.launchWait
            while !app.isFinishedLaunching, ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(100)) }
            if !app.isFinishedLaunching { Self.log.error("reopen: the app did not finish launching in time") }
            return app.isFinishedLaunching
        } catch {
            Self.log.error("reopen: could not start the app: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    func open(_ files: [URL], withAppAt url: URL) {
        let n = files.count
        // the handler runs on a queue of NSWorkspace's: nonisolated and Sendable, it only logs
        NSWorkspace.shared.open(files, withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration()) { @Sendable _, error in
            if let error {
                Self.log.error("reopen: could not open \(n, privacy: .public) scripts: \(error.localizedDescription, privacy: .private)")
            }
        }
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
