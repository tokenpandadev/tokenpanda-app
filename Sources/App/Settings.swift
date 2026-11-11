// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Feed
import Text
import UI

/// The UserDefaults keys of the spec, section 10. Nothing else is stored in preferences.
/// Open at login is not among them: its state is the system's, SMAppService.mainApp.status, read each time it is shown.
@MainActor
enum Settings {
    static let defaults = UserDefaults.standard
    static let macFiguresInBar = "macFiguresInBar"
    static let nudges = "nudges"
    static let listPriceEquivalent = "listPriceEquivalent"
    static let keepAwake = "keepAwake"
    static let keepAwakeWhileOpen = "keepAwakeWhileOpen"
    static let restoreSessions = "restoreSessions"
    static let reopenApp = TerminalApp.settingKey               // "reopenApp": terminal, iterm or ghostty
    static let hookPreviousCommand = "hookPreviousCommand"
    static let hookPreviousRefresh = "hookPreviousRefresh"   // the user's refreshInterval Install lowered, for Remove without the backup
    static let nudgedWeeklyWindow = NudgeRules.weeklyKey       // "nudgedWeeklyWindow", as every version wrote it
    static let nudgedFiveHourWindow = NudgeRules.fiveHourKey   // "nudgedFiveHourWindow"

    /// The fallback keys per settings folder: the old names for ~/.claude, a suffix for every other folder.
    static func previousCommandKey(_ id: String?) -> String { id.map { hookPreviousCommand + "." + $0 } ?? hookPreviousCommand }
    static func previousRefreshKey(_ id: String?) -> String { id.map { hookPreviousRefresh + "." + $0 } ?? hookPreviousRefresh }

    static func register() {
        defaults.register(defaults: [macFiguresInBar: false, nudges: true, listPriceEquivalent: true, keepAwake: false, keepAwakeWhileOpen: false, restoreSessions: false,
                                     reopenApp: TerminalApp.settingDefault])
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func set(_ key: String, _ value: Bool) { defaults.set(value, forKey: key) }
    static func toggle(_ key: String) { set(key, !bool(key)) }

    static func nudged(_ key: String) -> Double? {
        defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
    }
    /// nil takes the mark back (a post the centre refused).
    static func setNudged(_ key: String, _ epoch: Double?) {
        if let epoch { defaults.set(epoch, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

enum Paths {
    static let bundleId = "dev.tokenpanda.app"
    static var dataDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleId, isDirectory: true)
    }
    static var weeksFile: URL { dataDir.appendingPathComponent("weeks.json") }
    static var restoreFile: URL { dataDir.appendingPathComponent("restore.json") }
    /// The Reopen folders, under the data folder so the zap's trash takes a leftover with it (0.1.19, audit F-54).
    static var reopenDir: URL { Reopen.baseFolder(dataDir: dataDir) }
}
