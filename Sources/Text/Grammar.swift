// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The line renderer: one function per component of the style guide, copied from the approved popover draft.
// Nothing here is reinterpreted; a change to the sheet is a change here.
import Foundation

/// What VoiceOver says where the panel abbreviates: weekdays and months in full, token figures in words, a
/// countdown in units. "Sun 18:00" is "Sunday 18:00", "1.02B" is "1.02 billion", "in 3d 3h" is "in 3 days 3 hours".
public enum Spoken {
    static let days = ["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
    static let months = ["Jan": "January", "Feb": "February", "Mar": "March", "Apr": "April", "May": "May", "Jun": "June", "Jul": "July",
                         "Aug": "August", "Sep": "September", "Oct": "October", "Nov": "November", "Dec": "December"]

    public static func words(_ s: String) -> String {
        s.replacingOccurrences(of: "  ", with: ", ").split(separator: " ", omittingEmptySubsequences: false).map { t -> String in
            var tok = String(t), tail = ""
            if let last = tok.last, ",.)".contains(last) { tail = String(last); tok.removeLast() }
            if let d = days[tok] ?? months[tok] { return d + tail }
            if tok == "USD" { return "US dollars" + tail }
            if let u = tok.last, "BMk".contains(u), tok.count > 1, Double(tok.dropLast()) != nil {
                return tok.dropLast() + (u == "B" ? " billion" : u == "M" ? " million" : " thousand") + tail
            }
            return tok + tail
        }.joined(separator: " ")
    }

    /// "in 3d 3h" and "in 2h 15m" in units.
    public static func countdown(_ s: String) -> String {
        s.split(separator: " ").map { t -> String in
            guard let u = t.last, "dhm".contains(u), let n = Int(t.dropLast()) else { return String(t) }
            let unit = u == "d" ? "day" : u == "h" ? "hour" : "minute"
            return "\(n) \(unit)\(n == 1 ? "" : "s")"
        }.joined(separator: " ")
    }

    /// "Weekly (all models)" as "Weekly, all models".
    public static func title(_ s: String) -> String { s.replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "") }

    /// "[list price equivalent  USD 1,140]" as "list price equivalent, 1,140 US dollars".
    public static func chip(_ s: String) -> String {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let r = t.range(of: "USD ") {
            let after = t[r.upperBound...]
            let amount = after.prefix { $0.isNumber || $0 == "," || $0 == "." }
            t = t[..<r.lowerBound] + amount + " US dollars" + after.dropFirst(amount.count)
        }
        return t.replacingOccurrences(of: "  ", with: ", ")
    }
}

public enum Grammar {
    public static let notificationsOff = "Notifications are off in System Settings"

    /// The window that says the app runs while its menu bar icon is not visible. From macOS 26 an app's icon can be
    /// switched off in System Settings, Menu Bar, and a button opens that pane; before, only Apple's own items have a
    /// switch (Control Center), so the text names a full menu bar first and has no button. The notch is named only on a
    /// Mac with one (0.1.14 named it on every Mac), both causes when it is not known (notch nil), and every text names a
    /// menu bar manager, which the check also catches (0.1.15, audit F-1; wording approved 2026-11-04).
    public static func hiddenIconHint(switchInSettings: Bool, notch: Bool?) -> (title: String, text: String, button: String?) {
        let title = "tokenpanda is running"
        let manager = "an app that hides menu bar icons, such as Bartender or Ice"
        if switchInSettings {
            let full: String
            switch notch {
            case true?: full = "hidden behind the notch when the menu bar is full"
            case false?: full = "left out when the menu bar is full"
            case nil: full = "left out or hidden behind the notch when the menu bar is full"
            }
            return (title, "Its icon is not visible in the menu bar. It may be switched off in System Settings, Menu Bar, \(full), or kept out of view by \(manager).",
                    "Open Menu Bar Settings")
        }
        let cause: String
        switch notch {
        case true?: cause = "the menu bar is full and the icon is hidden behind the notch"
        case false?: cause = "the menu bar is full"
        case nil: cause = "the menu bar is full and the icon is left out or hidden behind the notch"
        }
        return (title, "Its icon is not visible in the menu bar, most likely because \(cause). Quitting another menu bar app makes room for it. "
                    + "An app that hides menu bar icons, such as Bartender or Ice, can also keep it out of view.", nil)
    }

