// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit

import CoreText
import Text

/// How tall the panel is: as tall as its lines, at most the visible height of the screen less 60 pt (the arrow, the gap
/// under the menu bar and a margin at the bottom), never under 200 pt. Without a screen, the lines' height.
public enum PanelSize {
    public static let margin: CGFloat = 60
    public static let minimum: CGFloat = 200
    public static func height(content: CGFloat, visible: CGFloat?) -> CGFloat {
        guard let visible else { return content }
        return min(content, max(minimum, visible - margin))
    }
}

extension RGBA {
    public var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    /// The colour for the panel's appearance: the token itself in dark, its light partner in light.
    public func ink(_ light: Bool) -> NSColor { light ? Tokens.light(self).ns : ns }
}

extension NSAppearance {
    /// True for the light appearances (aqua and its high contrast twin).
    public var isLight: Bool { bestMatch(from: [.aqua, .darkAqua]) == .aqua }
}

/// One VoiceOver element of the panel: a line of text, a control, or the group of a tab strip. Its frame is computed
/// from the view each time it is asked, so it stays right while the popover moves or grows.
/// AppKit calls these on the main thread, as it does every accessibility method of a view.
final class PanelElement: NSAccessibilityElement {
    nonisolated(unsafe) weak var view: LineView?
    nonisolated(unsafe) var rect: NSRect = .zero          // in the view's flipped coordinates
    nonisolated(unsafe) var control: Int? = nil           // index into the view's controls; nil for text and groups

    override func accessibilityFrame() -> NSRect {
        guard let v = view else { return .zero }
        let r = rect
        return MainActor.assumeIsolated {
            guard let w = v.window else { return .zero }
            return w.convertToScreen(v.convert(r, to: nil))
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let v = view, let c = control else { return false }
        return MainActor.assumeIsolated { v.press(c) }
    }

    override func isAccessibilityFocused() -> Bool {
        guard let v = view, let c = control else { return false }
        return MainActor.assumeIsolated { v.focus == c && v.window?.firstResponder === v }
    }

    override func setAccessibilityFocused(_ focused: Bool) {
        guard focused, let v = view, let c = control else { return }
        MainActor.assumeIsolated { v.setFocus(c, visible: true, announce: false) }
    }
}

/// Draws lines of SF Mono 12 on the glass: text runs, block bars with their track, the tab inversions,
/// row hover and the tooltip. Cells, not pixels: every piece advances by its cell count.
///
/// VoiceOver and the keyboard: every action is a control (Controls.extract), exposed as a button, a checkbox with its
/// state, or a tab with its selected state, each with a press action. The keyboard focus moves through the controls of
/// the tab in reading order with the up and down arrows, along a line (the tab strip, the section switch) with left and
/// right; Space and Return press the focused one. The focus ring is the style guide's: a 1 pt accent outline, 1 pt out.
@MainActor
public final class LineView: NSView {
    public static let lineHeight: CGFloat = 16
    public static let width: CGFloat = 380
    public let padTop: CGFloat = 12
    public let padSide: CGFloat = 10
    public let padBottom: CGFloat = 10

