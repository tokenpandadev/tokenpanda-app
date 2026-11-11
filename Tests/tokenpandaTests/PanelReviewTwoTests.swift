// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
import Text
import Feed
@testable import UI

/// The fixes of the second design review of 0.1.19 (spec 24.46 to 24.53): tooltips placed off their own row and the
/// tabs, a session as one row, the press on the selected tab, the spare hue rule, a huge session figure, the week at 0%,
/// the highlight and the header rule.
@MainActor
struct PanelReviewTwoTests {
    static func view(_ lines: [Line]) -> LineView {
        let v = LineView()
        v.appearance = NSAppearance(named: .darkAqua)
        v.drawsStage = true
        v.lines = lines
        v.frame = NSRect(x: 0, y: 0, width: LineView.width, height: v.contentHeight)
        return v
    }

    static func render(_ v: LineView) throws -> NSBitmapImageRep {
        let rep = try #require(v.bitmapImageRepForCachingDisplay(in: v.bounds))
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }

    /// The pixel at a point of the view, in device pixels of the rep.
    static func pixel(_ rep: NSBitmapImageRep, _ v: LineView, _ x: CGFloat, _ y: CGFloat) -> [Int] {
        let s = CGFloat(rep.pixelsWide) / v.bounds.width
        var p = [Int](repeating: 0, count: 4)
        rep.getPixel(&p, atX: Int(x * s), y: Int(y * s))
        return p
    }

    static var claude: [Line] { Grammar.popover(ScreenBuilder.screen(Fixtures.input())) }

    /// The lines a tooltip rect covers.
    static func covered(_ r: NSRect, _ v: LineView) -> Range<Int> {
        let a = Int(((r.minY - v.padTop) / LineView.lineHeight).rounded())
        return a..<(a + Int((r.height / LineView.lineHeight).rounded()))
    }

    // MARK: 24.46 tooltips

