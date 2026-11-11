// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

// The bar grammar of the style guide, section 5, as the approved popover draws it:
// full cells plus one eighth block, the notch mark at the elapsed share.

public struct BarOptions: Sendable {
    public var color: RGBA?     // the fill hue of a row bar
    public var over: Bool       // coral from the tick on
    public var stale: Bool      // fill in the track colour, track at 35%, mark dim
    public var plain: Bool      // no track
    public init(color: RGBA? = nil, over: Bool = false, stale: Bool = false, plain: Bool = false) {
        self.color = color; self.over = over; self.stale = stale; self.plain = plain
    }
}

public enum Bar {
    public static let eighths: [Character] = [" ", "\u{258F}", "\u{258E}", "\u{258D}", "\u{258C}", "\u{258B}", "\u{258A}", "\u{2589}"]
    public static let full: Character = "\u{2588}"
    public static let notchLeft: Character = "\u{2590}"   // ▐ on the cell before the tick
    public static let notchRight: Character = "\u{258C}"  // ▌ on the tick cell

    public struct Fill: Sendable, Equatable {
        public var fullCells: Int
        public var eighths: Int   // 0 to 8; 8 means the last cell is a full block too
        public init(fullCells: Int, eighths: Int) { self.fullCells = fullCells; self.eighths = eighths }
        public var cellsDrawn: Int { fullCells + (eighths > 0 ? 1 : 0) }
    }

    /// f = U / 100 * N, full cells floor(f), then round((f - floor(f)) * 8) eighths.
    public static func fill(width n: Int, used u: Double) -> Fill {
        let clamped = min(max(u, 0), 100)
        let f = clamped / 100 * Double(n)
        let fullCells = Int(f.rounded(.down))
        let e8 = Int(((f - Double(fullCells)) * 8).rounded())
        return Fill(fullCells: min(fullCells, n), eighths: fullCells >= n ? 0 : e8)
    }

    /// The glyph per cell, without the mark.
    public static func glyphs(width n: Int, used u: Double) -> [Character] {
        let f = fill(width: n, used: u)
        return (0..<n).map { i in
            if i < f.fullCells { return full }
            if i == f.fullCells { return f.eighths == 8 ? full : eighths[f.eighths] }
            return " "
        }
    }

    /// The mark stands at cell round(E / 100 * N), never past N - 1 and never before cell 1 (the notch needs the cell before it).
    public static func tick(width n: Int, elapsed e: Double) -> Int {
        max(1, min(n - 1, Int((e / 100 * Double(n)).rounded())))
    }

    public static func render(width n: Int, used u: Double, elapsed e: Double?, options o: BarOptions = BarOptions()) -> BarRender {
        let base = glyphs(width: n, used: u)
        let t = e.map { tick(width: n, elapsed: $0) }
        let fillColor = o.color ?? (o.stale ? Tokens.staleFill : Tokens.accent)
        let pastColor = (o.over && !o.stale) ? Tokens.coral : fillColor
        let markColor = o.stale ? Tokens.dim : Tokens.bold
        var cells: [BarCell] = []
        for i in 0..<n {
            if let t, i == t - 1 || i == t {
                cells.append(BarCell(glyph: i == t - 1 ? notchLeft : notchRight, color: markColor, solid: false))
            } else {
                let color = i >= (t ?? n) ? pastColor : fillColor
                cells.append(BarCell(glyph: base[i], color: color, solid: base[i] == full))
            }
        }
        var track: [Range<Int>] = []
        if !o.plain {
            if let t {
                if t - 1 > 0 { track.append(0..<(t - 1)) }
                if t + 1 < n { track.append((t + 1)..<n) }
            } else {
                track.append(0..<n)
            }
        }
        return BarRender(width: n, cells: cells, track: track,
                         trackColor: o.stale ? Tokens.trackStale : Tokens.track, plain: o.plain, tick: t)
    }
}

public enum Format {
    /// Text broken into lines of at most w cells at spaces, never cut: a word longer than w is split. Text that fits stays
    /// as it is, double spaces and all; a break eats the spaces at it. Double spaces part the figures of a line, so a break
    /// falls there first, and a figure stays whole when it fits a line of its own. Widths are cells: a wide character
    /// counts two (0.1.19).
    public static func wrap(_ s: String, _ w: Int) -> [String] {
        guard Cells.width(s) > w else { return [s] }
        let parts = s.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count > 1 else { return wrapWords(s, w) }
        var out: [String] = []
        var line = ""
        for part in parts {
            if line.isEmpty { line = part }
            else if Cells.width(line) + 2 + Cells.width(part) <= w { line += "  " + part; continue }
            else { out.append(line.trimmingCharacters(in: .whitespaces)); line = part }
            if Cells.width(line) > w {
                let rows = wrapWords(line, w)
                out += rows.dropLast()
                line = rows.last ?? ""
            }
        }
        if !line.isEmpty { out.append(line.trimmingCharacters(in: .whitespaces)) }
        return out
    }

