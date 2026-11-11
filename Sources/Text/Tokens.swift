// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The token table of the style guide, section 1. One job per hex.
import Foundation

public struct RGBA: Sendable, Hashable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xff) / 255; g = Double((hex >> 8) & 0xff) / 255; b = Double(hex & 0xff) / 255; a = alpha
    }
    public func with(alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }
}

public enum Tokens {
    public static let text = RGBA(hex: 0xe0e0e0)      // default text, the percent, figures
    public static let bold = RGBA(hex: 0xededed)      // section titles, the status word, the notch mark
    public static let dim = RGBA(hex: 0xb3b3b3)       // reset line, pace lines, captions, header line, chips: 4.5 to 1 or more even over a white desktop
    public static let dimmer = RGBA(hex: 0x949494)    // free cells in the memory grid: 3 to 1 even over white (0.1.14, was 888888)
    public static let quiet = RGBA(hex: 0xb8b8b8)     // key hints in the foot: 4.5 to 1 or more even over a white desktop
    public static let accent = RGBA(hex: 0xb1b9f9)    // used fill, selected tab, the rule
    // the bar behind the fill. Back at its 0.1.18 value in 0.1.19 (chosen on 11.11): the lifted 65698d reached 3 to 1 on the
    // glass but cut the accent fill to 2.8 and the coral over pace segment to 1.7 against it; here they keep 4.0 and 2.4
    public static let track = RGBA(hex: 0x505370)
    public static let trackStale = RGBA(hex: 0x505370, alpha: 0.35)
    // the fill of a stale bar: 3 to 1 or more on its faint track (0.1.19; it was the track colour itself, 1.7 to 1.9)
    public static let staleFill = RGBA(hex: 0x7e82b0)
    public static let coral = RGBA(hex: 0xd77757)     // the fill past the tick when over pace
    public static let warning = RGBA(hex: 0xffc107)   // the hit mark, swap cells, the Mac warning dot
    // the Mac warning dot on the selected tab's accent ground: the light warning, 3.8 to 1 there (0.1.19; the warning
    // itself is 1.15 to 1 on the accent)
    public static let warningOnAccent = RGBA(hex: 0x7a4e00)
    public static let box = RGBA(hex: 0x373737)       // the tooltip ground
    public static let selection = RGBA(r: 39 / 255, g: 61 / 255, b: 76 / 255) // row hover
    public static let inkOnAccent = RGBA(hex: 0x000000)
    public static let inkOnBold = RGBA(hex: 0x191d27)
    public static let white = RGBA(hex: 0xffffff)
    public static let tint = RGBA(r: 25 / 255, g: 29 / 255, b: 39 / 255, a: 0.82)
    public static let stage = RGBA(hex: 0x0e1120)     // the draft's ground behind the glass, for snapshots only

    // Hues from the terminal's ANSI palette
    public static let magenta = RGBA(hex: 0xbd7bcd)   // Fable
    public static let yellow = RGBA(hex: 0xc4ac62)    // Opus
    public static let cyan = RGBA(hex: 0x7ccbcd)      // Sonnet
    public static let green = RGBA(hex: 0x6caa71)     // Haiku
    public static let blue = RGBA(hex: 0x6d96b4)      // projects
    public static let blue2 = RGBA(hex: 0x67b5ed)     // sessions
    public static let procWhite = RGBA(hex: 0xdee5eb) // processes
    // the unused hues of the profile in palette order, for a model family not in the table (0.1.19). Red and bright red
    // are banned; black and bright black are greys, not hues; bright blue is the sessions' and bright white too near
    // the process white
    public static let brightGreen = RGBA(hex: 0x79be7e)
    public static let brightYellow = RGBA(hex: 0xe5c872)
    public static let brightMagenta = RGBA(hex: 0xd389e5)
    public static let brightCyan = RGBA(hex: 0x84dde0)
    public static let spare: [RGBA] = [brightGreen, brightYellow, brightMagenta, brightCyan]

    /// The hue of a model family in the table, nil for any other.
    public static func knownHue(forFamily family: String) -> RGBA? {
        switch family.lowercased() {
        case "fable": return magenta
        case "opus": return yellow
        case "sonnet": return cyan
        case "haiku": return green
        default: return nil
        }
    }

    /// The hue of a model family. A family not in the table takes the first unused hue of the palette.
    public static func hue(forFamily family: String) -> RGBA { knownHue(forFamily: family) ?? spare[0] }

    /// Two hues closer than this (CIE76 colour difference in CIELAB, sRGB with a D65 white) read as one in a bar.
    public static let closeHue = 20.0

