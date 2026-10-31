// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// A line of the popover is a run of pieces. Everything the app draws is a line of these.

public enum Action: Sendable, Hashable {
    case tab(Int)
    case section(Int)
    case toggle(String)
    case install
    case uninstall
    case quit
}

public struct BarCell: Sendable, Hashable {
    public var glyph: Character
    public var color: RGBA
    public var solid: Bool   // a full block: paint the cell ground in the fill colour too, so SF Mono's hairline closes
}

public struct BarRender: Sendable, Hashable {
    public var width: Int
    public var cells: [BarCell]
    public var track: [Range<Int>]   // cell ranges that carry the track ground
    public var trackColor: RGBA
    public var plain: Bool           // no track (a row bar)
    public var tick: Int?            // the cell the mark stands on, for the tests and the labels

    public var glyphs: String { String(cells.map(\.glyph)) }
}

public struct Piece: Sendable {
    public var text: String
    public var style: Style
    public var cells: Int
    public var wide: Bool          // each glyph sits in a 2 cell box (the memory grid glyphs)
    public var action: Action?
    public var tip: String?
    public var tipLeft: Bool
    public var bar: BarRender?
    public var checked: Bool?      // a tab or a checkbox: its selected or checked state; nil for a plain button
    public var label: String?      // the spoken name of the control this piece belongs to, when it differs from its text

    public init(_ text: String, _ style: Style = .text, cells: Int? = nil, wide: Bool = false,
                action: Action? = nil, tip: String? = nil, tipLeft: Bool = false, bar: BarRender? = nil,
                checked: Bool? = nil, label: String? = nil) {
        self.text = text; self.style = style; self.wide = wide; self.action = action
        self.tip = tip; self.tipLeft = tipLeft; self.bar = bar; self.checked = checked; self.label = label
        self.cells = cells ?? (wide ? text.count * 2 : text.count)
    }

    public static func bar(_ b: BarRender) -> Piece { Piece(b.glyphs, .text, cells: b.width, bar: b) }
}

public struct Line: Sendable {
    public var pieces: [Piece]
    public var hover: Bool          // highlights across the full width under the pointer
    public var label: String?       // the accessibility label of the line, when it differs from its text
    public var help: String?        // the accessibility help of the line's control: the dim line under a checkbox

    public init(_ pieces: [Piece] = [], hover: Bool = false, label: String? = nil, help: String? = nil) {
        self.pieces = pieces; self.hover = hover; self.label = label; self.help = help
    }

    /// The line as plain text: bars become their glyph runs. Used by the golden tests.
    public var plain: String { pieces.map(\.text).joined() }
    public var cells: Int { pieces.reduce(0) { $0 + $1.cells } }
}

/// What a control is to VoiceOver and the keyboard.
public enum ControlKind: Sendable, Equatable {
    case tab        // a tab of the tab strip or the section switch, with its selected state
    case checkbox   // a setting, with its checked state
    case button     // Install, Remove, Quit, the Login Items note
    case figure     // a figure with a readout: focusable, shows its tooltip, does nothing on Space
}

/// One control of the panel: the pieces of a line that share an action, or a figure with a tooltip.
/// The keyboard focus moves through these in reading order; VoiceOver gets one element for each.
public struct Control: Sendable, Equatable {
    public var kind: ControlKind
    public var action: Action?
    public var label: String
    public var checked: Bool?
    public var help: String?
    public var line: Int
    public var startCell: Int
    public var cells: Int
    /// Stable across renders for the same control: the action, or the figure's line text, and its ordinal among equals.
    public var key: String

    public static func == (a: Control, b: Control) -> Bool {
        a.kind == b.kind && a.action == b.action && a.label == b.label && a.checked == b.checked && a.help == b.help
            && a.line == b.line && a.startCell == b.startCell && a.cells == b.cells && a.key == b.key
    }
}

public enum Controls {
    /// The controls of the lines in reading order: top to bottom, left to right.
    public static func extract(_ lines: [Line]) -> [Control] {
        var out: [Control] = []
        var seen: [String: Int] = [:]
        func key(_ base: String) -> String {
            let n = seen[base, default: 0]; seen[base] = n + 1
            return "\(base)#\(n)"
        }
        for (li, line) in lines.enumerated() {
            var cell = 0
            var i = 0
            let ps = line.pieces
            while i < ps.count {
                let p = ps[i]
                if let a = p.action {
                    var j = i, cells = 0, text = ""
                    while j < ps.count, ps[j].action == a { cells += ps[j].cells; text += ps[j].text; j += 1 }
                    let kind: ControlKind
                    switch a {
                    case .tab, .section: kind = .tab
                    case .toggle: kind = p.checked == nil ? .button : .checkbox
                    case .install, .uninstall, .quit: kind = .button
                    }
                    let label = p.label ?? line.label ?? text.trimmingCharacters(in: .whitespaces)
                    out.append(Control(kind: kind, action: a, label: label, checked: p.checked, help: p.tip ?? line.help,
                                       line: li, startCell: cell, cells: cells, key: key("\(a)")))
                    cell += cells
                    i = j
                    continue
                }
                if let tip = p.tip {
                    let label = line.label ?? line.plain.trimmingCharacters(in: .whitespaces)
                    out.append(Control(kind: .figure, action: nil, label: label, checked: nil, help: tip,
                                       line: li, startCell: cell, cells: p.cells, key: key("figure|" + (label.split(separator: ",").first.map(String.init) ?? label))))
                }
                cell += p.cells
                i += 1
            }
        }
        return out
    }
}
