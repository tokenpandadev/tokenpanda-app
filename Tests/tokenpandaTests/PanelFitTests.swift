// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
@testable import Text
import Feed
import MacStats
import Transcripts
@testable import UI

/// The panel fixes of 0.1.19 (spec 24): text measured in cells, figures that stay in their column and the panel, the
/// readout on the whole row, the totals line, the price chip, a window at its limit, the unknown window, the planless
/// week, swap on full memory, session names, contrast, the empty and error states, hues, bars, presses on mouse up,
/// the keyboard in a tall panel and the fixtures. Sample data only.
struct PanelFitTests {
    static func screen(_ i: LiveInput) -> Screen { ScreenBuilder.screen(i) }
    static func plain(_ i: LiveInput) -> [String] { Grammar.popover(screen(i)).map(\.plain) }

    /// Every input the tests have: the shipped fixtures and the stress inputs, on every tab and token section.
    static func everyInput() -> [(String, LiveInput)] {
        var out: [(String, LiveInput)] = []
        for (name, input) in Fixtures.all() + Fixtures.stress() {
            for tab in 0..<3 {
                for section in 0..<(tab == 0 ? 3 : 1) {
                    var i = input; i.tab = tab; i.section = section
                    out.append(("\(name) tab \(tab) section \(section)", i))
                }
            }
        }
        return out
    }

    // MARK: width over everything (24.0)

    /// No built line of any fixture or stress input (long, wide, huge) passes the panel: one cell of margin and the 47
    /// content cells, the width of the rule. Each piece's cells are its text measured in cells, wide characters as two.
    @Test func noLineOfAnyFixtureOrStressInputPassesThePanel() {
        for (name, input) in Self.everyInput() {
            for line in Grammar.popover(Self.screen(input)) {
                #expect(line.cells <= Grammar.popCells + 1, "\(name): \(line.cells) cells: \(line.plain)")
                for p in line.pieces where p.bar == nil && !p.wide {
                    #expect(p.cells == Cells.width(p.text), "\(name): piece \(p.text) says \(p.cells) cells")
                }
            }
        }
    }

    // MARK: 1 cells

    @Test func wideCharactersAndEmojiTakeTwoCells() {
        #expect(Cells.width("abc") == 3)
        #expect(Cells.width("日本語") == 6)
        #expect(Cells.width("emoji\u{1F43C}panda") == 12)
        #expect(Cells.width("한국") == 4)
        #expect(Cells.width("\u{26A0}") == 1)              // the hit mark, a text glyph: one cell
        #expect(Cells.width("\u{26A0}\u{FE0F}") == 2)      // asked to show as an emoji: two
        #expect(Cells.width("\u{25CF}\u{2594}\u{2588}\u{26C1}") == 4)   // the panel's own glyphs stay one cell each
        #expect(Piece("日本").cells == 4)
        let c = Format.col("日本語のプロジェクト名前", 14)
        #expect(Cells.width(c) == 14)
        #expect(Cells.width(Format.col("日本語のプロジェクト名前", 14).trimmingCharacters(in: .whitespaces)) <= 14)
        #expect(Format.rcol("日本", 5) == " 日本")
        #expect(Format.wrap("日本語 日本語 日本語", 8).allSatisfy { Cells.width($0) <= 8 })
    }

    @Test @MainActor func theFallbackDrawGivesAWideCharacterTwoCells() {
        let v = LineView()
        let boxes = v.glyphBoxes("日a\u{1F43C}", wide: false)
        #expect(boxes == [2 * v.cellWidth, v.cellWidth, 2 * v.cellWidth])
        #expect(v.glyphBoxes("\u{26C1}\u{26C1}", wide: true) == [2 * v.cellWidth, 2 * v.cellWidth])
    }