    /// The CIE76 colour difference of two colours: the distance of their CIELAB values.
    public static func difference(_ a: RGBA, _ b: RGBA) -> Double {
        func lab(_ c: RGBA) -> (Double, Double, Double) {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let r = lin(c.r), g = lin(c.g), b = lin(c.b)
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let p = lab(a), q = lab(b)
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }

    /// The hues of several families at once: the known ones from the table, each other family the next unused hue of
    /// the palette in the order they come, so two unknown families do not share one (style guide section 1).
    /// Each spare hue is the bright twin of one family's hue, so a spare closer than `closeHue` to a hue already on the
    /// screen (a family in the list, or a spare given to an earlier unknown family) is skipped: with Opus in the list an
    /// unknown family never takes the bright yellow (0.1.19). When every unused spare is that close (all four families
    /// in the list), the next unused spare in palette order is taken, as before.
    public static func hues(forFamilies families: [String]) -> [String: RGBA] {
        var out: [String: RGBA] = [:]
        let known = families.compactMap { knownHue(forFamily: $0) }
        var taken: [RGBA] = []
        for f in families where out[f.lowercased()] == nil {
            if let h = knownHue(forFamily: f) { out[f.lowercased()] = h; continue }
            let unused = spare.filter { !taken.contains($0) }
            let inUse = known + taken
            let far = unused.first { s in inUse.allSatisfy { difference(s, $0) >= closeHue } }
            let h = far ?? unused.first ?? spare[taken.count % spare.count]
            out[f.lowercased()] = h
            taken.append(h)
        }
        return out
    }
}

/// Light mode (0.1.11): the panel follows the Mac's appearance. The lines keep the dark tokens above; at draw time
/// each one is swapped for its light partner here, so one table holds the whole light palette. Alpha is kept.
extension Tokens {
    public static let tintLight = RGBA(r: 250 / 255, g: 250 / 255, b: 252 / 255, a: 0.82)
    public static let stageLight = RGBA(hex: 0xe6e8ef) // the light draft's ground behind the glass, for snapshots only

    static let lightTable: [UInt32: UInt32] = [
        0xe0e0e0: 0x1d1d1f, // text
        0xededed: 0x000000, // bold
        0xb3b3b3: 0x505055, // dim
        0x949494: 0x6e6e73, // dimmer
        0xb8b8b8: 0x525257, // quiet
        0xb1b9f9: 0x3b46b8, // accent
        0x505370: 0x9ea4c8, // track, track when stale: shows over a white and a black desktop, the fill stays 3 to 1 from it
        0x7e82b0: 0x70748e, // the stale fill: 3 to 1 on its faint track (0.1.19)
        0xd77757: 0xb9502e, // coral
        0xffc107: 0x7a4e00, // warning
        0x7a4e00: 0xffc107, // the warning dot on the selected tab: the dark warning on the light accent, 4.7 to 1
        0x373737: 0xe4e4e8, // box
        0x273d4c: 0xd6e4f0, // selection
        0x000000: 0xffffff, // ink on the accent
        0x191d27: 0xffffff, // ink on bold
        0xffffff: 0x000000, // white
        0x0e1120: 0xe6e8ef, // stage
        0xbd7bcd: 0x8e3fa3, // magenta, Fable
        0xc4ac62: 0x8a6d00, // yellow, Opus
        0x7ccbcd: 0x00757a, // cyan, Sonnet
        0x6caa71: 0x2e7d32, // green, Haiku
        0x6d96b4: 0x2f5f86, // blue, projects
        0x67b5ed: 0x1a6fb0, // blue2, sessions
        0xdee5eb: 0x3a3f45, // process white
        0x79be7e: 0x25704a, // bright green, a family not in the table
        0xe5c872: 0x7a5d00, // bright yellow
        0xd389e5: 0x7b2f94, // bright magenta
        0x84dde0: 0x006469, // bright cyan
    ]

    /// The light partner of a dark token. A colour not in the table is returned as it is.
    public static func light(_ c: RGBA) -> RGBA {
        if c == tint { return tintLight }
        let hex = (UInt32((c.r * 255).rounded()) << 16) | (UInt32((c.g * 255).rounded()) << 8) | UInt32((c.b * 255).rounded())
        guard let l = lightTable[hex] else { return c }
        return RGBA(hex: l, alpha: c.a)
    }
}

public struct Style: Sendable, Hashable {
    public var fg: RGBA
    public var bg: RGBA?
    public var bold: Bool
    public init(fg: RGBA, bg: RGBA? = nil, bold: Bool = false) { self.fg = fg; self.bg = bg; self.bold = bold }

    public static let text = Style(fg: Tokens.text)
    public static let bold = Style(fg: Tokens.bold, bold: true)
    public static let dim = Style(fg: Tokens.dim)
    public static let dimmer = Style(fg: Tokens.dimmer)
    public static let quiet = Style(fg: Tokens.quiet)
    public static let accent = Style(fg: Tokens.accent)
    public static let warning = Style(fg: Tokens.warning)
    public static let tabSelected = Style(fg: Tokens.inkOnAccent, bg: Tokens.accent, bold: true)
    public static let subSelected = Style(fg: Tokens.inkOnBold, bg: Tokens.bold, bold: true)
}