    /// Whether the hidden icon window names the notch (spec 20.3.0): the screen whose menu bar holds the item, when the
    /// item's window has a screen (true when that screen has a notch); otherwise no notch when no connected screen has
    /// one, and nil, not known, when some screen has one.
    public static func notch(itemScreen: Bool?, anyScreen: Bool) -> Bool? {
        if let itemScreen { return itemScreen }
        return anyScreen ? nil : false
    }
    public static let popCells = 47      // content cells in the 380 pt popover at SF Mono 12
    public static let popBar = 36        // the window bar
    public static let rowBar = 24
    public static let weekBar = 20
    public static let memCols = 20
    public static let memRows = 10

    static let blank = Line()
    static func L(_ pieces: Piece...) -> Line { Line(pieces) }
    static func sp(_ s: String, _ st: Style = .text) -> Piece { Piece(s, st) }

    // 6.1 header line and tab strip
    public static func header(line: String, tab sel: Int, warn: Bool) -> [Line] {
        var tabs: [Piece] = []
        for (i, name) in ["Claude", "Mac", "Settings"].enumerated() {
            if i > 0 { tabs.append(sp("  ")) }
            let style: Style = i == sel ? .tabSelected : .text
            if name == "Mac" && warn {
                tabs.append(Piece(" Mac ", style, action: .tab(i), checked: i == sel, label: "Mac, warning"))
                tabs.append(Piece("\u{25CF}", Style(fg: Tokens.warning, bg: style.bg), action: .tab(i), checked: i == sel, label: "Mac, warning"))
                tabs.append(Piece(" ", style, action: .tab(i), checked: i == sel, label: "Mac, warning"))
            } else {
                tabs.append(Piece(" \(name) ", style, action: .tab(i), checked: i == sel, label: name))
            }
        }
        return [
            L(sp(" "), sp(line, .dim)),
            L(sp(String(repeating: "\u{2594}", count: popCells + 1), .accent)).silent,
            Line([sp(" ")] + tabs),
        ]
    }

    static func percentPiece(_ used: Double, dim: Bool) -> Piece {
        sp(" \(Int(used.rounded()))% used", dim ? .dim : .text)
    }

