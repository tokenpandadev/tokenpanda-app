// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
import Text
import Feed
@testable import UI

/// Snapshots of the real panel: each part of the line grammar drawn by LineView offscreen, through
/// bitmapImageRepForCachingDisplay, in dark and light, compared with the reference PNGs in Snapshots/.
/// Sample data only (Fixtures). TP_RECORD_SNAPSHOTS=1 writes the references anew; a missing reference is written
/// and the test fails once, so a new part is looked at before it counts. On CI (another Mac, another font build) the
/// parts are still drawn and measured, the pixels are not compared.
@MainActor
struct PanelSnapshotTests {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Snapshots")
    static let env = ProcessInfo.processInfo.environment
    static var record: Bool { env["TP_RECORD_SNAPSHOTS"] == "1" }
    static var onCI: Bool { env["CI"] != nil }

    /// A pixel differs when one channel moves by more than this; a snapshot fails when more than `allowed` pixels differ.
    /// The same Mac renders the same bitmap, so the count is small: one changed digit moves about a hundred pixels.
    static let channelTolerance = 16
    static let allowed = 8

    enum Part: String, CaseIterable, Sendable {
        case tabsClaude = "tabs-claude"
        case tabsMacWarning = "tabs-mac-warning"
        case sectionSwitch = "section-switch"
        case windowOverPace = "window-over-pace"
        case windowStale = "window-stale"
        case windowTooEarly = "window-too-early"
        case sessions = "sessions"
        case rowsAndChips = "rows-and-chips"
        case rowHoverTooltip = "row-hover-tooltip"
        case sessionHoverTooltip = "session-hover-tooltip"
        case tabPressedSelected = "tab-pressed-selected"
        case weeks = "weeks"
        case memoryGrid = "memory-grid"
        case macBars = "mac-bars"
        case macHealthOther = "mac-health-other"
        case settingsRows = "settings-rows"
        case focusRing = "focus-ring"
        case popoverClaude = "popover-claude"
        case popoverMac = "popover-mac"
        case popoverSettings = "popover-settings"
    }

    /// Three hours into the sample week (Sunday 11 October, 21:00): too little of the week has passed to project.
    static var tooEarly: LiveInput {
        let now = Fixtures.date(2026, 10, 11, 21, 0)
        var i = Fixtures.input(weekly: 2)
        let limits = Limits(windows: ["seven_day": .init(used: 2, resetsAt: Fixtures.weeklyReset, previousResetsAt: nil, contradicts: false),
                                      "five_hour": .init(used: 3, resetsAt: Fixtures.date(2026, 10, 11, 23, 50), previousResetsAt: nil, contradicts: false)],
                            asOf: now.addingTimeInterval(-60))
        i.feed = FeedState(limits: limits, sessions: Fixtures.openSessions, lastWriteAt: now.addingTimeInterval(-2))
        i.now = now
        return i
    }

    static func screen(_ name: String) throws -> Screen {
        let input = try #require(Fixtures.all().first { $0.0 == name }?.1)
        return ScreenBuilder.screen(input)
    }

