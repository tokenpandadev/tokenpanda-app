// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The token table of the style guide, section 1. One job per hex.

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
    public static let dimmer = RGBA(hex: 0x888888)    // free cells in the memory grid
    public static let quiet = RGBA(hex: 0xb8b8b8)     // key hints in the foot: 4.5 to 1 or more even over a white desktop
    public static let accent = RGBA(hex: 0xb1b9f9)    // used fill, selected tab, the rule
    public static let track = RGBA(hex: 0x505370)     // the bar behind the fill; the fill when stale
    public static let trackStale = RGBA(hex: 0x505370, alpha: 0.35)
    public static let coral = RGBA(hex: 0xd77757)     // the fill past the tick when over pace
    public static let warning = RGBA(hex: 0xffc107)   // the hit mark, swap cells, the Mac warning dot
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

    /// The hue of a model family. A family not in the table takes the process white: the sheet
    /// names "the next unused ANSI hue" but gives no value for it, so nothing is guessed.
    public static func hue(forFamily family: String) -> RGBA {
        switch family.lowercased() {
        case "fable": return magenta
        case "opus": return yellow
        case "sonnet": return cyan
        case "haiku": return green
        default: return procWhite
        }
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
        0x888888: 0x6e6e73, // dimmer
        0xb8b8b8: 0x525257, // quiet
        0xb1b9f9: 0x3b46b8, // accent
        0x505370: 0x9ea4c8, // track, track when stale: shows over a white and a black desktop, the fill stays 3 to 1 from it
        0xd77757: 0xb9502e, // coral
        0xffc107: 0x7a4e00, // warning
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