    // 6.3 window section
    public static func windowSection(_ w: WindowView) -> [Line] {
        var out: [Line] = [L(sp(" "), sp(w.title, .bold))]
        switch w.mode {
        case .live(let p):
            let bar = Bar.render(width: popBar, used: w.used, elapsed: p.elapsed, options: BarOptions(over: p.over))
            out.append(L(sp(" "), .bar(bar), percentPiece(w.used, dim: false)))
            out.append(L(sp(" "), sp(p.reset + "  " + p.countdown, .dim)))
            if let proj = p.projection {
                out.append(L(sp(" "), sp(p.status, .bold), sp("  " + proj, .dim)))
            } else {
                out.append(L(sp(" "), sp(p.status, .bold)))
            }
            out.append(L(sp(" "), sp(p.allowance, .dim)))
        case .stale(let asOf, let reset, let e):
            let bar = Bar.render(width: popBar, used: w.used, elapsed: e, options: BarOptions(stale: true))
            out.append(L(sp(" "), .bar(bar), percentPiece(w.used, dim: true)))
            out.append(L(sp(" "), sp(reset, .dim)))
            out.append(L(sp(" "), sp("as of " + asOf, .dim)))
        case .resetPassed(let reset):
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))))
            out.append(L(sp(" "), sp(reset + "  no session since", .dim)))
        case .nextReply(let reset):
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))))
            out.append(L(sp(" "), sp(reset + "  new window on the next reply", .dim)))
        case .absent:
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))))
            out.append(L(sp(" "), sp("not in the last feed", .dim)))
        case .quiet:
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: w.used, elapsed: nil, options: BarOptions(stale: true))), percentPiece(w.used, dim: true)))
            out.append(L(sp(" "), sp("not in the last feed", .dim)))
        case .unknown:
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: w.used, elapsed: nil)), percentPiece(w.used, dim: true)))
            out.append(L(sp(" "), sp("unknown window", .dim)))
        }
        return spoken(out, label: windowLabel(w), focusable: true)
    }

    /// The style guide's one label per window section: "Weekly, all models. 61% used. Resets Sunday 18:00, in 3 days
    /// 3 hours. Over pace, limit Sunday 01:20 at this rate. 0.5% an hour left."
    public static func windowLabel(_ w: WindowView) -> String {
        let pct = "\(Int(w.used.rounded()))% used"
        var parts = [Spoken.title(w.title)]
        switch w.mode {
        case .live(let p):
            parts += [pct, Spoken.words(p.reset) + ", " + Spoken.countdown(p.countdown),
                      p.projection.map { p.status + ", " + Spoken.words($0) } ?? p.status, p.allowance]
        case .stale(let asOf, let reset, _): parts += [pct, Spoken.words(reset) + ", as of " + asOf]
        case .resetPassed(let reset): parts += [Spoken.words(reset) + ", no session since"]
        case .nextReply(let reset): parts += [Spoken.words(reset) + ", new window on the next reply"]
        case .absent: parts += ["not in the last feed"]
        case .quiet: parts += [pct, "not in the last feed"]
        case .unknown: parts += [pct, "unknown window"]
        }
        return parts.joined(separator: ". ") + "."
    }

    /// A group of lines said once: the first line carries the label, the rest are hidden.
    static func spoken(_ lines: [Line], label: String, focusable: Bool = false) -> [Line] {
        guard var first = lines.first else { return lines }
        first.label = label
        first.focusable = focusable
        return [first] + lines.dropFirst().map(\.silent)
    }

    static func privacy() -> [Line] {
        spoken([L(sp(" "), sp("This app makes no network calls. Usage comes", .dim)),
                L(sp(" "), sp("from Claude Code's own status feed on this Mac.", .dim))],
               label: "This app makes no network calls. Usage comes from Claude Code's own status feed on this Mac.")
    }

    static func windowEmpty(_ title: String, _ line: String) -> [Line] {
        spoken([L(sp(" "), sp(title, .bold)),
                L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))),
                L(sp(" "), sp(line, .dim))], label: Spoken.title(title) + ". " + line.replacingOccurrences(of: "  ", with: ", ") + ".", focusable: true)
    }

    // the empty and first run states of the approved draft
    public static func limits(_ v: LimitsView) -> [Line] {
        switch v {
        case .windows(let ws, let staleNote):
            var out: [Line] = []
            for (i, w) in ws.enumerated() {
                if i > 0 { out.append(blank) }
                out += windowSection(w)
            }
            if staleNote {
                // one sentence for VoiceOver, said once, not as two broken lines
                out += spoken([L(sp(" "), sp("limits are shared with the Claude app and other", .dim)),
                               L(sp(" "), sp("Macs, so the real figure may be higher", .dim))],
                              label: "limits are shared with the Claude app and other Macs, so the real figure may be higher")
            }
            return out
        case .noHook(let previous, let slowerRefresh, let error, let targets):
            var out: [Line] = [
                L(sp(" "), sp("Weekly and 5h window", .bold)),
                L(sp(" "), sp("needs Claude Code's status line feed", .dim)),
            ]
            if targets.count <= 1 {
                out += dimLines("one statusLine entry in \(targets.first ?? "~/.claude")/settings.json", indent: 1)
            } else {
                out.append(L(sp(" "), sp("one statusLine entry in the settings.json of", .dim)))
                for t in targets { out += dimLines(t, indent: 3) }
            }
            out.append(L(sp(" "), sp(previous == nil ? "chained if one exists" : "your current status line is kept and chained", .dim)))
            if slowerRefresh { out.append(L(sp(" "), sp(refreshLine, .dim))) }
            out.append(L(sp(" "), Piece(" Install the status line entry ", .tabSelected, action: .install, label: "Install the status line entry")))
            if let error { out += dimLines(error, indent: 1) }
            out.append(blank)
            out += privacy()
            return out
        case .noSession:
            return windowEmpty("Weekly (all models)", "no session yet  open Claude Code once") + [blank]
                + windowEmpty("5h window", "no session yet  open Claude Code once")
        case .firstReply:
            return windowEmpty("Weekly (all models)", "waiting for the first reply") + [blank]
                + windowEmpty("5h window", "waiting for the first reply")
        case .noLimits:
            return [L(sp(" "), sp("Weekly and 5h window", .bold)),
                    L(sp(" "), sp("these sessions carry no plan limits", .dim))]
        case .hooksDisabled:
            return [L(sp(" "), sp("Weekly and 5h window", .bold)),
                    L(sp(" "), sp("disableAllHooks is on in settings.json", .dim)),
                    L(sp(" "), sp("so Claude Code runs no status line", .dim))]
        case .formatChanged:
            return [L(sp(" "), sp("Weekly and 5h window", .bold)),
                    L(sp(" "), sp("the feed format changed, update tokenpanda", .dim))]
        }
    }

    // 6.14 open sessions, as the draft draws them: two lines per session
    public static func sessionRows(_ list: [SessionView], more: Int) -> [Line] {
        var out: [Line] = [L(sp(" "), sp("Open sessions", .bold))]
        if list.isEmpty {
            out.append(L(sp(" "), sp("no open session", .dim)))
            return out
        }
        for s in list {
            // the name and model are in the figure line's label; said once, there. A waiting session has no figure line
            // with a label, so its name line stays.
            // a long session name is cut so name and model stay on one line inside the panel
            let room = max(8, popCells - 2 - s.model.count)
            let name = s.name.count > room ? String(s.name.prefix(room - 1)) + "\u{2026}" : s.name
            let nameLine = L(sp(" "), sp(name), sp("  "), sp(s.model, .dim))
            out.append(s.waiting ? nameLine : nameLine.silent)
            let bar = Bar.render(width: rowBar, used: s.waiting ? 0 : Double(s.used), elapsed: nil, options: BarOptions(color: s.hue, plain: true))
            if s.waiting {
                // no figure yet: the words take the bar's place, so they fit the width
                let words = s.compacted ? "compacted or resumed  next reply updates it" : "waiting for the first reply"
                out.append(Line([sp(" "), sp(words, .dim)], hover: true))
            } else {
                let fig = Piece(s.figure + "  " + Format.rcol("\(s.used)%", 3), .text, tip: s.tip, tipLeft: true)
                out.append(Line([sp(" "), .bar(bar), sp("  "), fig], hover: true,
                                label: "\(s.name), \(s.model), context \(Spoken.words(s.figure)), \(s.used)% used"))
            }
        }
        if more > 0 { out.append(L(sp(" "), sp("and \(more) more", .dim))) }
        return out
    }

    // 6.5 table row
    public static func row(_ r: RowView) -> Line {
        let bar = Bar.render(width: rowBar, used: Double(r.share), elapsed: nil, options: BarOptions(color: r.hue, plain: true))
        let fig = Piece(Format.rcol(r.figure, 5), .text, tip: r.tip)
        // the readout is in the label, so it is not said a second time as help
        return Line([sp(" "), sp(Format.col(r.name, 14)), sp(" "), .bar(bar), sp("  "), fig], hover: true,
                    label: "\(r.name), " + Spoken.words(r.tip), help: "")
    }

    // 6.6 section switch
    public static func subTabs(_ sel: Int) -> Line {
        var pieces: [Piece] = [sp(" ")]
        for (i, name) in ["Models", "Projects", "Sessions"].enumerated() {
            if i > 0 { pieces.append(sp("  ")) }
            pieces.append(Piece(" \(name) ", i == sel ? .subSelected : .text, action: .section(i), checked: i == sel, label: name))
        }
        return Line(pieces)
    }

    public static func tokens(_ t: TokensView) -> [Line] {
        let title = ["Tokens by model  7 days", "Tokens by project  7 days", "Tokens by session  today"][t.section]
        var out: [Line] = [L(sp(" "), sp(title, .bold)), subTabs(t.section)]
        if let empty = t.empty {
            out.append(L(sp(" "), sp(empty, .dim)))
            if let e = t.errorLine { out.append(L(sp(" "), sp(Format.col(e, popCells - 1).trimmingCharacters(in: .whitespaces), .dim))) }
            return out
        }
        let list = t.rows[t.section]
        if list.isEmpty {
            out.append(L(sp(" "), sp(t.section == 2 ? "no session today" : "nothing in the last 7 days", .dim)))
        }
        for r in list { out.append(row(r)) }
        // a chip longer than the panel ("[list price equivalent  USD 0.63  one model unpriced]") wraps at its double
        // spaces and is still read as one line (0.1.18; cut off at the panel's edge since 0.1.17 showed cents)
        for chip in [t.priceChip, t.agentChip].compactMap({ $0 }) {
            out += spoken(Format.wrap(chip, popCells - 1).map { L(sp(" "), sp($0, .dim)) }, label: Spoken.chip(chip))
        }
        return out
    }

    // 6.8 weeks
    public static func week(_ w: WeekView) -> Line {
        var pieces: [Piece] = [sp(" "), sp(Format.col(w.date, 6)), sp("  ")]
        if let used = w.used {
            let bar = Bar.render(width: weekBar, used: Double(used), elapsed: w.elapsed, options: BarOptions(over: w.over))
            pieces.append(.bar(bar))
            pieces.append(w.hit ? Piece("\u{26A0}", .warning, cells: 1) : sp(" "))
            pieces.append(sp(" " + Format.rcol("\(used)%", 4)))
        } else {
            pieces.append(.bar(Bar.render(width: weekBar, used: 0, elapsed: nil)))
            pieces.append(sp("  "))
        }
        if let note = w.note { pieces.append(sp("  " + note, .dim)) }
        // "Week of 28 September, 100%, hit the limit Thursday 16:10"
        var label = "Week of " + Spoken.words(w.date) + ", " + (w.used.map { "\($0)%" } ?? "no figure")
        if let note = w.note { label += ", " + (w.hit ? "hit the limit " : "") + Spoken.words(note) }
        var line = Line(pieces, label: label)
        line.focusable = true   // the Down key stops on each week too
        return line
    }

    // 6.9 memory grid
    public static func memGrid(_ m: MemView) -> [Line] {
        let total = memCols * memRows
        var out: [Line] = []
        for r in 0..<memRows {
            var pieces: [Piece] = [sp(" ")]
            var runGlyph = ""
            var runStyle: Style = .accent
            func flush() { if !runGlyph.isEmpty { pieces.append(Piece(runGlyph, runStyle, wide: true)); runGlyph = "" } }
            for c in 0..<memCols {
                let i = r * memCols + c
                let (g, st): (String, Style) = i < m.usedCells ? ("\u{26C1}", .accent) : i >= total - m.swapCells ? ("\u{26DD}", .warning) : ("\u{26F6}", .dimmer)
                if st != runStyle { flush(); runStyle = st }
                runGlyph += g
            }
            flush()
            out.append(Line(pieces))
        }
        out.append(L(sp(" "), Piece("\u{26C1}", .accent, wide: true), sp("Used "), sp(m.usedLine, .dim)))
        out.append(L(sp(" "), Piece("\u{26F6}", .dimmer, wide: true), sp("Free "), sp(m.freeLine, .dim)))
        out.append(L(sp(" "), Piece("\u{26DD}", .warning, wide: true), sp("Swap "), sp(m.swapLine, .dim), sp("   "), sp("Pressure " + m.pressure, .dim)))
        // one image with a description; the cells and the legend glyphs are hidden
        out = out.map(\.silent)
        out[0].hidden = false
        out[0].image = true
        out[0].label = memoryLabel(m)
        out[0].focusable = true
        return out
    }

    /// "Memory 25.5 of 36 gigabytes, 71%, free 10.5 gigabytes, swap 0.9 gigabytes, pressure normal"
    public static func memoryLabel(_ m: MemView) -> String {
        let used = m.usedLine.replacingOccurrences(of: " GB (", with: " gigabytes, ").replacingOccurrences(of: ")", with: "")
        func gb(_ s: String) -> String { s.replacingOccurrences(of: " GB", with: " gigabytes") }
        return "Memory \(used), free \(gb(m.freeLine)), swap \(gb(m.swapLine)), pressure \(m.pressure)"
    }

    // 6.10 checkbox rows
    /// A checkbox row: the box and the label are one control, checked or not; the dim lines under it are its help.
    public static func cbRow(_ key: String, _ label: String, _ on: Bool, _ sub: String?, indent: String = " ", more: [String] = []) -> [Line] {
        let subs = [sub].compactMap { $0 } + more
        // the notifications note is a link of its own (below), so it is not also the checkbox's help: said once
        let help = subs.filter { $0 != notificationsOff }
        var out = [Line([sp(indent), Piece(on ? "[x]" : "[ ]", .text, action: .toggle(key), checked: on, label: label),
                         Piece(" " + label, .text, action: .toggle(key), checked: on, label: label)],
                        hover: true, label: label, help: help.isEmpty ? nil : help.joined(separator: ", "))]
        // the dim lines are the checkbox's help: said once, as help, not again as text. The notifications note is the one
        // exception: a link that opens the setting, so it is a control of its own.
        for sub in subs {
            if sub == notificationsOff {
                let pad = String(repeating: " ", count: indent.count + 4)
                out.append(Line([sp(pad), Piece(sub, .accent, action: .openNotificationSettings, label: sub + ", open System Settings")],
                                hover: true, label: sub + ", open System Settings"))
            } else {
                out += dimLines(sub, indent: indent.count + 4).map(\.silent)
            }
        }
        return out
    }

    /// Dim text at an indent, wrapped at spaces to the rule's width (popCells + 1, as the header rule) instead of cut at the edge.
    public static func dimLines(_ text: String, indent: Int) -> [Line] {
        // VoiceOver reads the text once, whole, on its first line
        spoken(Format.wrap(text, popCells + 1 - indent).map { L(sp(String(repeating: " ", count: indent)), sp($0, .dim)) }, label: text)
    }

    /// The key hints. m, p and s switch the token sections, so they are named only on the Claude tab, where they work.
    public static func foot(tab: Int) -> [Line] {
        [blank, L(sp(" "), sp(tab == 0 ? "Esc closes  Tab switches  m p s sections" : "Esc closes  Tab switches", .quiet))]
    }

    public static func claudeTab(_ c: ClaudeTab) -> [Line] {
        var out = limits(c.limits) + [blank]
        if case .noHook = c.limits {} else {
            out += sessionRows(c.sessions, more: c.moreSessions) + [blank]
        }
        out += tokens(c.tokens)
        out.append(blank)
        out.append(L(sp(" "), sp("Week over week", .bold)))
        if c.weeks.isEmpty { out.append(L(sp(" "), sp("no week recorded yet", .dim))) }
        for w in c.weeks { out.append(week(w)) }
        return out
    }

    public static func macTab(_ m: MacTab) -> [Line] {
        func c(_ t: String) -> String { t.replacingOccurrences(of: "  ", with: ", ") }
        var out: [Line] = spoken([L(sp(" "), sp("CPU", .bold)),
                                  L(sp(" "), .bar(Bar.render(width: popBar, used: Double(m.cpu), elapsed: nil)), sp(" \(m.cpu)%")),
                                  L(sp(" "), sp(m.cpuLine, .dim))], label: "CPU \(m.cpu)%, " + c(m.cpuLine), focusable: true)
        if let gpu = m.gpu {
            out.append(blank)
            out += spoken([L(sp(" "), sp("GPU", .bold)),
                           L(sp(" "), .bar(Bar.render(width: popBar, used: Double(gpu), elapsed: nil)), sp(" \(gpu)%")),
                           L(sp(" "), sp("device utilisation", .dim))], label: "GPU \(gpu)%, device utilisation", focusable: true)
        }
        if let mem = m.memory {
            out.append(blank)
            // the title is in the image's description ("Memory 25.5 of 36 gigabytes, ..."), so it is not said twice
            out.append(L(sp(" "), sp("Memory", .bold)).silent)
            out += memGrid(mem)
        }
        if let b = m.battery {
            out.append(blank)
            out += spoken([L(sp(" "), sp("Battery", .bold)),
                           L(sp(" "), .bar(Bar.render(width: popBar, used: Double(b.percent), elapsed: nil)), sp(" \(b.percent)%")),
                           L(sp(" "), sp(b.line1, .dim))] + (b.line2.isEmpty ? [] : Format.wrap(b.line2, popCells - 1).map { L(sp(" "), sp($0, .dim)) }),
                           label: "Battery \(b.percent)%, " + c(b.line1) + (b.line2.isEmpty ? "" : ", " + c(b.line2)), focusable: true)
        }
        out.append(blank)
        out.append(L(sp(" "), sp("Processes by CPU", .bold)))
        if let e = m.processError {
            out.append(L(sp(" "), sp("Cannot read the process list", .dim)))
            out.append(L(sp(" "), sp(e, .dim)))
        }
        for r in m.processes { out.append(row(r)) }
        return out
    }

    public static func settingsTab(_ s: SettingsTab) -> [Line] {
        var out = loginRow(s.openAtLogin, error: s.loginError)
        out += cbRow("macFiguresInBar", "Mac figures in the bar", s.macInBar, nil)
        out += cbRow("nudges", s.fiveHour ? "Nudge at 80% and before the 5h end" : "Nudge at 80%", s.nudges, s.nudgeNote)
        out += cbRow("listPriceEquivalent", "List price equivalent", s.listPrice, "tokens at list prices, not the plan price")
        out += cbRow("keepAwake", "Keep the Mac awake while Claude works", s.keepAwake, "a closed lid on battery still sleeps")
        if s.keepAwake {
            out += cbRow("keepAwakeWhileOpen", "also while a session waits for you", s.keepAwakeWhileOpen, s.awakeNote, indent: "     ")
        }
        out += cbRow("restoreSessions", "Reopen sessions after a restart", s.restoreSessions, "asks first, then opens each as it was started, and says when one ends on its own",
                     more: s.restoreSessions ? [s.nudgeNote].compactMap { $0 } : [])
        if s.restoreSessions { out += reopenAppRow(s.reopenApp) }
        out.append(blank)
        out += hookRow(installed: s.hookInstalled, someInstalled: s.hookSomeInstalled, error: s.hookError, slowerRefresh: s.hookSlowerRefresh,
                       targets: s.hookTargets, scriptMissing: s.hookScriptMissing, removeScriptError: s.removeScriptError)
        out.append(blank)
        out += reportRow(copied: s.reportCopied)
        out.append(blank)
        out += privacy()
        if let v = s.version { out.append(L(sp(" "), sp(v, .dim))) }
        out.append(blank)
        out.append(Line([sp(" "), Piece("Quit", .text, action: .quit), Piece(Format.rcol("\u{2318}Q", popCells - 5), .text, action: .quit)],
                        hover: true, label: "Quit, command Q"))
        return out
    }

    /// Copy a problem report: one click puts plain text on the clipboard for an issue or a mail. The dim line is its help.
    public static func reportRow(copied: Bool?) -> [Line] {
        let label = "Copy a problem report"
        var out = [Line([sp(" "), Piece(label, .text, action: .copyReport)], hover: true, label: label, help: reportHelp)]
        out += dimLines(reportHelp, indent: 5).map(\.silent)
        if let copied { out += dimLines(copied ? reportCopied : reportFailed, indent: 5) }
        return out
    }

    /// Under the button: what it does and what it never does.
    public static let reportHelp = "versions, switches and errors to paste into an issue or a mail, sends nothing"
    /// After a click, until the panel closes.
    public static let reportCopied = "copied"
    /// After a click the clipboard refused.
    public static let reportFailed = "could not copy"

    /// The app Reopen opens the sessions in: one pop-up row under the Reopen switch, a menu of Terminal, iTerm and Ghostty
    /// on a click, Space or Return. Ghostty and iTerm ask before they run each file they are handed, so their row says so.
    public static func reopenAppRow(_ app: TerminalApp) -> [Line] {
        let label = "Open sessions in"
        let asks: String? = app == .ghostty ? ghosttyAsks : app == .iterm ? itermAsks : nil
        var out = [Line([sp("     "), Piece(label + " " + app.title + " \u{25BE}", .text, action: .pickReopenApp, label: label, value: app.title)],
                        hover: true, label: label, help: asks)]
        if let asks { out += dimLines(asks, indent: 9).map(\.silent) }
        return out
    }

    /// Said under the pop-up while Ghostty is picked: Ghostty 1.2 and later confirm every script opened in them.
    public static let ghosttyAsks = "Ghostty asks before it runs each one"
    /// Said under the pop-up while iTerm is picked: iTerm confirms each script until "Suppress this message permanently"
    /// is ticked in its prompt (VM test 05.11, iTerm 3.7.7).
    public static let itermAsks = "iTerm asks until you tick Suppress"

    /// Open at login: the box shows what the system says. While the system waits for the user's OK, the box stays empty and
    /// the note under it opens System Settings, Login Items, on a click, like the row. An error from a click follows as a dim line.
    public static func loginRow(_ state: LoginItem, error: String?) -> [Line] {
        var out = cbRow(loginKey, "Open at login", state == .on, nil)
        if state == .needsApproval {
            out.append(Line([sp("     "), Piece("click to allow it in Login Items", .dim, action: .toggle(loginKey))],
                            hover: true, label: "Open at login waits for your OK, click to open Login Items in System Settings"))
        }
        if let error { out += dimLines(error, indent: 5) }
        return out
    }

    /// The Open at login row's action key. Not a preference: the state is the system's.
    public static let loginKey = "openAtLogin"

    /// Said where the click is when Install lowers the user's own refreshInterval: their command then runs that often too.
    static let refreshLine = "your status line then refreshes every 5 s"

    /// The status line entry: one click installs it, one click removes it and puts the previous entry back.
    /// With several settings folders installed in some and not in others, both rows show: Install adds the missing ones.
    public static func hookRow(installed: Bool, someInstalled: Bool = false, error: String?, slowerRefresh: Bool = false,
                               targets: [String] = ["~/.claude"], scriptMissing: Bool = false, removeScriptError: String? = nil) -> [Line] {
        var out: [Line] = []
        if !installed {
            let label = "Install the status line entry"
            out.append(Line([sp(" "), Piece(label, .text, action: .install)], hover: true, label: label))
            let target = targets.count <= 1 ? "one entry in \(targets.first ?? "~/.claude")/settings.json"
                                            : "one entry in each of " + targets.joined(separator: ", ")
            out += dimLines(target, indent: 5)
            if scriptMissing { out += dimLines("the hook script is gone, Install puts it back", indent: 5) }
            if slowerRefresh { out.append(L(sp("     "), sp(refreshLine, .dim))) }
        }
        if installed || someInstalled {
            let label = "Remove the status line entry"
            out.append(Line([sp(" "), Piece(label, .text, action: .uninstall)], hover: true, label: label))
            out.append(L(sp("     "), sp("puts back what statusLine held before", .dim)))
        }
        if let error { out += dimLines(error, indent: 5) }
        if let e = removeScriptError { out += dimLines(removeScriptNote + e, indent: 5) }
        return out
    }

    /// Said when remove.sh cannot be written: the zap runs it to put the previous status line back.
    public static let removeScriptNote = "Could not write remove.sh, so brew uninstall --zap cannot put your status line back: "

    public static func popover(_ s: Screen) -> [Line] {
        var out = header(line: s.headerLine, tab: s.tab, warn: s.warn) + [blank]
        switch s.tab {
        case 0: out += claudeTab(s.claude)
        case 1: out += macTab(s.mac)
        default: out += settingsTab(s.settings)
        }
        return out + foot(tab: s.tab)
    }
}