    /// The lines of a part, and what to set on the view before it draws.
    static func lines(_ part: Part) throws -> ([Line], (LineView) -> Void) {
        let none: (LineView) -> Void = { _ in }
        let claude = try screen("claude-overpace")
        switch part {
        case .tabsClaude: return (Grammar.header(line: claude.headerLine, tab: 0, warn: false), none)
        case .tabsMacWarning: return (Grammar.header(line: claude.headerLine, tab: 1, warn: true), none)
        case .sectionSwitch: return ([Grammar.subTabs(0), Grammar.subTabs(1), Grammar.subTabs(2)], none)
        case .windowOverPace: return (Grammar.limits(claude.claude.limits), none)
        case .windowStale: return (Grammar.limits(try screen("claude-stale").claude.limits), none)
        case .windowTooEarly: return (Grammar.limits(ScreenBuilder.screen(Self.tooEarly).claude.limits), none)
        case .sessions: return (Grammar.sessionRows(claude.claude.sessions, more: claude.claude.moreSessions), none)
        case .rowsAndChips: return (Grammar.tokens(claude.claude.tokens), none)
        case .rowHoverTooltip:
            // the first model row under the pointer, its figure's tooltip open
            let lines = Grammar.tokens(claude.claude.tokens)
            let row = try #require(lines.firstIndex { $0.hover })
            let piece = try #require(lines[row].pieces.lastIndex { $0.tip != nil })
            return (lines, { v in v.hoverLine = row; v.hoverTip = (line: row, piece: piece) })
        case .sessionHoverTooltip:
            // the pointer on the second session's name line: both lines highlight, the tooltip clears the row (0.1.19)
            let lines = Grammar.sessionRows(claude.claude.sessions, more: claude.claude.moreSessions)
            let name = try #require(lines.lastIndex { $0.joinsNext })
            return (lines, { v in v.pointerMoved(to: NSPoint(x: v.padSide + 3 * v.cellWidth, y: v.lineY(name) + 8)) })
        case .tabPressedSelected:
            // a press held on the selected tab: its ink at a quarter on the accent (0.1.19)
            return (Grammar.header(line: claude.headerLine, tab: 0, warn: false), { v in
                if let c = v.controls.first(where: { $0.action == .tab(0) }) { let r = v.controlRect(c); v.pointerDown(at: NSPoint(x: r.midX, y: r.midY)) }
            })
        case .weeks: return (claude.claude.weeks.map(Grammar.week), none)
        case .memoryGrid: return (Grammar.memGrid(try #require(try screen("mac").mac.memory)), none)
        case .macBars: return (Grammar.macTab(try screen("mac").mac), none)
        case .macHealthOther: return (Grammar.macTab(try screen("mac-health-other").mac), none)
        case .settingsRows: return (Grammar.settingsTab(try screen("settings").settings), none)
        case .focusRing:
            // the keyboard on the second setting
            return (Grammar.settingsTab(try screen("settings").settings), { v in v.setFocus(1, visible: true, announce: false) })
        case .popoverClaude: return (Grammar.popover(claude), none)
        case .popoverMac: return (Grammar.popover(try screen("mac")), none)
        case .popoverSettings: return (Grammar.popover(try screen("settings")), none)
        }
    }

    /// Draws the lines offscreen through the view's own cache, as AppKit draws it into the popover.
    static func render(_ lines: [Line], light: Bool, prepare: (LineView) -> Void) throws -> NSBitmapImageRep {
        let v = LineView()
        v.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        v.drawsStage = true
        v.lines = lines
        v.frame = NSRect(x: 0, y: 0, width: LineView.width, height: v.contentHeight)
        prepare(v)
        let rep = try #require(v.bitmapImageRepForCachingDisplay(in: v.bounds))
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }

    /// RGBA8 pixels of an image, drawn into one known format so a PNG read back and a fresh render compare alike.
    static func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        out.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    nonisolated static let cases: [(Part, Bool)] = Part.allCases.flatMap { [($0, false), ($0, true)] }

    @Test(arguments: cases)
    func panelPartMatchesItsReference(_ part: Part, light: Bool) throws {
        let name = "\(part.rawValue)-\(light ? "light" : "dark")"
        let (lines, prepare) = try Self.lines(part)
        #expect(!lines.isEmpty)
        let rep = try Self.render(lines, light: light, prepare: prepare)
        // the part is the panel's width and its lines' height, whatever the backing scale
        #expect(rep.size.width == LineView.width)
        #expect(rep.size.height == 12 + CGFloat(lines.count) * LineView.lineHeight + 10)
        try Self.compare(rep, name)
    }

    /// Compares a render with its reference PNG, or writes the reference when there is none (or when recording).
    static func compare(_ rep: NSBitmapImageRep, _ name: String) throws {
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = dir.appendingPathComponent(name + ".png")
        let exists = FileManager.default.fileExists(atPath: url.path)
        let write = record ? true : !exists && !onCI
        if write {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: url)
            if !record { Issue.record("Recorded the new reference \(name).png; look at it, then run the tests again") }
            return
        }
        if onCI { return }
        let actual = try #require(NSBitmapImageRep(data: png)?.cgImage)
        let reference = try #require(NSBitmapImageRep(data: try Data(contentsOf: url))?.cgImage)
        let same = actual.width == reference.width && actual.height == reference.height
        #expect(same, "\(name): \(actual.width) by \(actual.height) px, the reference is \(reference.width) by \(reference.height)")
        guard same else { return keep(png, name) }
        let a = pixels(actual), b = pixels(reference)
        var differing = 0
        for p in stride(from: 0, to: a.count, by: 4) {
            for c in 0..<4 where abs(Int(a[p + c]) - Int(b[p + c])) > channelTolerance { differing += 1; break }
        }
        #expect(differing <= allowed, "\(name): \(differing) pixels differ from the reference")
        if differing > allowed { keep(png, name) }
    }

    /// A failing render is kept in the temporary folder for a look.
    static func keep(_ png: Data, _ name: String) {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let url = out.appendingPathComponent(name + ".png")
        try? png.write(to: url)
        Issue.record("The render is kept at \(url.path)")
    }
}
