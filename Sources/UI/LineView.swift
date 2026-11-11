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

    /// VoiceOver moves the keyboard focus with its cursor by setting this, on every element that allows it. A control
    /// takes the keyboard focus, scrolled into view; a text line or a group is scrolled into view, so the outline VoiceOver
    /// draws stays inside a capped panel. There is no public scroll to visible action an element can take: macOS 14 and
    /// 15 declare none, and 26 only through deprecated API (0.1.15, audit F-5; 0.1.14 scrolled for controls only).
    override func setAccessibilityFocused(_ focused: Bool) {
        guard focused, let v = view else { return }
        let r = rect, c = control
        MainActor.assumeIsolated {
            if let c { v.setFocus(c, visible: true, announce: false) } else { v.reveal(r) }
        }
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(setAccessibilityFocused(_:)) { return true }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}

/// Draws lines of SF Mono 12 on the glass: text runs, block bars with their track, the tab inversions,
/// row hover and the tooltip. Cells, not pixels: every piece advances by its cell count.
///
/// VoiceOver and the keyboard: every action is a control (Controls.extract), exposed as a button, a checkbox with its
/// state, a pop-up with its value, or a tab with its selected state, each with a press action. The keyboard focus moves through the controls of
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
                case .popUp:
                    e.setAccessibilityRole(.popUpButton)
                    e.setAccessibilitySubrole(nil)
                    e.setAccessibilityValue(c.value)
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
        if focusVisible, let i { reveal(controlRect(controls[i])) }
        needsDisplay = true
        if announce, let i, let e = accessibilityElement(forControl: i) {
            NSAccessibility.post(element: e, notification: .focusedUIElementChanged)
        }
    }

    /// Scrolls a rect of the lines into view with a line of room around it, in a panel shorter than its lines; a rect
    /// already in view does not move the panel.
    func reveal(_ r: NSRect) {
        scrollToVisible(r.insetBy(dx: 0, dy: -LineView.lineHeight))
    }

    /// Scrolls the panel by one line, down or up, within the lines: the line after the visible part comes into view, or
    /// the one before it. Nothing moves in a panel that shows all its lines.
    func scrollLine(down: Bool) {
        let v = visibleRect
        if down {
            let y = min(bounds.maxY, v.maxY + LineView.lineHeight)
            scrollToVisible(NSRect(x: v.minX, y: y - 1, width: 1, height: 1))
        } else {
            let y = max(bounds.minY, v.minY - LineView.lineHeight)
            scrollToVisible(NSRect(x: v.minX, y: y, width: 1, height: 1))
        }
    }

    /// Where the control that runs this action is drawn, in the view's coordinates: the pop-up's menu opens there.
    public func rect(of action: Action) -> NSRect? {
        controls.first { $0.action == action }.map(controlRect)
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
            // past the last control Down scrolls the panel on a line at a time, and before the first Up scrolls back to
            // the top, so in a panel shorter than its lines the keyboard reaches every line (0.1.19)
            if let f = focus, focusVisible {
                if key == .down, f == controls.count - 1 { scrollLine(down: true); return true }
                if key == .up, f == 0 { scrollLine(down: false); return true }
            }
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

    /// The box each character of a run is drawn in when the run is not drawn whole: its cells times the cell width, two
    /// cells for a wide character or an emoji, two for every glyph of a wide piece (the memory grid).
    func glyphBoxes(_ text: String, wide: Bool) -> [CGFloat] {
        text.map { CGFloat(wide ? 2 : Cells.width($0)) * cellWidth }
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
            // a glyph from another font: each one in its own box of cells, left aligned. A wide character or an emoji has
            // a box of two cells (0.1.19; one before, so CJK was squeezed and an emoji covered the next letter); a glyph
            // wider than its box is narrowed to it, never drawn over its neighbour.
            var gx = x
            for (ch, box) in zip(text, glyphBoxes(text, wide: wide)) {
                let gl = ctLine(String(ch), bold: bold, color: color)
                let gw = CTLineGetTypographicBounds(gl, nil, nil, nil)
                if gw > box + 0.5, gw > 0 {
                    ctx.saveGState()
                    ctx.translateBy(x: gx, y: 0)
                    ctx.scaleBy(x: box / gw, y: 1)
                    ctx.textPosition = CGPoint(x: 0, y: y + baseline)
                    CTLineDraw(gl, ctx)
                    ctx.restoreGState()
                } else {
                    // a wide character narrower than its two cells sits in their middle, as a terminal draws it
                    let inset = !wide && box > cellWidth * 1.5 ? max(0, (box - gw) / 2) : 0
                    ctx.textPosition = CGPoint(x: gx + inset, y: y + baseline)
                    CTLineDraw(gl, ctx)
                }
                gx += box
            }
        }
        ctx.restoreGState()
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // the device pixels of this drawing: 2 on a Retina screen and in the snapshots, from the context itself
        pixelScale = max(1, abs(ctx.userSpaceToDeviceSpaceTransform.a).rounded())
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
            // grounds first, one rect per run of pieces with the same ground on whole device pixels: the selected tab with
            // the warning dot is three pieces on one flat block, without seams at their joins (0.1.19)
            var gx = padSide
            var run: (start: CGFloat, end: CGFloat, color: RGBA)? = nil
            func flushGround() {
                if let r = run {
                    r.color.ink(isLight).setFill()
                    let a = snap(r.start), b = snap(r.end)
                    NSRect(x: a, y: y, width: b - a, height: LineView.lineHeight).fill()
                }
                run = nil
            }
            for p in line.pieces {
                let w = CGFloat(p.cells) * cellWidth
                if let bg = p.style.bg {
                    if let r = run, r.color == bg, abs(r.end - gx) < 0.01 { run?.end = gx + w } else { flushGround(); run = (gx, gx + w, bg) }
                } else { flushGround() }
                gx += w
            }
            flushGround()
            if let pr = pressed, pr.inside, let c = controls.first(where: { $0.key == pr.key }), c.line == li {
                // a control under a press that is still inside it: the accent at a quarter, until the button comes up
                Tokens.accent.with(alpha: 0.25).ink(isLight).setFill()
                let r = controlRect(c)
                NSRect(x: snap(r.minX), y: r.minY, width: snap(r.maxX) - snap(r.minX), height: r.height).fill()
            }
            var x = padSide
            for p in line.pieces {
                let w = CGFloat(p.cells) * cellWidth
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

    /// The device pixel scale: 2 on a Retina screen and in the snapshots.
    var pixelScale: CGFloat = 2

    /// A coordinate on the nearest device pixel edge, so two rects that meet leave no seam between them.
    func snap(_ v: CGFloat) -> CGFloat { (v * pixelScale).rounded() / pixelScale }

    /// The part of a cell a bar glyph covers, as a fraction from the cell's left edge: a full block, an eighth block (the
    /// left n eighths) or a half of the notch. nil for a space or a glyph not of the bar grammar.
    nonisolated static func coverage(_ g: Character) -> (from: Double, to: Double)? {
        if g == Bar.full { return (0, 1) }
        if g == Bar.notchLeft { return (0.5, 1) }   // ▐ the right half
        if let n = Bar.eighths.firstIndex(of: g), n > 0 { return (0, Double(n) / 8) }   // ▌ is four eighths: the left half
        return nil
    }

    /// The bar as rects on whole device pixels, one height for every cell: the track, then each run of one colour. The
    /// eighth blocks and the notch halves are drawn as the parts of the cell their glyphs cover, at the full block's top
    /// and bottom, so the last cell of a fill has no step and the joins inside a fill no hairline (0.1.19; the glyphs of
    /// the last cell sat one device pixel short, and a coral run met the accent on a fractional point).
    func drawBar(_ bar: BarRender, x: CGFloat, y: CGFloat, ctx: CGContext) {
        let top = snap(y + barTop), bottom = snap(y + barTop + barHeight)
        func fill(_ a: CGFloat, _ b: CGFloat) {
            let l = snap(a), r = snap(b)
            if r > l { NSRect(x: l, y: top, width: r - l, height: bottom - top).fill() }
        }
        bar.trackColor.ink(isLight).setFill()
        for r in bar.track { fill(x + CGFloat(r.lowerBound) * cellWidth, x + CGFloat(r.upperBound) * cellWidth) }
        // each cell on its own: two cells that meet share one snapped edge, so no seam shows between them
        for (i, c) in bar.cells.enumerated() {
            guard let cov = LineView.coverage(c.glyph) else { continue }
            c.color.ink(isLight).setFill()
            fill(x + (CGFloat(i) + CGFloat(cov.from)) * cellWidth, x + (CGFloat(i) + CGFloat(cov.to)) * cellWidth)
        }
    }

    /// The cells a tooltip line may hold: the panel's width less the side padding and one cell of padding each side.
    var tipCells: Int { max(10, Int((bounds.width - 2 * padSide) / cellWidth) - 2) }

    /// A tooltip longer than the panel is wide breaks over lines at its double spaces (then at spaces), never cut.
    nonisolated public static func tipLines(_ tip: String, width: Int) -> [String] {
        guard Cells.width(tip) > width else { return [tip] }
        var out: [String] = []
        var line = ""
        for part in tip.components(separatedBy: "  ") where !part.isEmpty {
            if line.isEmpty { line = part }
            else if Cells.width(line) + 2 + Cells.width(part) <= width { line += "  " + part }
            else { out.append(line); line = part }
        }
        if !line.isEmpty { out.append(line) }
        return out.flatMap { Cells.width($0) > width ? Format.wrap($0, width) : [$0] }
    }

    func drawTip(_ tip: String, line li: Int, piece pi: Int, ctx: CGContext) {
        let p = lines[li].pieces[pi]
        var px = padSide
        for k in 0..<pi { px += CGFloat(lines[li].pieces[k].cells) * cellWidth }
        let rows = LineView.tipLines(tip, width: tipCells)
        let cells = rows.map { Cells.width($0) }.max() ?? 0
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
            drawRun(row, bold: false, color: Tokens.text, x: x + cellWidth, y: y + CGFloat(k) * LineView.lineHeight, cells: Cells.width(row), wide: false, ctx: ctx)
        }
    }

    // MARK: pointer

    func hit(at point: NSPoint) -> Hit? { hits.first { $0.rect.contains(point) } }

    public override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    /// The pointer over a point of the view: the row under it highlights, and a row with a readout shows its tooltip
    /// wherever the pointer is on the row, name, bar or figure (0.1.19; only over the figure before).
    func pointerMoved(to p: NSPoint) {
        let li = Int(((p.y - padTop) / LineView.lineHeight).rounded(.down))
        let newLine: Int? = (li >= 0 && li < lines.count && lines[li].hover && p.x >= padSide && p.x <= bounds.width - padSide) ? li : nil
        var newTip: (Int, Int)? = nil
        if let h = hit(at: p), lines[h.line].pieces[h.piece].tip != nil { newTip = (h.line, h.piece) }
        else if let l = newLine, let pi = lines[l].pieces.firstIndex(where: { $0.tip != nil }) { newTip = (l, pi) }
        if newLine != hoverLine || newTip?.0 != hoverTip?.line || newTip?.1 != hoverTip?.piece {
            hoverLine = newLine
            hoverTip = newTip.map { (line: $0.0, piece: $0.1) }
            needsDisplay = true
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if hoverLine != nil || hoverTip != nil { hoverLine = nil; hoverTip = nil; needsDisplay = true }
    }

    /// The control with an action under a point, by its stable key.
    func controlKey(at p: NSPoint) -> String? {
        controls.first { $0.action != nil && controlRect($0).contains(p) }?.key
    }

    /// A press in progress: the control it started on, and whether the pointer is still inside it.
    var pressed: (key: String, inside: Bool)? = nil

    public override func mouseDown(with event: NSEvent) { pointerDown(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseDragged(with event: NSEvent) { pointerDragged(to: convert(event.locationInWindow, from: nil)) }
    public override func mouseUp(with event: NSEvent) { pointerUp(at: convert(event.locationInWindow, from: nil)) }

    /// A control acts when the button comes up inside it, as a macOS button does: the press shows on it while the pointer
    /// stays inside, and dragging off before letting go cancels it, so Remove, Install and Quit can be taken back (0.1.19;
    /// they acted on the press before).
    func pointerDown(at p: NSPoint) {
        if focusVisible { focusVisible = false }
        pressed = controlKey(at: p).map { ($0, true) }
        needsDisplay = true
    }

    func pointerDragged(to p: NSPoint) {
        guard let pr = pressed else { return }
        let inside = controlKey(at: p) == pr.key
        if inside != pr.inside { pressed = (pr.key, inside); needsDisplay = true }
    }

    func pointerUp(at p: NSPoint) {
        guard let pr = pressed else { return }
        pressed = nil
        needsDisplay = true
        guard controlKey(at: p) == pr.key, let c = controls.first(where: { $0.key == pr.key }), let a = c.action else { return }
        onAction?(a)
    }

    public override var acceptsFirstResponder: Bool { true }
}
