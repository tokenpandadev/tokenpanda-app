// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// How many terminal cells a text takes. A wide character (East Asian Wide or Fullwidth: CJK, kana, Hangul, fullwidth
// forms) and an emoji take two cells, as a terminal draws them; everything else one. Every width in the panel is
// measured with this: Piece.cells, the name cuts, Format.col and the fallback draw of LineView (0.1.19).

public enum Cells {
    /// The East Asian Wide and Fullwidth ranges of Unicode 15 (EastAsianWidth.txt, W and F), folded to ranges.
    static let wide: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2329...0x232A, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
        0xA000...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F,
        0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x16FE0...0x16FE4, 0x17000...0x18CFF, 0x1AFF0...0x1B2FF, 0x1F200...0x1F2FF,
        0x20000...0x2FFFD, 0x30000...0x3FFFD,
    ]

    /// The cells of one character (a grapheme cluster): two when it is wide or shows as an emoji, else one.
    public static func width(_ ch: Character) -> Int {
        let scalars = ch.unicodeScalars
        guard let first = scalars.first else { return 0 }
        // asked to show as an emoji by the variation selector U+FE0F, or a keycap (U+20E3): two cells, also for a first
        // scalar under U+1100 (1 and # of a keycap, copyright and registered), which the fast path below counted one
        // until the second review of 0.1.19
        if scalars.contains(where: { $0.value == 0xFE0F || $0.value == 0x20E3 }) { return 2 }
        if first.value < 0x1100 { return 1 }   // Latin, Greek, Cyrillic and the rest: one cell, the fast path
        // an emoji shown as an emoji by default
        if first.properties.isEmojiPresentation { return 2 }
        let v = first.value
        for r in wide where r.contains(v) { return 2 }
        return 1
    }

    /// The cells of a text.
    public static func width(_ s: String) -> Int {
        var n = 0
        for ch in s { n += width(ch) }
        return n
    }

    /// The longest start of a text that fits in w cells.
    public static func prefix(_ s: String, _ w: Int) -> String {
        var out = "", n = 0
        for ch in s {
            let c = width(ch)
            if n + c > w { break }
            out.append(ch); n += c
        }
        return out
    }
}