    public var lines: [Line] = [] {
        didSet { hoverLine = nil; hoverTip = nil; rebuildHits(); needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }
    /// The controls of the lines in reading order; the keyboard focus is an index into these.
    public private(set) var controls: [Control] = []
    /// The focused control, kept across renders by its key.
    public private(set) var focus: Int? = nil
    /// The ring shows once the keyboard moved the focus; a click hides it again.
    public private(set) var focusVisible = false
    var focusKey: String? = nil
    var elements: [String: PanelElement] = [:]
    /// The focused control's element, written on the main actor, read by AppKit's accessibility on the main thread.
    nonisolated(unsafe) var focusedElement: PanelElement? = nil
    /// The elements the VoiceOver pointer can land on, innermost first; written on the main actor.
    nonisolated(unsafe) var hitList: [PanelElement] = []
    public var onAction: ((Action) -> Void)?
    /// Snapshot mode: paint the draft's stage colour under the tint, since there is no desktop behind an offscreen view.
    public var drawsStage = false
    /// Debug snapshots only: another ground behind the tint, to measure contrast over a bright desktop (--snapshot-stage white).
    public static var stageOverride: RGBA? = nil
    /// Debug snapshots only: draw the light palette whatever the Mac is set to (--snapshot-light).
    public static var lightOverride: Bool? = nil
    /// The panel follows the Mac: light palette under a light appearance.
    var isLight: Bool { LineView.lightOverride ?? effectiveAppearance.isLight }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    let cellWidth: CGFloat
    let baseline: CGFloat
    let barTop: CGFloat
    let barHeight: CGFloat

    struct Hit { var rect: NSRect; var line: Int; var piece: Int }
    var hits: [Hit] = []
    var hoverLine: Int? = nil
    var hoverTip: (line: Int, piece: Int)? = nil
    var lineCache: [String: CTLine] = [:]

    public override var isFlipped: Bool { true }
    public var contentHeight: CGFloat { padTop + CGFloat(lines.count) * LineView.lineHeight + padBottom }

    public init() {
        let probe = NSAttributedString(string: "0", attributes: [.font: font])
        cellWidth = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(probe), nil, nil, nil)
        let ascent = font.ascender, descent = -font.descender
        baseline = (LineView.lineHeight - (ascent + descent)) / 2 + ascent
        // the block glyph's ink box inside the 16 pt line, measured from the font that renders it
        let ct = font as CTFont
        let s = String(Bar.full) as CFString
        let used = CTFontCreateForString(ct, s, CFRange(location: 0, length: 1))
        var chars = Array(String(Bar.full).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(used, &chars, &glyphs, chars.count)
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(used, .horizontal, &glyphs, &rect, 1)
        if rect.height > 0 {
            barTop = baseline - rect.maxY
            barHeight = rect.height
        } else {
            barTop = 3; barHeight = 12
        }
        super.init(frame: NSRect(x: 0, y: 0, width: LineView.width, height: 100))
        wantsLayer = false
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Usage")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: layout

    func lineY(_ i: Int) -> CGFloat { padTop + CGFloat(i) * LineView.lineHeight }

    func rebuildHits() {
        hits = []
        for (li, line) in lines.enumerated() {
            var x = padSide
            for (pi, p) in line.pieces.enumerated() {
                let w = CGFloat(p.cells) * cellWidth
                if p.action != nil || p.tip != nil {
                    hits.append(Hit(rect: NSRect(x: x, y: lineY(li), width: w, height: LineView.lineHeight), line: li, piece: pi))
                }
                x += w
            }
        }
        controls = Controls.extract(lines)
        // the focus follows its control through a render; a control that went keeps the place in the order
        if let k = focusKey {
            if let i = controls.firstIndex(where: { $0.key == k }) { focus = i }
            else if let f = focus, !controls.isEmpty { focus = min(f, controls.count - 1); focusKey = controls[focus!].key }
            else { focus = nil; focusKey = nil }
        }
        rebuildAccessibility()
    }

    func controlRect(_ c: Control) -> NSRect {
        NSRect(x: padSide + CGFloat(c.startCell) * cellWidth, y: lineY(c.line), width: CGFloat(c.cells) * cellWidth, height: LineView.lineHeight)
    }

    /// Elements are kept by key between renders, so VoiceOver's cursor stays where it was while the figures move.
    func element(_ key: String) -> PanelElement {
        if let e = elements[key] { return e }
        let e = PanelElement()
        e.view = self
        elements[key] = e
        return e
    }

    func rebuildAccessibility() {
        var used: [String: PanelElement] = [:]
        var children: [PanelElement] = []
        var changed: [PanelElement] = []
        let byLine = Dictionary(grouping: controls.indices, by: { controls[$0].line })
        for (li, line) in lines.enumerated() {
            let lineRect = NSRect(x: padSide, y: lineY(li), width: bounds.width - 2 * padSide, height: LineView.lineHeight)
            let idx = byLine[li] ?? []
            let actionable = idx.filter { controls[$0].kind != .figure }
            if actionable.isEmpty {
                // a line of text; a figure's readout is its help, and the keyboard can focus it. A hidden line is
                // decoration (the rule, grid cells) or said already by the line that labels its group.
                if line.hidden { continue }
                let text = line.label ?? line.plain.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                // keyed by its place and its visible words without figures, not by the spoken label: the Mac figures
                // change every 2 s, and a new element each time made VoiceOver lose its place and jump on
                let stable = line.image ? "image" : String(line.plain.filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces).prefix(24))
                let key = idx.first.map { "c|" + controls[$0].key } ?? "t|\(li)|\(stable)"
                let e = element(key)
                e.setAccessibilityRole(line.image ? .image : .staticText)
                e.setAccessibilityLabel(text)
                let help = idx.first.flatMap { controls[$0].help } ?? line.help
                e.setAccessibilityHelp(help?.isEmpty == true ? nil : help)
                e.setAccessibilityParent(self)
                e.rect = lineRect
                e.control = idx.first
                used[key] = e; children.append(e)
                continue
            }
            var parent: NSObject = self
            if actionable.count > 1, actionable.allSatisfy({ controls[$0].kind == .tab }) {
                // the tab strip and the section switch: a tab group around their tabs
                let key = "g|" + controls[actionable[0]].key
                let g = element(key)
                g.setAccessibilityRole(.tabGroup)
                if case .section = controls[actionable[0]].action { g.setAccessibilityLabel("Token sections") } else { g.setAccessibilityLabel("Tabs") }
                g.setAccessibilityParent(self)
                g.rect = lineRect
                g.control = nil
                used[key] = g; children.append(g)
                parent = g
            }
            var kids: [PanelElement] = []
            for ci in actionable {
                let c = controls[ci]
                let key = "c|" + c.key
                let e = element(key)
                let before = e.accessibilityValue() as? NSNumber
                switch c.kind {
                case .tab:
                    e.setAccessibilityRole(.radioButton)
                    e.setAccessibilitySubrole(.tabButtonSubrole)
                    e.setAccessibilityValue(NSNumber(value: c.checked == true ? 1 : 0))
                case .checkbox:
                    e.setAccessibilityRole(.checkBox)
                    e.setAccessibilitySubrole(nil)
                    e.setAccessibilityValue(NSNumber(value: c.checked == true ? 1 : 0))
                case .button, .figure:
                    e.setAccessibilityRole(.button)
                    e.setAccessibilitySubrole(nil)
                    e.setAccessibilityValue(nil)
                }
                e.setAccessibilityLabel(c.label)
                e.setAccessibilityHelp(c.help?.isEmpty == true ? nil : c.help)
                e.setAccessibilityParent(parent)
                e.rect = controlRect(c)
                e.control = ci
                if let b = before, let now = e.accessibilityValue() as? NSNumber, b != now { changed.append(e) }
                used[key] = e
                if parent === self { children.append(e) } else { kids.append(e) }
            }
            if let g = parent as? PanelElement { g.setAccessibilityChildren(kids) }
        }
        elements = used
        focusedElement = focus.flatMap { accessibilityElement(forControl: $0) }
        hitList = children.flatMap { e -> [PanelElement] in
            let kids = (e.accessibilityChildren() as? [PanelElement]) ?? []
            return kids + [e]   // a tab before its group, so the pointer lands on the tab
        }
        setAccessibilityChildren(children)
        for e in changed { NSAccessibility.post(element: e, notification: .valueChanged) }
    }

    /// The element of a control, for the tests and the focus notification.
    func accessibilityElement(forControl i: Int) -> PanelElement? { elements["c|" + controls[i].key] }

    // MARK: keyboard

    /// Presses a control: its action, as a click would. A figure has none.
    @discardableResult
    func press(_ i: Int) -> Bool {
        guard i >= 0, i < controls.count, let a = controls[i].action else { return false }
        onAction?(a)
        return true
    }

    func setFocus(_ i: Int?, visible: Bool, announce: Bool = true) {
        focus = i
        focusKey = i.map { controls[$0].key }
        focusVisible = visible && i != nil
        focusedElement = i.flatMap { accessibilityElement(forControl: $0) }
        if let i, controls[i].kind == .figure { hoverTip = tipPiece(of: controls[i]) } else if focusVisible { hoverTip = nil }
        // in a panel shorter than its lines, the focused control is scrolled into view, with a line of room around it
        if focusVisible, let i { scrollToVisible(controlRect(controls[i]).insetBy(dx: 0, dy: -LineView.lineHeight)) }
        needsDisplay = true
        if announce, let i, let e = accessibilityElement(forControl: i) {
            NSAccessibility.post(element: e, notification: .focusedUIElementChanged)
        }
    }

    /// Puts the focus on the control that runs this action (the selected tab after Tab, for one).
    public func focus(on action: Action, visible: Bool) {
        if let i = controls.firstIndex(where: { $0.action == action }) { setFocus(i, visible: visible) }
    }

    func tipPiece(of c: Control) -> (line: Int, piece: Int)? {
        var cell = 0
        for (pi, p) in lines[c.line].pieces.enumerated() {
            if cell == c.startCell, p.tip != nil { return (c.line, pi) }
            cell += p.cells
        }
        return nil
    }

    /// The focus keys: up and down through the tab's controls, left and right along a line. Returns whether it used the key.
    public func moveFocus(_ key: FocusKey) -> Bool {
        guard !controls.isEmpty else { return false }
        switch key {
        case .down, .up:
            let next: Int
            if let f = focus { next = key == .down ? min(f + 1, controls.count - 1) : max(f - 1, 0) }
            else { next = key == .down ? 0 : controls.count - 1 }
            setFocus(next, visible: true)
            return true
        case .left, .right:
            guard let f = focus else { return false }
            let line = controls[f].line
            let n = key == .right ? f + 1 : f - 1
            guard n >= 0, n < controls.count, controls[n].line == line else { return true }
            setFocus(n, visible: true)
            return true
        case .press:
            guard let f = focus else { return false }
            focusVisible = true
            press(f)
            return true
        }
    }

    public enum FocusKey: Sendable { case up, down, left, right, press }

    /// The key codes the panel reads for the focus: arrows, Space, Return and Enter.
    public static func focusKey(forKeyCode code: UInt16) -> FocusKey? {
        switch code {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 49, 36, 76: return .press
        default: return nil
        }
    }

    /// VoiceOver's pointer and the trackpad commander ask which element is under a screen point: the drawn line's.
    public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        let rects: [NSRect] = MainActor.assumeIsolated {
            guard let w = window else { return [] }
            return hitList.map { w.convertToScreen(convert($0.rect, to: nil)) }
        }
        if let i = rects.firstIndex(where: { $0.contains(point) }) { return hitList[i] }
        return super.accessibilityHitTest(point)
    }