    @Test func everyTooltipSitsOnTheLineGridOffItsRowAndOffTheTabs() throws {
        for lines in [Self.claude, Grammar.tokens(ScreenBuilder.screen(Fixtures.input()).claude.tokens),
                      Grammar.sessionRows(ScreenBuilder.screen(Fixtures.input()).claude.sessions, more: 0)] {
            let v = Self.view(lines)
            var seen = 0
            for (li, line) in lines.enumerated() {
                for (pi, p) in line.pieces.enumerated() {
                    guard let tip = p.tip, p.action == nil else { continue }
                    seen += 1
                    let layout = v.tipLayout(tip, line: li, piece: pi)
                    let r = layout.clear
                    // the box inside its lines, 2 pt short of them on one side only: the gap to its row
                    #expect(layout.rect.minX >= r.minX && layout.rect.maxX <= r.maxX && r.width == v.bounds.width && layout.rect.height == r.height - 2)
                    // whole lines of the grid: no part of a covered line shows under its edge
                    let off = (r.minY - v.padTop) / LineView.lineHeight
                    #expect(off == off.rounded(), "line \(li): tooltip at y \(r.minY) is off the grid")
                    #expect(r.height == r.height.rounded() && Int(r.height) % Int(LineView.lineHeight) == 0)
                    let cover = Self.covered(r, v)
                    #expect(!cover.overlaps(v.rowLines(li)), "line \(li): the tooltip covers its own row")
                    for k in cover where k >= 0 && k < lines.count { #expect(!lines[k].isTabRow, "line \(li): the tooltip covers the tabs on line \(k)") }
                    #expect(r.minY >= 0 && r.maxY <= v.bounds.maxY, "line \(li): \(r) outside \(v.bounds)")
                }
            }
            #expect(seen > 0)
        }
    }

    @Test func theFirstModelRowsTooltipGoesBelowTheSectionSwitch() throws {
        let lines = Grammar.tokens(ScreenBuilder.screen(Fixtures.input()).claude.tokens)
        let v = Self.view(lines)
        let row = try #require(lines.firstIndex { $0.hover })
        #expect(lines[row - 1].isTabRow)
        let pi = try #require(lines[row].pieces.firstIndex { $0.tip != nil })
        let t = v.tipLayout(try #require(lines[row].pieces[pi].tip), line: row, piece: pi)
        #expect(t.clear.minY == v.lineY(row + 1))
        #expect(t.rect.minY == v.lineY(row + 1) + 2)
    }

    @Test func theSessionTooltipLeavesNoPixelOfItsDrawingBehind() throws {
        let lines = Self.claude
        let v = Self.view(lines)
        let clean = try Self.render(v)
        let name = try #require(lines.firstIndex { $0.joinsNext })
        v.pointerMoved(to: NSPoint(x: v.padSide + 3 * v.cellWidth, y: v.lineY(name) + 8))
        #expect(v.hoverTip != nil)
        let hovered = try Self.render(v)
        #expect(hovered.representation(using: .png, properties: [:]) != clean.representation(using: .png, properties: [:]))
        // the name and model line under the hover is still drawn: the tooltip is off the row
        let t = try #require(v.openTip)
        #expect(!Self.covered(t.clear, v).overlaps(name...(name + 1)))
        // the gap between the box and the row, and every covered line under the box's edge, show only the ground
        let ground = Self.pixel(hovered, v, v.bounds.width - 2, t.clear.minY + 1)
        let gapY = t.rect.minY > t.clear.minY ? t.clear.minY + 1 : t.clear.maxY - 1
        var x = t.clear.minX + 0.5
        while x < t.clear.maxX - 0.5 {
            #expect(Self.pixel(hovered, v, x, gapY) == ground, "a pixel of a covered line at x \(x)")
            x += 0.5
        }
        for k in Self.covered(t.clear, v) {
            var bx = t.rect.maxX + 0.5
            while bx < v.bounds.width - 0.5 {
                #expect(Self.pixel(hovered, v, bx, v.lineY(k) + 8) == ground, "line \(k) shows beside the box at x \(bx)")
                bx += 0.5
            }
        }
        v.hoverLine = nil; v.hoverTip = nil
        let after = try Self.render(v)
        #expect(after.representation(using: .png, properties: [:]) == clean.representation(using: .png, properties: [:]))
    }

    // MARK: 24.47 a session is one row

    @Test func theNameLineAndTheBarLineAreOneRow() throws {
        let lines = Self.claude
        let v = Self.view(lines)
        let name = try #require(lines.firstIndex { $0.joinsNext })
        let bar = name + 1
        let tip = try #require(lines[bar].pieces.firstIndex { $0.tip != nil })
        for y in [v.lineY(name) + 8, v.lineY(bar) + 8] {
            v.hoverLine = nil; v.hoverTip = nil
            v.pointerMoved(to: NSPoint(x: v.padSide + 10 * v.cellWidth, y: y))
            #expect(v.hoverRows == name...bar, "at y \(y)")
            #expect(v.hoverTip?.line == bar && v.hoverTip?.piece == tip, "at y \(y)")
        }
        // both lines are highlighted
        let rep = try Self.render(v)
        let sel = Self.pixel(rep, v, v.padSide + 1, v.lineY(name) + 1)
        #expect(Self.pixel(rep, v, v.padSide + 1, v.lineY(bar) + 1) == sel)
        v.hoverLine = nil; v.hoverTip = nil
        let plain = try Self.render(v)
        #expect(Self.pixel(plain, v, v.padSide + 1, v.lineY(name) + 1) != sel)
        // the blank line between sessions is no part of either row
        #expect(!lines[bar].joinsNext)
    }

    // MARK: 24.48 the press on the selected tab

    @Test func aPressOnTheSelectedTabShows() throws {
        for (lines, action) in [(Grammar.header(line: "x", tab: 0, warn: false), Action.tab(0)), ([Grammar.subTabs(1)], Action.section(1))] {
            let v = Self.view(lines)
            let c = try #require(v.controls.first { $0.action == action })
            #expect(c.checked == true)
            let r = v.controlRect(c)
            let at = (r.minX + v.cellWidth / 2, r.midY)
            let up = Self.pixel(try Self.render(v), v, at.0, at.1)
            v.pointerDown(at: NSPoint(x: r.midX, y: r.midY))
            let down = Self.pixel(try Self.render(v), v, at.0, at.1)
            #expect(up != down, "\(action): the press does not show")
            v.pointerUp(at: NSPoint(x: r.midX, y: r.midY))
        }
    }

    // MARK: 24.49 spare hues

    @Test func anUnknownFamilyNeverTakesASpareHueNearOneOnScreen() {
        let families = ["fable", "opus", "sonnet", "haiku"]
        // every set of families with one unknown: the unknown is far from each family in the set while a far spare is left
        for mask in 0..<15 {
            let set = families.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let hues = Tokens.hues(forFamilies: set + ["zeta"])
            let z = hues["zeta"]!
            for f in set { #expect(Tokens.difference(z, Tokens.knownHue(forFamily: f)!) >= Tokens.closeHue, "\(set): zeta near \(f)") }
        }
        // the review's case: an unknown beside Opus is not the bright yellow
        #expect(Tokens.hues(forFamilies: ["opus", "unpriced"])["unpriced"] != Tokens.brightYellow)
        // each spare is the bright twin of one family, so it is near that one only
        for s in Tokens.spare {
            #expect(families.filter { Tokens.difference(s, Tokens.knownHue(forFamily: $0)!) < Tokens.closeHue }.count == 1)
        }
        // all four families on screen: no far spare is left, the palette order holds and two unknowns still differ
        let all = Tokens.hues(forFamilies: families + ["zeta", "omega"])
        #expect(all["zeta"] == Tokens.brightGreen && all["omega"] != all["zeta"])
    }

    // MARK: 24.50 a huge session figure

    @Test func aHugeSessionFigureFitsInItsUnit() throws {
        #expect(Format.contextTokens(Int.max) == ">999T")
        #expect(Format.contextTokens(Int.max, decimal: false) == ">999T")
        #expect(Format.contextTokens(1_234_000_000) == "1.2B")
        #expect(Format.contextTokens(999_960_000) == "1B")
        #expect(Format.contextTokens(12_300_000_000_000) == "12.3T")
        var i = Fixtures.input()
        var s = i.feed.sessions[0].snapshot
        s.currentUsageTokens = Int.max
        i.feed.sessions[0] = OpenSession(snapshot: s)
        let lines = Grammar.popover(ScreenBuilder.screen(i))
        let row = try #require(lines.first { $0.plain.contains(">999T of 1M") })
        #expect(!row.plain.contains("\u{2026}"))
        #expect(row.cells <= Grammar.popCells + 1)
    }

    // MARK: 24.51 the week at 0%

    @Test func theWeekAtZeroSaysAWholeSentence() throws {
        let lines = Grammar.popover(ScreenBuilder.screen(Fixtures.input(weekly: 0))).map(\.plain)
        #expect(lines.contains(" Ahead  0% by reset at this rate"))
        #expect(!lines.contains(" Ahead"))
    }

    // MARK: 24.52 the highlight and the rule

    @Test func theHighlightEndsWithTheRuleAndTheRuleIsOnePiece() throws {
        let lines = Self.claude
        let v = Self.view(lines)
        let row = try #require(lines.firstIndex { $0.hover && !$0.joinsNext && $0.pieces.contains { $0.tip != nil } })
        let end = v.padSide + v.columnWidth
        let plain = try Self.render(v)
        v.hoverLine = row
        let lit = try Self.render(v)
        let y = v.lineY(row) + 1
        #expect(Self.pixel(lit, v, end - 1, y) != Self.pixel(plain, v, end - 1, y), "the highlight stops short of the rule")
        #expect(Self.pixel(lit, v, end + 1, y) == Self.pixel(plain, v, end + 1, y), "the highlight runs past the rule")
        // the rule: one flat colour along its middle pixel row, from its first cell to its last
        let ruleLine = try #require(lines.firstIndex { $0.plain.allSatisfy { $0 == LineView.ruleGlyph } && !$0.plain.isEmpty })
        let ry = v.lineY(ruleLine) + v.ruleTop + v.ruleHeight / 2
        let first = Self.pixel(plain, v, v.padSide + 0.5, ry)
        #expect(first != Self.pixel(plain, v, v.padSide + 0.5, v.lineY(ruleLine) + LineView.lineHeight - 1), "the rule is not drawn")
        var x = v.padSide + 0.5
        while x < end - 0.5 {
            #expect(Self.pixel(plain, v, x, ry) == first, "the rule changes at x \(x)")
            x += 0.5
        }
        #expect(Self.pixel(plain, v, end + 1, ry) != first)
    }
}
