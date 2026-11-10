// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import UI

/// A change of tab clears the problem report's "copied" line, by click and by Tab or Shift Tab (audit F-23).
struct PanelTabTests {
    @Test func tabKeyClearsCopied() {
        var p = PanelTab(tab: 2, reportCopied: true)
        p.step(back: false)
        #expect(p.tab == 0)
        #expect(p.reportCopied == nil)
    }

    @Test func shiftTabClearsCopiedAndGoesBack() {
        var p = PanelTab(tab: 0, reportCopied: false)
        p.step(back: true)
        #expect(p.tab == 2)
        #expect(p.reportCopied == nil)
    }

    @Test func clickOnATabClearsCopied() {
        var p = PanelTab(tab: 2, reportCopied: true)
        p.select(1)
        #expect(p.tab == 1)
        #expect(p.reportCopied == nil)
    }

    @Test func copiedStaysWhileTheTabStays() {
        var p = PanelTab(tab: 2)
        p.reportCopied = true
        #expect(p.tab == 2)
        #expect(p.reportCopied == true)
    }

    @Test func tabWrapsRoundAllThree() {
        var p = PanelTab()
        var seen: [Int] = []
        for _ in 0..<PanelTab.count { p.step(back: false); seen.append(p.tab) }
        #expect(seen == [1, 2, 0])
        p.select(-1)
        #expect(p.tab == 2)
        p.select(4)
        #expect(p.tab == 1)
    }
}
