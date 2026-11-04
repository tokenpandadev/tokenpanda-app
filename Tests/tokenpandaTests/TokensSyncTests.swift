// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
@testable import Text
@testable import UI

/// The design system and the app hold one set of values. design/system/tokens.json is built by Style Dictionary into
/// Generated/DesignTokens.swift; these tests hold the token file, the generated Swift, Tokens.swift and the panel
/// measures against each other, so none of them can drift from the others.
struct TokensSyncTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every colour of Tokens.swift by its name. A token added there and not here fails tokensSwiftHasNoTokenTheSystemLacks.
    static let app: [String: RGBA] = [
        "text": Tokens.text, "bold": Tokens.bold, "dim": Tokens.dim, "dimmer": Tokens.dimmer, "quiet": Tokens.quiet,
        "accent": Tokens.accent, "track": Tokens.track, "trackStale": Tokens.trackStale, "coral": Tokens.coral,
        "warning": Tokens.warning, "box": Tokens.box, "selection": Tokens.selection, "inkOnAccent": Tokens.inkOnAccent,
        "inkOnBold": Tokens.inkOnBold, "white": Tokens.white, "tint": Tokens.tint, "stage": Tokens.stage,
        "magenta": Tokens.magenta, "yellow": Tokens.yellow, "cyan": Tokens.cyan, "green": Tokens.green,
        "blue": Tokens.blue, "blue2": Tokens.blue2, "procWhite": Tokens.procWhite,
    ]

    @Test func darkPaletteIsTheTokenTable() {
        #expect(Set(DesignTokens.darkByName.keys) == Set(Self.app.keys))
        for (name, value) in Self.app { #expect(DesignTokens.darkByName[name] == value, "dark \(name)") }
    }

    @Test func lightPaletteIsTheLightTable() {
        #expect(Set(DesignTokens.lightByName.keys) == Set(Self.app.keys))
        for (name, value) in Self.app { #expect(DesignTokens.lightByName[name] == Tokens.light(value), "light \(name)") }
        #expect(DesignTokens.Light.tint == Tokens.tintLight)
        #expect(DesignTokens.Light.stage == Tokens.stageLight)
        // every entry of the light table is the partner of a token in the system, and every token but the tint has one
        let darkHexes = Set(DesignTokens.darkByName.values.map(Self.hex))
        for key in Tokens.lightTable.keys { #expect(darkHexes.contains(key), "light table entry \(String(key, radix: 16)) has no token") }
        for (name, value) in DesignTokens.darkByName where name != "tint" {
            #expect(Tokens.lightTable[Self.hex(value)] != nil, "\(name) has no light partner")
        }
    }

    /// Reads Tokens.swift itself, so a colour added to the app without the token file fails here.
    @Test func tokensSwiftHasNoTokenTheSystemLacks() throws {
        let src = try String(contentsOf: Self.root.appendingPathComponent("Sources/Text/Tokens.swift"), encoding: .utf8)
        let rx = try NSRegularExpression(pattern: #"public static let (\w+) = RGBA\("#)
        let names = rx.matches(in: src, range: NSRange(src.startIndex..., in: src)).compactMap { Range($0.range(at: 1), in: src).map { String(src[$0]) } }
        #expect(names.count >= Self.app.count)
        for n in names {
            // tintLight and stageLight are the light mode of tint and stage
            let base = n.hasSuffix("Light") ? String(n.dropLast(5)) : n
            #expect(DesignTokens.darkByName[base] != nil, "Tokens.\(n) is not in design/system/tokens.json")
        }
    }

    /// The token file and the generated Swift agree: tokens.json was rebuilt after its last edit.
    @Test func generatedSwiftIsBuiltFromTheTokenFile() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("design/system/tokens.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let color = try #require(json["color"] as? [String: Any])
        for (mode, table) in [("dark", DesignTokens.darkByName), ("light", DesignTokens.lightByName)] {
            let group = try #require(color[mode] as? [String: Any])
            #expect(group.count == table.count, "\(mode) count")
            for (key, entry) in group {
                let value = try #require((entry as? [String: Any])?["$value"] as? [String: Any])
                let hexString = try #require(value["hex"] as? String)
                let rgb = try #require(UInt32(hexString.dropFirst(), radix: 16))
                let alpha = (value["alpha"] as? Double) ?? 1
                #expect(table[Self.swiftName(key)] == RGBA(hex: rgb, alpha: alpha), "\(mode) \(key)")
            }
        }
        let size = try #require(json["size"] as? [String: Any])
        #expect(Self.number(size["panel-width"]) == DesignTokens.Size.panelWidth)
        #expect(Self.number(size["line"]) == DesignTokens.Size.line)
        let cells = try #require(json["cells"] as? [String: Any])
        #expect((cells["popover"] as? [String: Any])?["$value"] as? Int == DesignTokens.Cells.popover)
    }

    @Test @MainActor func panelMeasuresAreTheViewsOwn() throws {
        let v = LineView()
        #expect(Double(LineView.width) == DesignTokens.Size.panelWidth)
        #expect(Double(LineView.lineHeight) == DesignTokens.Size.line)
        #expect(Double(v.padTop) == DesignTokens.Size.padTop)
        #expect(Double(v.padSide) == DesignTokens.Size.padSide)
        #expect(Double(v.padBottom) == DesignTokens.Size.padBottom)
        #expect(Double(PanelSize.margin) == DesignTokens.Size.screenMargin)
        #expect(Double(PanelSize.minimum) == DesignTokens.Size.panelMinimum)
        #expect(Double(v.font.pointSize) == DesignTokens.Font.sizeBody)
        #expect(Grammar.popCells == DesignTokens.Cells.popover)
        #expect(Grammar.popBar == DesignTokens.Cells.barWindow)
        #expect(Grammar.rowBar == DesignTokens.Cells.barRow)
        #expect(Grammar.weekBar == DesignTokens.Cells.barWeek)
        #expect(Grammar.memCols == DesignTokens.Cells.memoryColumns)
        #expect(Grammar.memRows == DesignTokens.Cells.memoryRows)
        // a table row: one space, the name column, one space, the bar, two spaces, the figure column
        let row = Grammar.row(RowView(name: "sample", hue: Tokens.blue, share: 50, figure: "1.2M", tip: "sample"))
        #expect(row.pieces.map(\.cells) == [1, DesignTokens.Cells.nameColumn, 1, DesignTokens.Cells.barRow, 2, DesignTokens.Cells.figureColumn])
        // the focus ring and the tooltip gap are literals in the drawing code
        let draw = try String(contentsOf: Self.root.appendingPathComponent("Sources/UI/LineView.swift"), encoding: .utf8)
        let o = Self.literal(DesignTokens.Size.focusOffset), w = Self.literal(DesignTokens.Size.focusRing), g = Self.literal(DesignTokens.Size.tipGap)
        #expect(draw.contains("insetBy(dx: -\(o), dy: -\(o))"))
        #expect(draw.contains("path.lineWidth = \(w)"))
        #expect(draw.contains("lineY(li) - h - \(g)"))
        #expect(draw.contains("lineY(li) + LineView.lineHeight + \(g)"))
    }

    @Test func itemMeasuresAreTheImagesOwn() throws {
        #expect(Double(ItemImage.height) == DesignTokens.Size.itemHeight)
        #expect(Double(ItemImage.gap) == DesignTokens.Size.itemGap)
        #expect(Double(ItemImage.cell) == DesignTokens.Size.itemCell)
        let src = try String(contentsOf: Self.root.appendingPathComponent("Sources/UI/ItemImage.swift"), encoding: .utf8)
        #expect(src.contains("monospacedDigitSystemFont(ofSize: \(Self.literal(DesignTokens.Font.sizeItem)), weight: st.over ? .semibold : .regular)"))
    }

    /// The chrome tokens are the stage of the style guide: docs/docs.css draws the strips and the banner with them.
    @Test func chromeIsTheStyleGuidesStage() throws {
        let css = try String(contentsOf: Self.root.appendingPathComponent("docs/docs.css"), encoding: .utf8)
        func rgba(_ c: RGBA) -> String {
            let a = String(format: "%g", c.a).replacingOccurrences(of: "0.", with: ".")
            return "rgba(\(Int((c.r * 255).rounded())),\(Int((c.g * 255).rounded())),\(Int((c.b * 255).rounded())),\(a))"
        }
        let C = DesignTokens.Chrome.self
        #expect(css.contains(".strip{") && css.contains("background:" + rgba(C.menubarDarkGround) + ";color:" + rgba(C.menubarDarkInk)))
        #expect(css.contains(".strip.light{background:" + rgba(C.menubarLightGround) + ";color:" + rgba(C.menubarLightInk)))
        #expect(css.contains("width:\(Self.literal(C.bannerWidth))px") && css.contains("border-radius:\(Self.literal(C.bannerRadius))px;background:" + rgba(C.bannerGround)))
        #expect(css.contains("0 0 0 1px " + rgba(C.bannerEdge)))
        #expect(css.contains("13px/\(Self.literal(C.bannerLine))px var(--sf);color:" + rgba(C.bannerTitle)))
        #expect(css.contains(".nb p{margin:1px 0 0;color:" + rgba(C.bannerBody)))
        #expect(css.contains(".nb time{font-size:\(Self.literal(DesignTokens.Font.sizeTime))px;color:" + rgba(C.bannerTime)))
    }

    static func hex(_ c: RGBA) -> UInt32 {
        // the three bytes do not overlap, so adding them is the same as or-ing them
        (UInt32((c.r * 255).rounded()) << 16) + (UInt32((c.g * 255).rounded()) << 8) + UInt32((c.b * 255).rounded())
    }

    /// "hue-proc-white" is procWhite, "ink-on-accent" is inkOnAccent: the rule of style-dictionary.config.js.
    static func swiftName(_ key: String) -> String {
        let k = key.hasPrefix("hue-") ? String(key.dropFirst(4)) : key
        let parts = k.split(separator: "-").map(String.init)
        return parts.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }.joined()
    }

    static func number(_ entry: Any?) -> Double? {
        ((entry as? [String: Any])?["$value"] as? [String: Any])?["value"] as? Double
    }

    static func literal(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
}
