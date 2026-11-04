// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
import Text
import Feed
import Pace
@testable import UI

/// Snapshots of the menu bar item: the real ItemImage, a template image, tinted on a dark and a light menu bar strip
/// as the OS draws a template item (ink by source-in), at half strength when stale. The strip colours are the chrome
/// tokens. The nudge banner is drawn by the OS (UNUserNotificationCenter) and has no view to render here; its texts are
/// checked in ItemSnapshotTests.nudgeTextsAreTheRulesOwn and drawn in Storybook.
@MainActor
struct ItemSnapshotTests {
    enum State: String, CaseIterable, Sendable {
        case normal = "item-normal"
        case overPace = "item-over-pace"
        case stale = "item-stale"
        case weeklyLimit = "item-weekly-limit"
        case fiveHourLimit = "item-five-limit"
        case macWarning = "item-mac-warning"
        case macFigure = "item-mac-figure"
        case noFigures = "item-no-figures"
    }

    static func input(_ name: String) throws -> LiveInput {
        try #require(Fixtures.all().first { $0.0 == name }?.1)
    }

    static func state(_ s: State) throws -> ItemState {
        switch s {
        case .normal: return ScreenBuilder.item(try input("claude-ahead"))
        case .overPace: return ScreenBuilder.item(try input("claude-overpace"))
        case .stale: return ScreenBuilder.item(try input("claude-stale"))
        case .weeklyLimit: return ScreenBuilder.item(Fixtures.input(weekly: 100))
        case .fiveHourLimit:
            let feed = FeedState(limits: Fixtures.limits(weekly: 61, five: 100), sessions: Fixtures.openSessions, lastWriteAt: Fixtures.now.addingTimeInterval(-2))
            return ScreenBuilder.item(Fixtures.input(feedState: feed))
        case .macWarning: return ScreenBuilder.item(try input("mac-warning"))
        case .macFigure:
            var i = try input("claude-overpace")
            i.macInBar = true
            return ScreenBuilder.item(i)
        case .noFigures: return ScreenBuilder.item(try input("claude-nohook"))
        }
    }

    /// A strip of menu bar with the item on it, 12 pt in from the left as the debug snapshot flag draws it.
    final class Strip: NSView {
        let image: NSImage, stale: Bool, light: Bool
        init(image: NSImage, stale: Bool, light: Bool) { self.image = image; self.stale = stale; self.light = light; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            (light ? Tokens.stageLight : Tokens.stage).ns.setFill(); bounds.fill()
            (light ? DesignTokens.Chrome.menubarLightGround : DesignTokens.Chrome.menubarDarkGround).ns.setFill()
            bounds.fill(using: .sourceOver)
            let ink = light ? DesignTokens.Chrome.menubarLightInk : DesignTokens.Chrome.menubarDarkInk
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                ink.with(alpha: 1).ns.set()
                self.image.draw(in: rect)
                rect.fill(using: .sourceIn)
                return true
            }
            tinted.draw(in: NSRect(x: 12, y: 1, width: image.size.width, height: image.size.height), from: .zero, operation: .sourceOver,
                        fraction: stale ? DesignTokens.Chrome.itemStaleOpacity : ink.a, respectFlipped: true, hints: nil)
        }
    }

    nonisolated static let cases: [(State, Bool)] = State.allCases.flatMap { [($0, false), ($0, true)] }

    @Test(arguments: cases)
    func itemMatchesItsReference(_ s: State, light: Bool) throws {
        let st = try Self.state(s)
        let image = ItemImage.make(st)
        #expect(image.isTemplate)
        #expect(Double(image.size.height) == DesignTokens.Size.itemHeight)
        let strip = Strip(image: image, stale: st.stale, light: light)
        strip.frame = NSRect(x: 0, y: 0, width: image.size.width + 24, height: 24)
        let rep = try #require(strip.bitmapImageRepForCachingDisplay(in: strip.bounds))
        strip.cacheDisplay(in: strip.bounds, to: rep)
        try PanelSnapshotTests.compare(rep, "\(s.rawValue)-\(light ? "light" : "dark")")
    }

    /// The states are the ones the style guide names: semibold over pace, half strength stale, the eyes at a limit.
    @Test func statesAreTheOnesShown() throws {
        #expect(try Self.state(.normal).over == false)
        #expect(try Self.state(.overPace).over == true)
        #expect(try Self.state(.stale).stale == true)
        #expect(try Self.state(.weeklyLimit).eyes == .weeklyLimit)
        #expect(try Self.state(.fiveHourLimit).eyes == .fiveHourLimit)
        #expect(try Self.state(.macWarning).warn == true)
        #expect(try Self.state(.macFigure).macText == " CPU 9%")
        #expect(try Self.state(.noFigures).used == nil)
    }

    /// The banner texts the Storybook part shows, from the rules that post them.
    @Test func nudgeTextsAreTheRulesOwn() {
        let weekly = NudgeRules.due(limits: Fixtures.limits(weekly: 86), now: Fixtures.now, enabled: true)
        #expect(weekly.map(\.title) == ["Weekly at 86%"])
        // the banner names the limit in the Mac's own zone; the limit itself is Fri 16 Oct 05:20 in the sample zone (GMT)
        let lands = PaceModel.format(Fixtures.date(2026, 10, 16, 5, 20), "EEE HH:mm", timeZone: .current)
        #expect(weekly.map(\.body) == ["3 days 3 h to the reset. At this pace the limit lands \(lands)."])
        let fiveAt = Fixtures.date(2026, 10, 15, 17, 32)
        let five = NudgeRules.due(limits: Fixtures.limits(weekly: 61, five: 34, asOf: fiveAt.addingTimeInterval(-60)), now: fiveAt, enabled: true)
        #expect(five.map(\.title) == ["5h window ends in 15 min"])
        #expect(five.map(\.body) == ["34% used."])
    }
}