    /// The element under a point in the view's own coordinates, for the tests.
    func element(atViewPoint p: NSPoint) -> PanelElement? { hitList.first { $0.rect.contains(p) } }

    public override var accessibilityFocusedUIElement: Any? {
        focusedElement ?? super.accessibilityFocusedUIElement
    }

    public override func resetCursorRects() {
        for h in hits where lines[h.line].pieces[h.piece].action != nil { addCursorRect(h.rect, cursor: .pointingHand) }
    }

    // MARK: drawing

    func ctLine(_ text: String, bold: Bool, color: RGBA) -> CTLine {
        let key = "\(isLight ? 1 : 0)\(bold ? 1 : 0)|\(color.r),\(color.g),\(color.b),\(color.a)|\(text)"
        if let l = lineCache[key] { return l }
        if lineCache.count > 4000 { lineCache.removeAll() }
        let attr = NSAttributedString(string: text, attributes: [.font: bold ? boldFont : font, .foregroundColor: color.ink(isLight)])
        let l = CTLineCreateWithAttributedString(attr)
        lineCache[key] = l
        return l
    }

    func drawRun(_ text: String, bold: Bool, color: RGBA, x: CGFloat, y: CGFloat, cells: Int, wide: Bool, ctx: CGContext) {
        guard !text.isEmpty else { return }
        let line = ctLine(text, bold: bold, color: color)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let expected = CGFloat(cells) * cellWidth
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if !wide && abs(width - expected) < 0.75 {
            ctx.textPosition = CGPoint(x: x, y: y + baseline)
            CTLineDraw(line, ctx)
        } else {
            // a glyph from another font: each one in its own cell box, left aligned
            let box = wide ? 2 * cellWidth : cellWidth
            var gx = x
            for ch in text {
                let gl = ctLine(String(ch), bold: bold, color: color)
                ctx.textPosition = CGPoint(x: gx, y: y + baseline)
                CTLineDraw(gl, ctx)
                gx += box
            }
        }
        ctx.restoreGState()
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if drawsStage {
            (LineView.stageOverride?.ns ?? Tokens.stage.ink(isLight)).setFill(); bounds.fill()
            Tokens.tint.ink(isLight).setFill(); bounds.fill()
        }
        for (li, line) in lines.enumerated() {
            let y = lineY(li)
            if hoverLine == li, line.hover {
                Tokens.selection.ink(isLight).setFill()
                NSRect(x: padSide, y: y, width: bounds.width - 2 * padSide, height: LineView.lineHeight).fill()
            }
            var x = padSide
            for p in line.pieces {
                let w = CGFloat(p.cells) * cellWidth
                if let bg = p.style.bg {
                    bg.ink(isLight).setFill(); NSRect(x: x, y: y, width: w, height: LineView.lineHeight).fill()
                }
                if let bar = p.bar {
                    drawBar(bar, x: x, y: y, ctx: ctx)
                } else {
                    drawRun(p.text, bold: p.style.bold, color: p.style.fg, x: x, y: y, cells: p.cells, wide: p.wide, ctx: ctx)
                }
                x += w
            }
        }
        if focusVisible, let f = focus, f < controls.count {
            // the style guide's ring: 1 pt accent outline, 1 pt outside the control
            let r = controlRect(controls[f]).insetBy(dx: -1.5, dy: -1.5)
            Tokens.accent.ink(isLight).setStroke()
            let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
        }
        if let (li, pi) = hoverTip, li < lines.count, pi < lines[li].pieces.count, let tip = lines[li].pieces[pi].tip {
            drawTip(tip, line: li, piece: pi, ctx: ctx)
        }
    }

