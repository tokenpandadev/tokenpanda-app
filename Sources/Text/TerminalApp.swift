// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT

/// The app Reopen opens the session files in, picked in Settings. Each opens the same .command files through
/// Launch Services, as a double click would: no Apple events, no Automation permission, nothing typed.
public enum TerminalApp: String, CaseIterable, Sendable {
    case terminal, iterm, ghostty

    /// The name the panel, the menu and the notifications show.
    public var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm"
        case .ghostty: return "Ghostty"
        }
    }

    /// The bundle id Launch Services finds the app by.
    public var bundleId: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        }
    }

    /// The app of a running process's bundle id, if it is one of the three.
    public init?(bundleId: String?) {
        guard let b = bundleId, let a = Self.allCases.first(where: { $0.bundleId == b }) else { return nil }
        self = a
    }

    /// The app of a process's executable path: the binary inside the app's bundle, or iTerm's session server, which
    /// iTerm runs from outside its bundle (iTermServer-<version> under Application Support) and which holds the shells
    /// of its windows.
    public init?(executablePath path: String) {
        let parts = path.split(separator: "/").map(String.init)
        if let last = parts.last, last.hasPrefix("iTermServer") { self = .iterm; return }
        for (i, p) in parts.enumerated() where p.hasSuffix(".app") && i + 2 < parts.count
            && parts[i + 1] == "Contents" && parts[i + 2] == "MacOS" {
            switch p {
            case "Terminal.app": self = .terminal; return
            case "iTerm.app", "iTerm2.app": self = .iterm; return
            case "Ghostty.app": self = .ghostty; return
            default: continue
            }
        }
        return nil
    }

    /// The app whose window holds a process: the first of its parents, the process itself included, that is Terminal,
    /// iTerm or Ghostty, by bundle id or by executable path. Nil when none is found within `steps` or at launchd.
    public static func window(of pid: Int32, steps: Int = 8, parent: (Int32) -> Int32?, bundleId: (Int32) -> String?,
                              executablePath: (Int32) -> String?) -> TerminalApp? {
        var p: Int32? = pid
        for _ in 0..<steps {
            guard let q = p, q > 1 else { return nil }
            if let a = TerminalApp(bundleId: bundleId(q)) { return a }
            if let path = executablePath(q), let a = TerminalApp(executablePath: path) { return a }
            p = parent(q)
        }
        return nil
    }

    /// iTerm, when it is not running, is started on its own first and gets the files once it has finished launching,
    /// so the files do not race its launch. Terminal and Ghostty get them at once.
    public var startsBeforeOpen: Bool { self == .iterm }

    /// The stored setting: an unknown or missing value is Terminal.
    public init(setting: String?) {
        self = setting.flatMap(Self.init(rawValue:)) ?? .terminal
    }

    /// The app Reopen uses: the pick when it is installed, Terminal when it is not (Terminal comes with macOS).
    public static func resolve(setting: String?, installed: (TerminalApp) -> Bool) -> TerminalApp {
        let pick = TerminalApp(setting: setting)
        return pick == .terminal || installed(pick) ? pick : .terminal
    }

    /// The UserDefaults key of the pick and the default it starts at.
    public static let settingKey = "reopenApp"
    public static let settingDefault = TerminalApp.terminal.rawValue
}