    @Test func sessionNameAndModelAlwaysFitOneLine() {
        let room = Grammar.popCells - 2
        let names = ["workspace", String(repeating: "n", count: 80), "日本語のプロジェクト名前テスト日本語のプロジェクト", "emoji\u{1F43C}panda", ""]
        let models = ["Fable 5.1", String(repeating: "m", count: 60), String(repeating: "模", count: 30), ""]
        for n in names {
            for m in models {
                let (cn, cm) = Grammar.nameAndModel(n, m)
                #expect(Cells.width(cn) + Cells.width(cm) <= room, "\(n) \(m)")
                // the model is cut only when it alone leaves the name under eight cells
                if Cells.width(m) <= room - min(8, Cells.width(n)) { #expect(cm == m) }
            }
        }
        // the name is cut first
        let (n1, m1) = Grammar.nameAndModel(String(repeating: "n", count: 80), "Fable 5.1")
        #expect(m1 == "Fable 5.1" && n1.hasSuffix("\u{2026}"))
        // a model alone too long is cut too, the name keeps eight cells
        let (n2, m2) = Grammar.nameAndModel("workspace-long", String(repeating: "m", count: 60))
        #expect(m2.hasSuffix("\u{2026}") && Cells.width(n2) == 8)
    }

    @Test func aBlankLineStandsBetweenSessions() {
        let s = ScreenBuilder.screen(Fixtures.input())
        let lines = Grammar.sessionRows(s.claude.sessions, more: 0).map(\.plain)
        // title, name, bar, blank, name, bar
        #expect(lines.count == 6)
        #expect(lines[3].isEmpty)
        #expect(lines[4].hasPrefix(" tooling"))
    }

    // MARK: 2 figures

    @Test func tokenFiguresPickTheUnitAfterRounding() {
        #expect(Format.tokens(999_999_999) == "1.00B")
        #expect(Format.tokens(99_960) == "100k")
        #expect(Format.tokens(999_950) == "1.0M")
        #expect(Format.tokens(99_960_000) == "100M")
        #expect(Format.tokens(999) == "999")
        #expect(Format.tokens(999_995_000_000) == "1.00T")
        #expect(Format.contextTokens(999_960) == "1M")
        #expect(Format.contextTokens(999_600, decimal: false) == "1M")
        #expect(Format.contextTokens(99_960) == "100k")
        #expect(Format.tokenScale(999_999_999) == .billions)
        #expect(Format.tokenScale(999_950) == .millions)
        #expect(Format.tokens(99_960_000, scale: Format.tokenScale(99_960_000)) == "100M")
        #expect(Format.tokens(999_950, scale: Format.tokenScale(999_950)) == "1.0M")
        // no figure of these reads 1000 of a unit or 100.0
        for n in [999_999_999, 99_960, 999_950, 99_960_000, 999_500, 999_499_999_999] {
            let s = Format.tokens(n, scale: Format.tokenScale(n))
            #expect(!s.hasPrefix("1000") && !s.hasPrefix("100.0"), "\(n): \(s)")
        }
    }

    @Test func smallGroupsNeverReadZeroBesideTheirBar() {
        #expect(Format.tokens(3_000_000, scale: .billions) == "<0.01B")
        #expect(Format.tokens(4_000, scale: .millions) == "<0.1M")
        #expect(Format.tokens(40, scale: .thousands) == "<0.1k")
        #expect(Format.tokens(5_000_000, scale: .billions) == "0.01B")
        #expect(Format.tokens(0, scale: .billions) == "0")
    }

    @Test func theFigureColumnFitsTenBillionAndUp() {
        let list = [RowView(name: "Fable 5.1", hue: Tokens.magenta, share: 91, figure: "123.46B", tip: ""),
                    RowView(name: "Opus 5.5", hue: Tokens.yellow, share: 7, figure: "10.00B", tip: ""),
                    RowView(name: "Zeta 1", hue: Tokens.brightGreen, share: 0, figure: "<0.01B", tip: "")]
        let fw = Grammar.figureCells(list)
        #expect(fw == 7)
        let rows = list.map { Grammar.row($0, figureCells: fw) }
        // every row as wide as a five cell row, the figures right aligned in one column
        #expect(rows.allSatisfy { $0.cells == 47 })
        #expect(rows.map { $0.pieces.last!.text } == ["123.46B", " 10.00B", " <0.01B"])
    }

    @Test func aProcessAtAHundredPercentOrMoreFits() {
        #expect(Format.cpu(6.1) == "6.1%")
        #expect(Format.cpu(99.94) == "99.9%")
        #expect(Format.cpu(99.96) == "100%")
        #expect(Format.cpu(123.4) == "123%")
        #expect(Format.cpu(1000.5) == "1000%")
        var i = Fixtures.input(tab: 1)
        i.mac?.processes = [ProcessSample(pid: 1, name: "busy", cpuPercent: 1000.5, footprint: 1), ProcessSample(pid: 2, name: "b", cpuPercent: 0.5, footprint: 1)]
        for l in Grammar.popover(ScreenBuilder.screen(i)) { #expect(l.cells <= Grammar.popCells + 1, "\(l.plain)") }
        #expect(Self.plain(i).contains { $0.hasSuffix(" 1000%") })
    }

    // MARK: 3 readout on the whole row

    @Test @MainActor func theReadoutShowsOnHoverOfTheWholeRow() throws {
        let v = LineView()
        v.lines = Grammar.tokens(ScreenBuilder.screen(Fixtures.input()).claude.tokens)
        v.frame = NSRect(x: 0, y: 0, width: LineView.width, height: v.contentHeight)
        let row = try #require(v.lines.firstIndex { $0.hover })
        let tip = try #require(v.lines[row].pieces.firstIndex { $0.tip != nil })
        let y = v.lineY(row) + LineView.lineHeight / 2
        for x in [v.padSide + 3 * v.cellWidth, v.padSide + 20 * v.cellWidth, v.padSide + 44 * v.cellWidth] {
            v.hoverTip = nil
            v.pointerMoved(to: NSPoint(x: x, y: y))
            #expect(v.hoverTip?.line == row && v.hoverTip?.piece == tip, "at x \(x)")
        }
        // off the rows, no tooltip
        v.pointerMoved(to: NSPoint(x: v.padSide + 3 * v.cellWidth, y: v.lineY(0) + 4))
        #expect(v.hoverTip == nil)
    }

    // MARK: 4 totals

    @Test func totalsCloseTheTokenSection() throws {
        for section in 0..<3 {
            let t = ScreenBuilder.tokensView(Fixtures.input(section: section))
            #expect(t.totals == "today 72.4M  7 days 2.10B  30 days 9.80B")
            let lines = Grammar.tokens(t)
            let last = try #require(lines.last)
            #expect(last.plain == " today 72.4M  7 days 2.10B  30 days 9.80B")
            #expect(last.pieces.last?.style == .dim)
            #expect(last.label == "today 72.4 million, 7 days 2.10 billion, 30 days 9.80 billion")
        }
        // no figures, no totals
        var reading = Fixtures.input(); reading.tokens = nil
        #expect(ScreenBuilder.tokensView(reading).totals == nil)
    }

    // MARK: 5 price chip

    @Test func aWrappedChipsSecondLineStandsOneCellIn() {
        let t = TokensView(section: 0, rows: [[], [], []], priceChip: "[list price equivalent  USD 1.50  one model unpriced]", agentChip: nil)
        let chip = Grammar.tokens(t).map(\.plain).filter { $0.contains("list price") || $0.contains("unpriced]") }
        #expect(chip == [" [list price equivalent  USD 1.50", "  one model unpriced]"])
        // a chip that fits stays one line, one cell in
        let one = TokensView(section: 0, rows: [[], [], []], priceChip: "[list price equivalent  USD 1,140]", agentChip: nil)
        #expect(Grammar.tokens(one).map(\.plain).contains(" [list price equivalent  USD 1,140]"))
    }

    @Test func theSessionTooltipHasNoPriceWhenListPriceIsOff() {
        var i = Fixtures.input()
        #expect(ScreenBuilder.sessionViews(i).0[0].tip.hasPrefix("USD 38.20 list price equivalent"))
        i.listPrice = false
        let tip = ScreenBuilder.sessionViews(i).0[0].tip
        #expect(!tip.contains("USD") && !tip.contains("list price"))
        #expect(tip == "112 added  9 removed  effort high")
    }

    // MARK: 6 at the limit

    @Test func aWindowAtItsLimitSaysSo() {
        let lines = Self.plain(Fixtures.input(weekly: 100))
        #expect(lines.contains(" limit reached, resets Sun 18:00"))
        let at = lines.firstIndex(of: " Weekly (all models)")!
        #expect(!lines[at..<(at + 5)].contains { $0.contains("Over pace") || $0.contains("an hour left") })
        // the 5h window reads the clock alone
        var five = Fixtures.input()
        five.feed.limits = Fixtures.limits(weekly: 61, five: 100)
        #expect(Self.plain(five).contains(" limit reached, resets 17:45"))
        // and VoiceOver says it in the section's label
        let w = ScreenBuilder.windowView(key: "seven_day", limits: Fixtures.limits(weekly: 100), now: Fixtures.now, tz: Fixtures.timeZone)
        #expect(Grammar.windowLabel(w).contains("limit reached, resets Sunday 18:00"))
    }

    @Test func ninetyNinePointFiveNeverReadsAHundred() {
        #expect(Format.percentUsed(99.5) == 99)
        #expect(Format.percentUsed(99.99) == 99)
        #expect(Format.percentUsed(100) == 100)
        #expect(Format.percentUsed(61.4) == 61)
        var i = Fixtures.input()
        i.feed.limits = Fixtures.limits(weekly: 61, five: 99.5)
        let lines = Self.plain(i)
        #expect(!lines.contains { $0.hasSuffix("100% used") })
        #expect(lines.contains { $0.hasSuffix(" 99% used") })
        // the menu bar item too
        var w = Fixtures.input(weekly: 99.5)
        w.feed.limits = Fixtures.limits(weekly: 99.5)
        #expect(ScreenBuilder.item(w).used == 99)
    }

    // MARK: 7 unknown window

    @Test func anUnknownWindowKeyGetsAReadableTitleThatFits() {
        var lim = Fixtures.limits(weekly: 61)
        let key = "seven_day_opus_extra_long_key_that_runs_well_past_the_panel_edge"
        lim.windows[key] = .init(used: 12, resetsAt: Fixtures.weeklyReset)
        lim.windows["seven_day_opus"] = .init(used: 5, resetsAt: Fixtures.weeklyReset)
        var i = Fixtures.input(); i.feed.limits = lim
        let lines = Grammar.popover(ScreenBuilder.screen(i))
        #expect(ScreenBuilder.windowTitle("seven_day_opus") == "seven day opus")
        #expect(lines.map(\.plain).contains(" seven day opus"))
        let long = lines.first { $0.plain.hasPrefix(" seven day opus extra") }
        #expect(long != nil && long!.cells <= Grammar.popCells + 1 && long!.plain.hasSuffix("\u{2026}"))
        #expect(!lines.contains { $0.plain.contains("_") })
    }

    // MARK: 8 planless week

    @Test func aPlanlessFeedDoesNotSayNoFeedYet() {
        let planless = FeedState(limits: Limits(asOf: Fixtures.now.addingTimeInterval(-60), planless: true),
                                 sessions: Fixtures.openSessions, lastWriteAt: Fixtures.now.addingTimeInterval(-2))
        var i = Fixtures.input(feedState: planless)
        i.weeks = WeekRecords()
        let weeks = ScreenBuilder.weekViews(i)
        #expect(!weeks.contains { $0.note == "no feed yet" })
        #expect(weeks.last?.note == "no plan limits")
        // no feed at all still says so
        var none = Fixtures.input(feedState: FeedState())
        none.weeks = WeekRecords()
        #expect(ScreenBuilder.weekViews(none).last?.note == "no feed yet")
    }

    // MARK: 9 memory full with swap

    @Test func fullMemoryStillShowsItsSwap() throws {
        var i = Fixtures.input(tab: 1)
        let total = i.mac!.memoryTotal
        i.mac?.memoryUsed = total
        i.mac?.swapUsed = 12 * 1_073_741_824
        let mem = try #require(ScreenBuilder.macTab(i).memory)
        #expect(mem.swapCells > 0)
        #expect(mem.usedCells + mem.swapCells <= 200)
        let grid = Grammar.memGrid(mem).prefix(10).map(\.plain).joined()
        #expect(grid.filter { $0 == "\u{26DD}" }.count == mem.swapCells)
        // a little swap still shows one cell
        i.mac?.swapUsed = 1_048_576
        #expect(try #require(ScreenBuilder.macTab(i).memory).swapCells == 1)
        i.mac?.swapUsed = 0
        #expect(try #require(ScreenBuilder.macTab(i).memory).swapCells == 0)
    }

    // MARK: 10 session names in the token rows

    @Test func tokenSessionRowsUseTheOpenSessionNames() {
        var i = Fixtures.input(section: 2)
        var names = ScreenBuilder.tokensView(i).rows[2].map(\.name)
        // the open sessions go by their folders, the closed one by its id
        #expect(names == ["workspace", "tooling", "c91e0a44", "other"])
        i.sessionNames = ["3f1a9c2e-0000-4000-8000-000000000001": "refactor"]
        names = ScreenBuilder.tokensView(i).rows[2].map(\.name)
        #expect(names == ["refactor", "tooling", "c91e0a44", "other"])
    }

    // MARK: 11 contrast

    func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    func lum(_ c: RGBA) -> Double { 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }
    func over(_ top: RGBA, _ ground: RGBA) -> RGBA {
        RGBA(r: top.r * top.a + ground.r * (1 - top.a), g: top.g * top.a + ground.g * (1 - top.a), b: top.b * top.a + ground.b * (1 - top.a))
    }
    func ratio(_ a: RGBA, _ b: RGBA) -> Double { let x = lum(a), y = lum(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }

    @Test func theWarningDotOnTheSelectedTabReachesThreeToOne() throws {
        let tabs = Grammar.header(line: "x", tab: 1, warn: true)[2]
        let dot = try #require(tabs.pieces.first { $0.text == "\u{25CF}" })
        #expect(dot.style.fg == Tokens.warningOnAccent)
        #expect(ratio(dot.style.fg, Tokens.accent) >= 3)
        #expect(ratio(Tokens.light(dot.style.fg), Tokens.light(Tokens.accent)) >= 3)
        // on a tab not selected the dot keeps the warning, on the glass
        let other = Grammar.header(line: "x", tab: 0, warn: true)[2]
        #expect(other.pieces.first { $0.text == "\u{25CF}" }?.style.fg == Tokens.warning)
    }

    /// The bar track and the stale fill against their ground, dark and light: the glass of the style guide's
    /// measurement (#111424 to #202030, and the tint over the stage), and the light glass over white and the light stage.
    @Test func barTrackAndStaleFillReachThreeToOne() {
        let dark = [RGBA(hex: 0x111424), RGBA(hex: 0x202030), over(Tokens.tint, Tokens.stage)]
        let light = [over(Tokens.tintLight, Tokens.white), over(Tokens.tintLight, Tokens.stageLight)]
        for g in dark {
            #expect(ratio(Tokens.track, g) >= 3)
            #expect(ratio(Tokens.staleFill, over(Tokens.trackStale, g)) >= 3)
        }
        for g in light {
            #expect(ratio(Tokens.light(Tokens.track), g) >= 3)
            #expect(ratio(Tokens.light(Tokens.staleFill), over(Tokens.light(Tokens.trackStale), g)) >= 3)
        }
        // a stale bar is drawn in the stale fill
        #expect(Bar.render(width: 10, used: 50, elapsed: nil, options: BarOptions(stale: true)).cells[0].color == Tokens.staleFill)
    }

    @Test func theNewTokensHaveLightPartnersAndPassForGraphics() {
        let bright = over(Tokens.tint, Tokens.white)
        let lightBright = over(Tokens.tintLight, Tokens.white), lightDarkest = over(Tokens.tintLight, RGBA(hex: 0x000000))
        for c in [Tokens.staleFill, Tokens.warningOnAccent] + Tokens.spare { #expect(Tokens.light(c) != c) }
        for c in Tokens.spare {
            #expect(ratio(c, bright) >= 3)
            #expect(ratio(Tokens.light(c), lightBright) >= 3 && ratio(Tokens.light(c), lightDarkest) >= 3)
        }
    }

    // MARK: 12 empty and error states

    @Test func aTranscriptErrorWrapsLikeTheOtherErrors() {
        var i = Fixtures.input()
        i.tokens = nil
        let e = "The file \u{201C}projects\u{201D} couldn\u{2019}t be opened because you don\u{2019}t have permission to view it."
        i.transcriptsError = e
        let lines = Self.plain(i)
        #expect(!lines.contains { $0.contains("\u{2026}") })
        let at = lines.firstIndex { $0.contains("The file") }!
        let text = lines[at...].prefix { !$0.isEmpty }.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        #expect(text == e)
    }

    @Test func theSamplingMacTabHasNoEmptyProcessTitle() {
        var i = Fixtures.input(tab: 1)
        i.mac = nil
        let lines = Self.plain(i)
        #expect(lines.contains(" sampling"))
        #expect(!lines.contains { $0.contains("Processes by CPU") })
        #expect(!lines.contains { $0.contains(" 0%") })
        // a process error still has its title
        var e = Fixtures.input(tab: 1)
        e.mac?.processes = []; e.mac?.processError = "denied"
        #expect(Self.plain(e).contains(" Processes by CPU"))
    }

    @Test func noTranscriptsLeavesOutWeekOverWeek() {
        var i = Fixtures.input()
        i.transcriptsRootsExist = false
        let lines = Self.plain(i)
        #expect(lines.contains(" No transcripts in ~/.claude/projects"))
        #expect(!lines.contains(" Week over week"))
        // reading and the error keep it
        var reading = Fixtures.input(); reading.tokens = nil
        #expect(Self.plain(reading).contains(" Week over week"))
    }

    @Test func emptyAndErrorTextsNameTheFoldersLookedIn() {
        var i = Fixtures.input()
        i.transcriptsRootsExist = false
        i.transcriptFolders = ["~/.claude/projects", "~/.config/claude/projects", "~/.claude-work/projects"]
        #expect(ScreenBuilder.tokensView(i).empty == "No transcripts in ~/.claude/projects, ~/.config/claude/projects, ~/.claude-work/projects")
        let text = Self.plain(i).filter { $0.contains("projects") }.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        #expect(text == "No transcripts in ~/.claude/projects, ~/.config/claude/projects, ~/.claude-work/projects")
        i.transcriptsRootsExist = true; i.tokens = nil; i.transcriptsError = "denied"
        #expect(ScreenBuilder.tokensView(i).empty == "Cannot read ~/.claude/projects, ~/.config/claude/projects, ~/.claude-work/projects")
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(ScreenBuilder.folderNames([URL(fileURLWithPath: "/Users/someone/.claude/projects"), URL(fileURLWithPath: "/Volumes/x/projects")], home: home)
                == ["~/.claude/projects", "/Volumes/x/projects"])
    }

    // MARK: 13 hues and bars

    @Test func anUnknownModelFamilyTakesTheNextFreeHue() {
        let hues = Tokens.hues(forFamilies: ["fable", "zeta", "opus", "omega", "zeta"])
        #expect(hues["fable"] == Tokens.magenta && hues["opus"] == Tokens.yellow)
        #expect(hues["zeta"] == Tokens.brightGreen && hues["omega"] == Tokens.brightYellow)
        #expect(Tokens.hue(forFamily: "nothing") != Tokens.procWhite)
        var i = Fixtures.input()
        i.tokens?.byModel7d.append(TokenGroup(name: "Zeta 1", key: "claude-zeta-1", tokens: 1_000_000, share: 1))
        let rows = ScreenBuilder.tokensView(i).rows[0]
        #expect(rows.last?.hue == Tokens.brightGreen)
        #expect(!rows.contains { $0.hue == Tokens.procWhite })
    }

    /// Pixels of a render, dark, without the stage: the ground is clear, so a seam shows as a pixel under full alpha.
    @MainActor static func render(_ lines: [Line]) throws -> NSBitmapImageRep {
        let v = LineView()
        v.appearance = NSAppearance(named: .darkAqua)
        v.lines = lines
        v.frame = NSRect(x: 0, y: 0, width: LineView.width, height: v.contentHeight)
        let rep = try #require(v.bitmapImageRepForCachingDisplay(in: v.bounds))
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }

    static func rgba(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
        var p = [Int](repeating: 0, count: 4)
        rep.getPixel(&p, atX: x, y: y)
        return p
    }

    @Test @MainActor func theLastPartialBarCellIsFullHeight() throws {
        // 10 full cells and four eighths of a 24 cell bar, no track (a row bar), alone on its line
        let bar = Bar.render(width: 24, used: 10.5 / 24 * 100, elapsed: nil, options: BarOptions(color: Tokens.accent, plain: true))
        let v = LineView()
        let rep = try Self.render([Line([Piece(" "), .bar(bar)])])
        let scale = CGFloat(rep.pixelsWide) / LineView.width
        func extent(atCell c: Double) -> (Int, Int)? {
            let x = Int(((v.padSide + CGFloat(1 + c) * v.cellWidth) * scale).rounded(.down))
            let rows = (0..<rep.pixelsHigh).filter { Self.rgba(rep, x, $0)[3] == 255 }
            return rows.first.map { ($0, rows.last!) }
        }
        let full = try #require(extent(atCell: 3.5))
        let part = try #require(extent(atCell: 10.2))
        #expect(full == part, "full cell rows \(full), the last partial cell \(part)")
        // no seam inside the fill: every pixel column across the full cells is opaque at mid height
        let mid = (full.0 + full.1) / 2
        let x0 = Int(((v.padSide + v.cellWidth) * scale).rounded(.up)) + 1
        let x1 = Int(((v.padSide + 11 * v.cellWidth) * scale).rounded(.down)) - 1
        for x in x0...x1 { #expect(Self.rgba(rep, x, mid)[3] == 255, "seam at pixel column \(x)") }
    }

    @Test @MainActor func theSelectedMacTabWithItsDotIsOneFlatBlock() throws {
        let lines = Grammar.header(line: "x", tab: 1, warn: true)
        let rep = try Self.render(lines)
        let v = LineView()
        let scale = CGFloat(rep.pixelsWide) / LineView.width
        // " Claude " is cells 1 to 8, two spaces, then " Mac ", the dot and a space: cells 11 to 17
        let y = Int(((v.padTop + 2 * LineView.lineHeight) * scale).rounded(.up)) + 1   // the block's top row, above any glyph
        let x0 = Int(((v.padSide + 11 * v.cellWidth) * scale).rounded(.up)) + 1
        let x1 = Int(((v.padSide + 18 * v.cellWidth) * scale).rounded(.down)) - 1
        let first = Self.rgba(rep, x0, y)
        #expect(first[3] == 255)
        for x in x0...x1 { #expect(Self.rgba(rep, x, y) == first, "seam at pixel column \(x)") }
    }

    // MARK: 14 presses act on mouse up

    @Test @MainActor func controlsActOnMouseUpInsideAndCanBeCancelled() throws {
        let v = LineView()
        v.lines = Grammar.popover(ScreenBuilder.screen(Fixtures.input(tab: 2)))
        v.frame = NSRect(x: 0, y: 0, width: LineView.width, height: v.contentHeight)
        var acted: [Action] = []
        v.onAction = { acted.append($0) }
        let quit = try #require(v.controls.first { $0.action == .quit })
        let r = v.controlRect(quit)
        let inside = NSPoint(x: r.midX, y: r.midY), outside = NSPoint(x: r.midX, y: r.minY - 3 * LineView.lineHeight)
        v.pointerDown(at: inside)
        #expect(acted.isEmpty, "nothing on the press")
        #expect(v.pressed?.inside == true)
        v.pointerUp(at: inside)
        #expect(acted == [.quit])
        // dragged off before letting go: cancelled
        acted = []
        v.pointerDown(at: inside)
        v.pointerDragged(to: outside)
        #expect(v.pressed?.inside == false)
        v.pointerUp(at: outside)
        #expect(acted.isEmpty)
        #expect(v.pressed == nil)
        // dragged off and back: it acts
        v.pointerDown(at: inside); v.pointerDragged(to: outside); v.pointerDragged(to: inside); v.pointerUp(at: inside)
        #expect(acted == [.quit])
    }

    // MARK: 15 the keyboard in a tall panel

    @Test @MainActor func downReachesEveryLineOfAPanelShorterThanItsLines() throws {
        let v = LineView()
        // many sessions and the long stress input on a small screen
        let input = try #require(Fixtures.stress().first { $0.0 == "stress-wide" }?.1)
        v.lines = Grammar.popover(ScreenBuilder.screen(input))
        v.frame = NSRect(x: 0, y: 0, width: LineView.width, height: v.contentHeight)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: LineView.width, height: 300))
        scroll.documentView = v
        #expect(v.visibleRect.maxY < v.bounds.maxY - 1)
        for _ in 0..<(v.controls.count + v.lines.count) { _ = v.moveFocus(.down) }
        #expect(abs(v.visibleRect.maxY - v.bounds.maxY) < 1, "the last line is in view")
        for _ in 0..<(v.controls.count + v.lines.count) { _ = v.moveFocus(.up) }
        #expect(v.visibleRect.minY < 1, "and the first again")
    }

    // MARK: 16 fixtures

    @Test func aPressureWarnFixture() throws {
        let input = try #require(Fixtures.all().first { $0.0 == "mac-pressure-warn" }?.1)
        #expect(Self.plain(input).contains { $0.contains("Pressure warn") })
        #expect(input.warn)
    }
}
