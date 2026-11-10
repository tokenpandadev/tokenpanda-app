// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The panel's tab and the "copied" line that belongs to the tab it was shown on. Every tab change, by a click on the
// tab row or by Tab and Shift Tab, goes through select, so the line never follows the user to another tab (audit F-23).

/// Which of the three tabs shows, and the problem report's copy result on that tab.
public struct PanelTab: Equatable, Sendable {
    public static let count = 3
    public private(set) var tab: Int
    /// true copied, false the clipboard refused, nil not clicked since the tab showed
    public var reportCopied: Bool?

    public init(tab: Int = 0, reportCopied: Bool? = nil) {
        self.tab = ((tab % Self.count) + Self.count) % Self.count
        self.reportCopied = reportCopied
    }

    /// A click on a tab, or any other change of tab: the copied line goes.
    public mutating func select(_ t: Int) {
        tab = ((t % Self.count) + Self.count) % Self.count
        reportCopied = nil
    }

    /// Tab goes to the next tab, Shift Tab to the one before, wrapping round.
    public mutating func step(back: Bool) {
        select(tab + (back ? Self.count - 1 : 1))
    }
}