    func drawBar(_ bar: BarRender, x: CGFloat, y: CGFloat, ctx: CGContext) {
        let top = y + barTop
        bar.trackColor.ink(isLight).setFill()
        for r in bar.track {
            NSRect(x: x + CGFloat(r.lowerBound) * cellWidth, y: top, width: CGFloat(r.count) * cellWidth, height: barHeight).fill()
        }
        // full cells run with their colour behind them too, so the hairline between blocks closes
        var i = 0
        while i < bar.cells.count {
            let c = bar.cells[i]
            if c.solid {
                var j = i
                while j < bar.cells.count, bar.cells[j].solid, bar.cells[j].color == c.color { j += 1 }
                c.color.ink(isLight).setFill()
                NSRect(x: x + CGFloat(i) * cellWidth, y: top, width: CGFloat(j - i) * cellWidth, height: barHeight).fill()
                i = j
            } else { i += 1 }
        }
        // the glyphs, as runs of one colour
        i = 0
        while i < bar.cells.count {
            let c = bar.cells[i]
            var j = i
            var run = ""
            while j < bar.cells.count, bar.cells[j].color == c.color { run.append(bar.cells[j].glyph); j += 1 }
            if run.trimmingCharacters(in: .whitespaces).isEmpty == false {
                drawRun(run, bold: false, color: c.color, x: x + CGFloat(i) * cellWidth, y: y, cells: j - i, wide: false, ctx: ctx)
            }
            i = j
        }
    }