    private static func wrapWords(_ s: String, _ w: Int) -> [String] {
        guard Cells.width(s) > w else { return [s] }
        var out: [String] = []
        var line = ""
        for word in s.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            var word = word
            while Cells.width(word) > w {
                if !line.isEmpty { out.append(line); line = "" }
                var head = Cells.prefix(word, w)
                if head.isEmpty { head = String(word.prefix(1)) }   // one character wider than the line: it stands alone
                out.append(head); word = String(word.dropFirst(head.count))
            }
            if line.isEmpty { line = word }
            else if Cells.width(line) + 1 + Cells.width(word) <= w { line += " " + word }
            else { out.append(line.trimmingCharacters(in: .whitespaces)); line = word }
        }
        line = line.trimmingCharacters(in: .whitespaces)
        if !line.isEmpty { out.append(line) }
        return out.filter { !$0.isEmpty }
    }

    /// A name cut to a column: what fits in w - 1 cells and the ellipsis, padded to w cells.
    public static func col(_ s: String, _ w: Int) -> String {
        let c = cut(s, w)
        return c + String(repeating: " ", count: max(0, w - Cells.width(c)))
    }

    /// A text cut to w cells with the ellipsis, not padded.
    public static func cut(_ s: String, _ w: Int) -> String {
        guard w > 0 else { return "" }
        guard Cells.width(s) > w else { return s }
        return Cells.prefix(s, w - 1) + "\u{2026}"
    }

    public static func rcol(_ s: String, _ w: Int) -> String {
        let c = Cells.width(s)
        if c >= w { return s }
        return String(repeating: " ", count: w - c) + s
    }

    /// The units of a token figure, in order.
    static let units: [(div: Double, suffix: String)] = [(1e3, "k"), (1e6, "M"), (1e9, "B"), (1e12, "T")]

    /// One figure in one unit: k and M with one decimal under 100 and none from 100 up, B and T with two decimals.
    /// nil when the figure rounds to 1000 or more in that unit: then it takes the next one.
    static func inUnit(_ d: Double, _ u: Int) -> String? {
        let v = d / units[u].div
        let s = units[u].suffix
        if u >= 2 {
            if (v * 100).rounded() / 100 < 1000 || u == units.count - 1 { return String(format: "%.2f", v) + s }
            return nil
        }
        if (v * 10).rounded() / 10 < 100 { return String(format: "%.1f", v) + s }
        if v.rounded() < 1000 { return String(format: "%.0f", v) + s }
        return nil
    }

    /// Tokens: "72.4M", "1.02B", "31.2M", "100k". The unit is picked after rounding, so 99,960 is "100k" (never
    /// "100.0k"), 999,950 is "1.0M" (never "1000k") and 999,999,999 is "1.00B" (never "1000M") (0.1.19).
    public static func tokens(_ n: Int) -> String {
        if n < 1000 { return String(n) }
        let d = Double(n)
        for u in units.indices { if let s = inUnit(d, u) { return s } }
        return String(n)
    }

    /// A column of figures shares one unit, set by its largest: "1.02B" above "0.71B", never "710M". The unit is the
    /// one the largest figure takes after rounding.
    public enum TokenScale: Sendable { case trillions, billions, millions, thousands, units }
    public static func tokenScale(_ n: Int) -> TokenScale {
        if n < 1000 { return .units }
        let d = Double(n)
        for u in units.indices where inUnit(d, u) != nil { return [TokenScale.thousands, .millions, .billions, .trillions][u] }
        return .trillions
    }
    public static func tokens(_ n: Int, scale: TokenScale) -> String {
        let u: Int
        switch scale {
        case .units: return String(n)
        case .thousands: u = 0
        case .millions: u = 1
        case .billions: u = 2
        case .trillions: u = 3
        }
        if n <= 0 { return String(n) }
        let d = Double(n)
        let v = d / units[u].div
        let s = units[u].suffix
        // a small group in a column of large ones never reads 0.00B or 0.0M beside its bar
        if u >= 2 {
            if (v * 100).rounded() == 0 { return "<0.01" + s }
            return String(format: "%.2f", v) + s
        }
        if (v * 10).rounded() == 0 { return "<0.1" + s }
        return (v * 10).rounded() / 10 < 100 ? String(format: "%.1f", v) + s : String(format: "%.0f", v) + s
    }

    /// Context figures: "405.6k", "88.4k", "1.2M"; the window size without a decimal: "1M", "200k". A figure that rounds
    /// to 1000 in its unit takes the next one: 999,960 is "1M", never "1000k" (0.1.19).
    public static func contextTokens(_ n: Int, decimal: Bool = true) -> String {
        let d = Double(n)
        if d < 1e3 { return String(n) }
        for (i, u) in [(1e3, "k"), (1e6, "M")].enumerated() {
            let v = d / u.0
            let last = i == 1
            if decimal {
                let r = (v * 10).rounded() / 10
                if r < 1000 || last { return trim(String(format: "%.1f", v) + u.1) }
            } else if v.rounded() < 1000 || last {
                return String(format: "%.0f", v) + u.1
            }
        }
        return String(n)
    }

    private static func trim(_ s: String) -> String { s.replacingOccurrences(of: ".0", with: "") }

    /// The used percent as the panel writes it: rounded, but never 100 before the window is full. 99.5 reads 99 while a
    /// projection still runs; only a raw 100 reads 100 (0.1.19).
    public static func percentUsed(_ u: Double) -> Int {
        u >= 100 ? Int(u.rounded()) : min(99, Int(u.rounded()))
    }

    /// A process's CPU: "6.1%", and without the decimal from 100% up, so "123%" and "1000%" stay in the column (0.1.19).
    public static func cpu(_ p: Double) -> String {
        (p * 10).rounded() / 10 >= 100 ? String(format: "%.0f%%", p) : String(format: "%.1f%%", p)
    }

    /// "USD 1,140" for the chip; "USD 38.20" in a tooltip.
    public static func usd(_ v: Double, cents: Bool) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = cents ? 2 : 0
        f.maximumFractionDigits = cents ? 2 : 0
        f.usesGroupingSeparator = true
        return "USD " + (f.string(from: NSNumber(value: v)) ?? String(format: cents ? "%.2f" : "%.0f", v))
    }

    public static func gb(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", Double(bytes) / 1_073_741_824)
    }
}
