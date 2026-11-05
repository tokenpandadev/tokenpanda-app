// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Text

/// What opening the Reopen scripts needs from the system. The app passes NSWorkspace; the tests pass a recording fake,
/// so no test ever starts an app.
@MainActor public protocol ReopenSystem: AnyObject {
    func isRunning(bundleId: String) -> Bool
    /// Starts the app and returns once it has finished launching; false when it did not start or did not finish in time.
    func launch(appAt url: URL) async -> Bool
    /// Opens the files in the app, as a double click would. A failed open is logged by the system side.
    func open(_ files: [URL], withAppAt url: URL)
}

@MainActor public enum ReopenOpener {
    /// A Launch Services answer the app can use: nil when it is in a Trash folder or no longer on disk.
    public static func usable(_ url: URL?, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        guard let u = url?.standardizedFileURL else { return nil }
        if u.pathComponents.contains(".Trash") || u.pathComponents.contains(".Trashes") { return nil }
        return exists(u.path) ? u : nil
    }

    /// Opens the files in the app at `url`. iTerm, when not running, is started first and gets the files once it has
    /// finished launching; if it does not start, the files are still handed to Launch Services.
    public static func open(_ files: [URL], app: TerminalApp, at url: URL, system: ReopenSystem) async {
        if app.startsBeforeOpen, !system.isRunning(bundleId: app.bundleId) {
            _ = await system.launch(appAt: url)
        }
        system.open(files, withAppAt: url)
    }
}