    /// The cells a tooltip line may hold: the panel's width less the side padding and one cell of padding each side.
    var tipCells: Int { max(10, Int((bounds.width - 2 * padSide) / cellWidth) - 2) }

    /// A tooltip longer than the panel is wide breaks over lines at its double spaces (then at spaces), never cut.
    nonisolated public static func tipLines(_ tip: String, width: Int) -> [String] {
        guard tip.count > width else { return [tip] }
        var out: [String] = []
        var line = ""
        for part in tip.components(separatedBy: "  ") where !part.isEmpty {
            if line.isEmpty { line = part }
            else if line.count + 2 + part.count <= width { line += "  " + part }
            else { out.append(line); line = part }
        }
        if !line.isEmpty { out.append(line) }
        return out.flatMap { $0.count > width ? Format.wrap($0, width) : [$0] }
    }

    func drawTip(_ tip: String, line li: Int, piece pi: Int, ctx: CGContext) {
        let p = lines[li].pieces[pi]
        var px = padSide
        for k in 0..<pi { px += CGFloat(lines[li].pieces[k].cells) * cellWidth }
        let rows = LineView.tipLines(tip, width: tipCells)
        let cells = rows.map(\.count).max() ?? 0
        let w = CGFloat(cells + 2) * cellWidth
        let h = CGFloat(rows.count) * LineView.lineHeight
        var x = p.tipLeft ? padSide : px + CGFloat(p.cells) * cellWidth - w
        x = max(padSide, min(x, bounds.width - padSide - w))
        // above the line, inside the part of the panel in view: below the line when there is no room above it
        let above = lineY(li) - h - 2
        let y = above >= visibleRect.minY ? above : lineY(li) + LineView.lineHeight + 2
        Tokens.box.ink(isLight).setFill()
        NSRect(x: x, y: y, width: w, height: h).fill()
        for (k, row) in rows.enumerated() {
            drawRun(row, bold: false, color: Tokens.text, x: x + cellWidth, y: y + CGFloat(k) * LineView.lineHeight, cells: row.count, wide: false, ctx: ctx)
        }
    }

    // MARK: pointer

    func hit(at point: NSPoint) -> Hit? { hits.first { $0.rect.contains(point) } }

    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let li = Int((p.y - padTop) / LineView.lineHeight)
        let newLine: Int? = (li >= 0 && li < lines.count && lines[li].hover && p.x >= padSide && p.x <= bounds.width - padSide) ? li : nil
        var newTip: (Int, Int)? = nil
        if let h = hit(at: p), lines[h.line].pieces[h.piece].tip != nil { newTip = (h.line, h.piece) }
        if newLine != hoverLine || newTip?.0 != hoverTip?.line || newTip?.1 != hoverTip?.piece {
            hoverLine = newLine
            hoverTip = newTip.map { (line: $0.0, piece: $0.1) }
            needsDisplay = true
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if hoverLine != nil || hoverTip != nil { hoverLine = nil; hoverTip = nil; needsDisplay = true }
    }

    public override func mouseDown(with event: NSEvent) {
        if focusVisible { focusVisible = false; needsDisplay = true }
        let p = convert(event.locationInWindow, from: nil)
        if let h = hit(at: p), let a = lines[h.line].pieces[h.piece].action { onAction?(a) }
    }

    public override var acceptsFirstResponder: Bool { true }
}
