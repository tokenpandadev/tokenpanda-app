#!/usr/bin/env python3
"""Builds the clickable wireframes of tokenpanda as it is built (0.1.7, main at 4ca4160).

    python3 build.py

Writes next to this file: screens/*.html, flows.js, index.html, walk.html, flow-test.md,
flows/flows.md and flows/NN-*.mmd. The screens share one set of parts (menu bar, the item,
the popover and its lines, system dialogs, terminal, editor), so a change to a part changes
every screen. The popover parts follow Sources/Text/Grammar.swift line for line.
Flow steps, their screens and the flow test results live in flows_data.py.
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SC = {}  # id -> dict(title, area, body, keys)


def reg(sid, title, area, body, keys=None):
    assert sid not in SC, sid
    SC[sid] = dict(title=title, area=area, body=body, keys=keys or {})


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def A(href, inner, cls='', style=''):
    st = f' style="{style}"' if style else ''
    c = f' class="{cls}"' if cls else ''
    if href:
        return f'<a{c} href="{href}.html"{st}>{inner}</a>'
    return f'<span{c}{st}>{inner}</span>'


def b(w, h=8, k=''):
    return f'<i class="b {k}" style="width:{w}px;height:{h}px"></i>'


def fb(cells, k=''):
    """A filler bar the width of `cells` mono cells: a name the drawing does not spell out."""
    return f'<i class="b {k}" style="width:{cells}ch;height:7px;margin:0 0"></i>'


def keys(**k):
    name = lambda kk: {'Shift_Tab': 'Shift+Tab', 'Meta_q': 'Meta+q'}.get(kk, kk)
    return {name(kk): (v + '.html') for kk, v in k.items() if v}


# ---------- the menu bar item: the panda from Sources/UI/ItemImage.swift ----------

PANDA = ["XX...XX", "XXXXXXX", "XXXXXXX", "X..X..X", "X.XXX.X", "XXX.XXX", ".XXXXX."]


def panda(eyes='normal'):
    grid = [list(''.join(c * 2 for c in row)) for row in PANDA for _ in (0, 1)]
    if eyes != 'normal':
        for left in (2, 8):
            for r in range(6, 10):
                for c in range(4):
                    hole = (c == r - 6 or c == 9 - r) if eyes == 'weekly' else r == 8
                    grid[r][left + c] = '.' if hole else 'X'
    rects = ''.join(f'<rect x="{c}" y="{r}" width="1" height="1"/>' for r, row in enumerate(grid) for c, ch in enumerate(row) if ch == 'X')
    return f'<svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor" aria-hidden="true">{rects}</svg>'


def item(fig='61%', eyes='normal', dim=False, over=False, warn=False, mac='', on=False, href='pop-live'):
    inner = panda(eyes) + (f'<b>{fig}</b>' if fig else '') + ('<span>&#9888;</span>' if warn else '') + (f'<span>{mac}</span>' if mac else '')
    cls = 'item' + (' dim' if dim else '') + (' over' if over else '') + (' on' if on else '')
    return A(href, inner, cls)


def mbar(it, clock='Thu 15 Oct 14:20', app='Finder'):
    return (f'<div class="mbar"><i class="apple"></i><span class="appname">{app}</span>{b(34, 7)}{b(28, 7)}{b(40, 7)}{b(30, 7)}'
            f'<span class="sp"></span><i class="ext"></i><i class="ext"></i>{it}<i class="ext"></i><i class="ext"></i>'
            f'<span class="clock">{clock}</span></div>')


def bgwins():
    return ('<div class="bgwin" style="left:40px;top:70px;width:560px;height:380px">' + b(180, 10, 'k') + b(420) + b(380) + b(400) + b(300) + b(360) + '</div>'
            '<div class="bgwin" style="left:120px;top:480px;width:460px;height:250px">' + b(140, 10, 'k') + b(380) + b(300) + b(340) + '</div>')


ITEM_X = 1040   # the item's middle on the canvas


def desk(it, clock='Thu 15 Oct 14:20', over='', app='Finder', wins=True):
    return f'<div class="vp">{bgwins() if wins else ""}{mbar(it, clock, app)}{over}</div>'


def tip(text, left, top, w=290, n=False):
    return f'<div class="tip{" n" if n else ""}" style="left:{left}px;top:{top}px;max-width:{w}px">{text}</div>'


def mark(left, top, w, h):
    return f'<div class="mark" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px"></div>'


# ---------- the popover lines, as Sources/Text/Grammar.swift draws them ----------

def L(*pieces, hov=False):
    return f'<div class="ln{" hov" if hov else ""}">' + ''.join(pieces) + '</div>'


def T(s, cls=''):
    return f'<span class="{cls}">{esc(s)}</span>' if cls else f'<span>{esc(s)}</span>'


BL = L(T(' '))


def wbar(cells, used, elapsed=None, over=False, stale=False):
    used = max(0, min(100, used))
    parts = []
    if over and elapsed is not None and used > elapsed:
        parts.append(f'<i style="width:{elapsed}%"></i><i class="ov" style="left:{elapsed}%;width:{used - elapsed}%"></i>')
    elif used > 0:
        parts.append(f'<i class="{"st" if stale else ""}" style="width:{used}%"></i>')
    if elapsed is not None:
        parts.append(f'<u style="left:calc({elapsed}% - 2px)"></u>')
    return f'<span class="wb{" stale" if stale else ""}" style="width:{cells}ch">{"".join(parts)}</span>'


def header(line, tab, warn=False, prefix='pop'):
    tabs = []
    for i, (name, sid) in enumerate([('Claude', TABS[prefix][0]), ('Mac', TABS[prefix][1]), ('Settings', TABS[prefix][2])]):
        if i:
            tabs.append(T('  '))
        inner = esc(name) + ('<i class="dot"></i>' if name == 'Mac' and warn else '')
        tabs.append(A(sid if i != tab else None, inner, 'tab' + (' on' if i == tab else '')))
    return L(T(' '), T(line, 'dim')) + '<div class="rule"></div>' + L(T(' '), *tabs)


# which screens the tab strip goes to, per family of popover screens
TABS = {'pop': ('pop-live', 'pop-mac', 'pop-settings'),
        'ultra': ('pop-ultra-today', 'pop-mac-ultra', 'pop-settings'),
        'nohook': ('pop-nohook', 'pop-mac', 'pop-settings-nohook'),
        'warn': ('pop-live-warn', 'pop-mac-warning', 'pop-settings')}


def win(title, mode='live', used=0, elapsed=None, over=False, reset='', countdown='', status='', proj='', allow='', asof='', note=''):
    out = [L(T(' '), T(title, 'bold'))]
    if mode == 'live':
        out.append(L(T(' '), wbar(36, used, elapsed, over), T(f' {used}% used')))
        out.append(L(T(' '), T(f'{reset}  {countdown}', 'dim')))
        out.append(L(T(' '), T(status, 'bold'), T(f'  {proj}', 'dim')) if proj else L(T(' '), T(status, 'bold')))
        out.append(L(T(' '), T(allow, 'dim')))
    elif mode == 'stale':
        out.append(L(T(' '), wbar(36, used, elapsed, stale=True), T(f' {used}% used', 'dim')))
        out.append(L(T(' '), T(reset, 'dim')))
        out.append(L(T(' '), T('as of ' + asof, 'dim')))
    elif mode == 'passed':
        out.append(L(T(' '), wbar(36, 0)))
        out.append(L(T(' '), T(reset + '  no session since', 'dim')))
    elif mode == 'absent':
        out.append(L(T(' '), wbar(36, 0)))
        out.append(L(T(' '), T('not in the last feed', 'dim')))
    elif mode == 'nosession':
        out.append(L(T(' '), wbar(36, 0)))
        out.append(L(T(' '), T('no session yet  open Claude Code once', 'dim')))
    return ''.join(out)


SHARED = L(T(' '), T('limits are shared with the Claude app and other', 'dim')) + L(T(' '), T('Macs, so the real figure may be higher', 'dim'))
PRIVACY = L(T(' '), T('This app makes no network calls. Usage comes', 'dim')) + L(T(' '), T("from Claude Code's own status feed on this Mac.", 'dim'))


def sessions(kind='two', tipline=False):
    out = [L(T(' '), T('Open sessions', 'bold'))]
    if kind == 'none':
        return ''.join(out) + L(T(' '), T('no open session', 'dim'))
    rows = [(9, 9, 41, '405.6k of 1M', ' 41%'), (7, 9, 9, '88.4k of 1M', '  9%')] if kind in ('two', 'waiting') else [(9, 9, 18, '180k of 1M', ' 18%')]
    for i, (n, m, used, fig, pct) in enumerate(rows):
        out.append(L(T(' '), fb(n, 'k'), T('  '), fb(m)))
        if kind == 'waiting':
            out.append(L(T(' '), wbar(24, 0), T('  '), T('waiting for the first reply', 'dim'), hov=False))
        else:
            out.append(L(T(' '), wbar(24, used), T('  ' + ' ' * (16 - len(fig)) + fig + ' ' + pct), hov=tipline and i == 0))
    return ''.join(out)


def tokens(section=0, empty=None, error=None, chip=True, prefix='pop'):
    title = ['Tokens by model  7 days', 'Tokens by project  7 days', 'Tokens by session  today'][section]
    hrefs = {'pop': ('pop-live', 'pop-projects', 'pop-sessions')}.get(prefix, (None, None, None))
    subs = [T(' ')]
    for i, name in enumerate(['Models', 'Projects', 'Sessions']):
        if i:
            subs.append(T('  '))
        subs.append(A(hrefs[i] if i != section else None, name, 'sub' + (' on' if i == section else '')))
    out = [L(T(' '), T(title, 'bold')), L(*subs)]
    if empty:
        out.append(L(T(' '), T(empty, 'dim')))
        if error:
            out.append(L(T(' '), T(error, 'dim')))
        return ''.join(out)
    data = [[(9, 49, '1.02B'), (8, 34, '0.71B'), (10, 11, '0.24B'), (9, 6, '0.13B')],
            [(9, 70, '1.46B'), (7, 20, '0.42B'), (7, 7, '0.14B'), (5, 4, '0.08B')],
            [(8, 43, '31.2M'), (8, 25, '18.0M'), (8, 17, '12.6M'), (5, 15, '10.6M')]][section]
    for n, share, fig in data:
        out.append(L(T(' '), fb(n, 'k'), T(' ' * (15 - n)), wbar(24, share), T('  ' + ' ' * (5 - len(fig)) + fig)))
    if chip:
        out.append(L(T(' '), T('[list price equivalent  USD 1,140]', 'dim')))
    out.append(L(T(' '), T('[44% by subagents]', 'dim')))
    return ''.join(out)


def weeks(rows):
    out = [L(T(' '), T('Week over week', 'bold'))]
    for date, used, hit, note, el, over in rows:
        pieces = [T(' '), T(f'{date:<6}  ')]
        if used is None:
            pieces += [wbar(20, 0), T('  ')]
        else:
            pieces += [wbar(20, used, el, over), T('&#9888;' if hit else ' ', 'warnc') if hit else T(' '), T(' ' + f'{used}%'.rjust(4))]
        if note:
            pieces.append(T('  ' + note, 'dim'))
        out.append(L(*pieces))
    return ''.join(out)


W_SAMPLE = [('21 Sep', 88, False, '', None, False), ('28 Sep', 100, True, 'Thu 16:10', None, False), ('5 Oct', 96, False, '', None, False), ('12 Oct', 61, False, 'so far', 55, True)]
W_ULTRA = [('12 Oct', 80, False, '', None, False), ('19 Oct', 35, False, '', None, False), ('26 Oct', 28, False, 'so far', 82, False)]


def foot(tab):
    return BL + L(T(' '), T('Esc closes  Tab switches  m p s sections' if tab == 0 else 'Esc closes  Tab switches', 'quiet'))


def pop(lines, left=None, arrow=None):
    left = ITEM_X - 190 if left is None else left
    arrow = ITEM_X - left - 7 if arrow is None else arrow
    return f'<div class="pop" style="left:{left}px;--arrow:{arrow}px">{lines}</div>'


def fix_html(s):
    # tab strip and <span> pieces carry raw names; the warning glyph in weeks is an entity
    return s.replace('<span class="warnc">&amp;#9888;</span>', '<span class="warnc">&#9888;</span>')


# ---------- popover screens ----------

LIVE_HDR = 'Usage live  Mac live'


def claude(limits, sess='two', tok=0, wk=None, hdr=LIVE_HDR, tab_prefix='pop', warn=False, chip=True, tok_empty=None, tok_err=None, tipline=False, staleNote=False):
    body = header(hdr, 0, warn, tab_prefix) + BL + limits + (SHARED if staleNote else '') + BL
    if sess:
        body += sessions(sess, tipline) + BL
    body += tokens(tok, tok_empty, tok_err, chip, 'pop' if tab_prefix == 'pop' else tab_prefix) + BL + weeks(wk or W_SAMPLE) + foot(0)
    return fix_html(body)


WEEKLY_OVER = dict(used=61, elapsed=55, over=True, reset='Resets Sun 18:00', countdown='in 3d 3h', status='Over pace', proj='limit Sun 01:20 at this rate', allow='0.5% an hour left')
FIVE_AHEAD = dict(used=24, elapsed=32, reset='Resets 17:45', countdown='in 3h 25m', status='Ahead', proj='76% by reset at this rate', allow='22% an hour left')
WEEKLY_ULTRA = dict(used=28, elapsed=82, reset='Resets Sun 17:00', countdown='in 1d 5h', status='Ahead', proj='34% by reset at this rate', allow='2% an hour left')
TODAY = 'Sat 31 Oct 11:11'

LIVE_LIMITS = win('Weekly (all models)', **WEEKLY_OVER) + BL + win('5h window', **FIVE_AHEAD)
POP_KEYS = keys(Escape='desk', Tab='pop-mac', Shift_Tab='pop-settings', m='pop-live', p='pop-projects', s='pop-sessions', Meta_q='desk-quit')

reg('desk', 'Menu bar, the item: panda and the weekly percentage, over pace in semibold', 'Menu bar',
    desk(item('61%', over=True, href='pop-live')))
reg('pop-live', 'Claude tab, live: weekly over pace, 5h ahead (Max or Pro)', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS))), POP_KEYS)
reg('pop-session-tip', 'Claude tab, hover on a session figure: list price, lines, effort', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tipline=True))
         + '<div style="position:absolute;left:860px;top:316px;width:360px;height:16px;overflow:hidden;background:#373737;color:var(--ink);font:12px/16px ui-monospace,monospace;white-space:pre"> USD 38.20 list price equivalent  112 added  9 removed  effort high</div>'
         + mark(856, 312, 372, 24) + tip('<b>Friction.</b> The tooltip is 68 cells wide in a 50 cell view and is drawn from the left edge, so it is cut after "9 remo" and the effort never shows (LineView.swift:203-213; the text from ScreenBuilder.swift:106-107).', 520, 290, 320)), POP_KEYS)
reg('pop-projects', 'Claude tab, tokens by project, 7 days (p)', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tok=1))), POP_KEYS)
reg('pop-sessions', 'Claude tab, tokens by session, today (s)', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tok=2))), POP_KEYS)
reg('pop-nochip', 'Claude tab with List price equivalent off: no price chip', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, chip=False))), POP_KEYS)

# flicker
FLICK = lambda u, proj: win('Weekly (all models)', used=u, elapsed=82, reset='Resets Sun 17:00', countdown='in 1d 5h', status='Ahead', proj=proj, allow='2% an hour left' if u > 20 else '3% an hour left') + BL + win('5h window', 'absent')
reg('desk-flicker-a', 'Menu bar with ten sessions open: 28% now', 'Menu bar',
    desk(item('28%', href='pop-flicker-a'), TODAY, over=tip('<b>Broken.</b> Watch it for ten seconds: 28%, 12%, 28%, 18%, 11%, 28%. Each idle session re-sends the weekly figure it saw at its own last reply, every 5 s, and the newest file wins (FeedReader.swift:96-101).', 760, 40, 320)
         + '<div class="alts"><a class="altg" href="desk-flicker-b.html">Two seconds later</a></div>'))
reg('desk-flicker-b', 'Menu bar two seconds later: 12%', 'Menu bar',
    desk(item('12%', href='pop-flicker-b'), TODAY, over=tip('<b>Broken.</b> Same account, same minute, 12%. The real figure is the highest one: usage inside a window only grows.', 760, 40, 320)
         + '<div class="alts"><a class="altg" href="pop-flicker-a.html">Open the popover</a></div>'))
UK = keys(Escape='desk-ultra', Tab='pop-mac-ultra', Shift_Tab='pop-settings', Meta_q='desk-quit')
reg('pop-flicker-a', 'Claude tab, the weekly at 28%', 'Claude tab',
    desk(item('28%', on=True, href='desk-flicker-a'), TODAY, over=pop(claude(FLICK(28, '34% by reset at this rate'), wk=W_ULTRA, tab_prefix='ultra'))
         + '<div class="alts"><a class="altg" href="pop-flicker-b.html">Two seconds later</a></div>'), UK)
reg('pop-flicker-b', 'Claude tab two seconds later: the weekly at 12%, Ahead 15% by reset', 'Claude tab',
    desk(item('12%', on=True, href='desk-flicker-b'), TODAY, over=pop(claude(FLICK(12, '15% by reset at this rate'), wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 12, False, 'so far', 82, False)], tab_prefix='ultra'))
         + mark(ITEM_X - 186, 106, 372, 88) + tip('<b>Broken.</b> The bar, the projection and the allowance jump with it. Week over week keeps whatever value was last seen: the real weeks.json holds 12 for this week while the account is at 28.', 560, 110, 300)), UK)

# first run and setup
NOHOOK = (L(T(' '), T('Weekly and 5h window', 'bold')) + L(T(' '), T("needs Claude Code's status line feed", 'dim'))
          + L(T(' '), T('one statusLine entry in ~/.claude/settings.json', 'dim')))


def nohook_lines(prev=False, href='pop-nosession'):
    return (NOHOOK + L(T(' '), T('your current status line is kept and chained' if prev else 'chained if one exists', 'dim'))
            + L(T(' '), A(href, ' Install the status line hook ', 'btnl')) + BL + PRIVACY)


def claude_nohook(prev=False, href='pop-nosession'):
    body = header('No usage feed yet  Mac live', 0, False, 'nohook') + BL + nohook_lines(prev, href) + BL + tokens(0) + BL + weeks(W_SAMPLE[:3] + [('12 Oct', None, False, 'no feed yet', None, False)]) + foot(0)
    return fix_html(body)


NK = keys(Escape='desk-nofeed', Tab='pop-mac', Shift_Tab='pop-settings-nohook', Meta_q='desk-quit')
reg('desk-nofeed', 'Menu bar, first launch: the panda alone, dimmed', 'Menu bar', desk(item('', dim=True, href='pop-nohook')))
reg('pop-nohook', 'Claude tab, first open: Install the status line hook', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook())
         + '<div class="alts"><a class="altg" href="editor-broken.html">settings.json is not valid JSON</a><a class="altg" href="pop-nohook-chained.html">You already have a status line</a></div>'), NK)
reg('pop-nohook-chained', 'Claude tab, first open with a status line of your own: kept and chained', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook(True))), NK)
reg('pop-install-failed', 'Claude tab after Install with an unreadable settings.json: nothing changes here', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook(href='pop-install-failed'))
         + mark(ITEM_X - 186, 172, 222, 20) + tip('<b>Broken.</b> The click failed ("settings.json is not a JSON object") and the Claude tab looks exactly as before. The error is drawn only on the Settings tab (Grammar.swift:100-110 has no error line; ScreenBuilder.swift:284 passes hookError to Settings only).', 560, 180, 300)
         + '<div class="alts"><a class="altg" href="pop-settings-error.html">Open Settings</a></div>'), NK)
reg('pop-nosession', 'Claude tab, hook installed, no session yet', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(fix_html(header('No usage feed yet  Mac live', 0) + BL + win('Weekly (all models)', 'nosession') + BL + win('5h window', 'nosession') + BL
                                                                          + sessions('none') + BL + tokens(0) + BL + weeks(W_SAMPLE[:3] + [('12 Oct', None, False, 'no feed yet', None, False)]) + foot(0)))
         + '<div class="alts"><a class="altg" href="term-claude.html">Start Claude Code</a></div>'), POP_KEYS)
reg('pop-firstcall', 'Claude tab during the first call: sessions open, windows still say open Claude Code once', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(fix_html(header(LIVE_HDR, 0) + BL + win('Weekly (all models)', 'nosession') + BL + win('5h window', 'nosession') + BL
                                                                          + sessions('waiting') + BL + tokens(0) + BL + weeks(W_SAMPLE) + foot(0)))
         + mark(ITEM_X - 186, 106, 372, 120) + tip('<b>Friction.</b> "open Claude Code once" while two sessions are open right under it. The first call never carries rate_limits; the figures come after the first reply. "waiting for the first reply" would be the honest line (Grammar.swift:112).', 560, 100, 300)
         + '<div class="alts"><a class="altg" href="pop-live.html">After the first reply</a></div>'), POP_KEYS)

# ultra
U_TODAY = win('Weekly (all models)', **WEEKLY_ULTRA) + BL + win('5h window', 'passed', reset='Reset 00:10')
reg('desk-ultra', 'Menu bar today, Ultra: 28%, nothing about the 5h window', 'Menu bar', desk(item('28%', href='pop-ultra-today'), TODAY))
reg('pop-ultra-today', 'Claude tab today, Ultra: the 5h window reads Reset 00:10 no session since, under Usage live', '5h window',
    desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(claude(U_TODAY, sess='one', wk=W_ULTRA, tab_prefix='ultra'))
         + mark(ITEM_X - 186, 202, 372, 54) + tip('<b>Broken.</b> Header says Usage live and a session is open, yet the 5h window says no session since 00:10. The feed has had no five_hour since 30 Oct; the stored record from that night stays in limits.json for good (FeedReader.swift:23-37), and a passed reset draws this line (ScreenBuilder.swift:65-66). "00:10" carries no day, so it reads as today.', 520, 190, 330)
         + '<div class="alts"><a class="altg" href="pop-ultra-fixed.html">The smallest fix</a></div>'), UK)
reg('pop-ultra-fixed', 'Proposed fix, not built: no 5h window in the feed, so no 5h section', '5h window',
    desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(claude(win('Weekly (all models)', **WEEKLY_ULTRA), sess='one', wk=W_ULTRA, tab_prefix='ultra'))
         + '<div class="fixlbl">Proposed fix, not in 0.1.7</div>'
         + tip('A feed that carries rate_limits without five_hour drops the stored five_hour (Limits.apply, FeedReader.swift:23). The 5h section is drawn only while the record exists (ScreenBuilder.swift:83). Max and Pro feeds still carry it, so for them nothing changes.', 520, 120, 330, n=True)), UK)
U_EVE = win('Weekly (all models)', used=24, elapsed=56, reset='Resets Sun 17:00', countdown='in 1d 19h', status='Ahead', proj='32% by reset at this rate', allow='2% an hour left') + BL + \
    win('5h window', used=63, elapsed=47, over=True, reset='Resets 00:10', countdown='in 2h 40m', status='Over pace', proj='limit 22:50 at this rate', allow='14% an hour left')
reg('pop-ultra-evening', '30 Oct, 21:30, Ultra: the 5h window frozen at 63% with a live countdown and pace', '5h window',
    desk(item('24%', on=True, href='desk-ultra'), 'Fri 30 Oct 21:30', over=pop(claude(U_EVE, sess='two', wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 24, False, 'so far', 56, False)], tab_prefix='ultra'))
         + mark(ITEM_X - 186, 202, 372, 88) + tip('<b>Broken.</b> 63% is the last figure before the feed stopped sending the 5h window. The countdown runs, the tick moves, and the projection says the limit lands 22:50: a limit that no longer exists. Nothing marks it as old, because the weekly keeps the shared asOf fresh (ScreenBuilder.swift:69).', 520, 170, 330)), UK)
U_LATE = win('Weekly (all models)', used=25, elapsed=58, reset='Resets Sun 17:00', countdown='in 1d 17h', status='Ahead', proj='33% by reset at this rate', allow='2% an hour left') + BL + \
    win('5h window', used=63, elapsed=96, reset='Resets 00:10', countdown='in 0h 12m', status='Ahead', proj='66% by reset at this rate', allow='185% an hour left')
reg('pop-ultra-late', '30 Oct, 23:58: the frozen 5h window drifts to Ahead, 185% an hour left', '5h window',
    desk(item('25%', on=True, href='desk-ultra'), 'Fri 30 Oct 23:58', over=pop(claude(U_LATE, sess='two', wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 25, False, 'so far', 58, False)], tab_prefix='ultra'))
         + mark(ITEM_X - 186, 202, 372, 88) + tip('<b>Broken.</b> The same frozen 63%, now read against the clock: Ahead, 185% an hour left. Rendered by the app from these inputs (states/ultra-late).', 520, 170, 300)
         + '<div class="alts"><a class="altg" href="notif-five-false.html">At 23:55, with a session feeding</a></div>'), UK)
reg('desk-five-limit', 'Menu bar, Ultra, the 5h window was at 100% when the feed stopped: - - eyes', 'Menu bar',
    desk(item('24%', eyes='five', href='pop-ultra-evening'), 'Fri 30 Oct 21:30', over=tip('<b>Broken.</b> The eyes say the 5h limit is reached and VoiceOver adds "5h limit reached" until 00:10, for a window Ultra no longer has (ScreenBuilder.swift:292-299 reads the frozen record).', 760, 40, 320)))
reg('pop-ultra-new', 'Claude tab, a new Ultra user: 5h window, empty bar, not in the last feed, for good', '5h window',
    desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(claude(win('Weekly (all models)', **WEEKLY_ULTRA) + BL + win('5h window', 'absent'), sess='one', wk=W_ULTRA[2:], tab_prefix='ultra'))
         + mark(ITEM_X - 186, 202, 372, 54) + tip('<b>Friction.</b> True, but permanent: an empty bar for a window this plan does not have. With the fix the section is gone.', 560, 200, 280)), UK)
reg('pop-live-max', 'Claude tab, Max or Pro today: both windows, as before', '5h window',
    desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(claude(win('Weekly (all models)', **WEEKLY_ULTRA) + BL + win('5h window', used=41, elapsed=55, reset='Resets 13:26', countdown='in 2h 15m', status='Ahead', proj='75% by reset at this rate', allow='26% an hour left'), sess='one', wk=W_ULTRA, tab_prefix='ultra'))), UK)

# weekly reset
reg('pop-week-near', 'Claude tab, 40 minutes before the weekly reset', 'Weekly reset',
    desk(item('91%', href='desk'), 'Sun 1 Nov 16:20', over=pop(claude(win('Weekly (all models)', used=91, elapsed=99, reset='Resets Sun 17:00', countdown='in 0h 40m', status='Ahead', proj='91% by reset at this rate', allow='13% an hour left') + BL + win('5h window', 'absent'), sess='one', wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 91, False, 'so far', 99, False)], tab_prefix='ultra'))
         + '<div class="alts"><a class="altg" href="pop-week-rolled.html">17:00 passes, no session open</a><a class="altg" href="pop-week-rolled-live.html">17:00 passes, sessions open and idle</a></div>'), UK)
reg('pop-week-rolled', 'Claude tab, weekly reset passed with no session since', 'Weekly reset',
    desk(item('', dim=True, href='desk'), 'Sun 1 Nov 18:30', over=pop(claude(win('Weekly (all models)', 'passed', reset='Reset Sun 17:00') + BL + win('5h window', 'absent'), sess='none', wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 91, False, '', None, False), ('2 Nov', None, False, 'last seen 91%', None, False)], hdr='Usage as of 16:52, last Claude Code session', tab_prefix='ultra'))), UK)
reg('pop-week-rolled-live', 'Claude tab, weekly reset passed while idle sessions feed: no session since, under Usage live', 'Weekly reset',
    desk(item('', dim=True, on=True, href='desk'), 'Sun 1 Nov 17:20', over=pop(claude(win('Weekly (all models)', 'passed', reset='Reset Sun 17:00') + BL + win('5h window', 'absent'), sess='two', wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 91, False, '', None, False), ('2 Nov', None, False, 'last seen 91%', None, False)], tab_prefix='ultra'))
         + mark(ITEM_X - 186, 106, 372, 56) + tip('<b>Friction.</b> Claude Code drops a window once its reset passes; the idle sessions keep feeding without it, and the app keeps the old record, so the weekly reads "no session since" while two sessions are listed below. It clears with the next reply. Same root as the 5h window.', 520, 100, 320)
         + '<div class="alts"><a class="altg" href="pop-week-new.html">The next reply</a></div>'), UK)
reg('pop-week-new', 'Claude tab, the new week arrived: 1% used, last week kept', 'Weekly reset',
    desk(item('1%', on=True, href='desk'), 'Sun 1 Nov 17:24', over=pop(claude(win('Weekly (all models)', used=1, elapsed=0.4, reset='Resets Sun 17:00', countdown='in 6d 23h', status='On pace', proj='limit Tue 09:00 at this rate', allow='0.6% an hour left') + BL + win('5h window', 'absent'), sess='two', wk=[W_ULTRA[0], W_ULTRA[1], ('26 Oct', 91, False, '', None, False), ('2 Nov', 1, False, 'so far', 0.4, False)], tab_prefix='ultra'))), UK)
reg('desk-weekly-limit', 'Menu bar, weekly limit reached: x x eyes until the reset', 'Menu bar', desk(item('100%', eyes='weekly', over=True, href='pop-live')))

# stale and missing
reg('pop-asof', 'Claude tab, last session closed 20 minutes ago: Usage as of, pace still computed', 'Stale feed',
    desk(item('61%', over=True, on=True, href='desk'), 'Thu 15 Oct 13:25', over=pop(claude(LIVE_LIMITS, sess='none', hdr='Usage as of 13:05, last Claude Code session')))
    + '', POP_KEYS)
STALE = win('Weekly (all models)', 'stale', used=61, elapsed=55, reset='Resets Sun 18:00', asof='13:05') + BL + win('5h window', 'stale', used=24, elapsed=32, reset='Resets 17:45', asof='13:05')
reg('pop-stale', 'Claude tab, stale: no session for over an hour', 'Stale feed',
    desk(item('61%', dim=True, on=True, href='desk-stale'), over=pop(claude(STALE, sess='none', hdr='Usage as of 13:05, last Claude Code session', staleNote=True))), POP_KEYS)
reg('desk-stale', 'Menu bar, stale: the item at half strength', 'Menu bar', desk(item('61%', dim=True, href='pop-stale')))
reg('pop-nolimits', 'Claude tab, an account without plan limits (API key)', 'Stale feed',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(fix_html(header(LIVE_HDR, 0) + BL + L(T(' '), T('Weekly and 5h window', 'bold')) + L(T(' '), T('this account has no plan limits to show', 'dim')) + BL
                                                                          + sessions('two') + BL + tokens(0) + BL + weeks(W_SAMPLE[:3] + [('12 Oct', None, False, 'no feed yet', None, False)]) + foot(0)))), POP_KEYS)
reg('pop-notranscripts', 'Claude tab, no transcripts folder', 'Stale feed',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tok_empty='No transcripts in ~/.claude/projects'))), POP_KEYS)

# Mac tab


def mac_tab(warn=False, health=True, hdr=LIVE_HDR, prefix='pop'):
    cells = ''.join('<i></i>' for _ in range(142)) + ''.join('<i class="f"></i>' for _ in range(53)) + ''.join('<i class="w"></i>' for _ in range(5))
    procs = [(6, 100, '6.1%'), (5, 38, '2.3%'), (12, 23, '1.4%'), (8, 13, '0.8%'), (5, 10, '0.6%')]
    body = header(hdr, 1, warn, prefix) + BL
    body += L(T(' '), T('CPU', 'bold')) + L(T(' '), wbar(36, 9), T(' 9%')) + L(T(' '), T('user 5%  system 4%  10 cores', 'dim')) + BL
    body += L(T(' '), T('GPU', 'bold')) + L(T(' '), wbar(36, 11), T(' 11%')) + L(T(' '), T('device utilisation', 'dim')) + BL
    body += L(T(' '), T('Memory', 'bold')) + f'<div class="grid10" style="margin-left:1ch">{cells}</div>'
    body += L(T(' '), T('Used ', ''), T('25.5 of 36 GB (71%)', 'dim')) + L(T(' '), T('Free ', ''), T('10.5 GB', 'dim')) + L(T(' '), T('Swap ', ''), T('0.9 GB', 'dim'), T('   '), T('Pressure ' + ('warn' if warn else 'normal'), 'dim')) + BL
    body += L(T(' '), T('Battery', 'bold')) + L(T(' '), wbar(36, 75), T(' 75%')) + L(T(' '), T('charging  47.6 W in  94 W adapter', 'dim'))
    body += L(T(' '), T('full in 51 min  ' + ('health 89%' if health else 'health n/a') + '  316 cycles', 'dim')) + BL
    body += L(T(' '), T('Processes by CPU', 'bold'))
    for n, share, fig in procs:
        body += L(T(' '), fb(n, 'k'), T(' ' * (15 - n)), wbar(24, share), T('   ' + fig.rjust(4)))
    return body + foot(1)


MK = keys(Escape='desk', Tab='pop-settings', Shift_Tab='pop-live', Meta_q='desk-quit')
reg('pop-mac', 'Mac tab: CPU, GPU, memory, battery, processes', 'Mac tab', desk(item('61%', over=True, on=True, href='desk'), over=pop(mac_tab())), MK)
reg('pop-mac-ultra', 'Mac tab (today)', 'Mac tab', desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(mac_tab(prefix='ultra'))), keys(Escape='desk-ultra', Tab='pop-settings', Shift_Tab='pop-ultra-today'))
reg('pop-mac-warning', 'Mac tab with the warning: dot on the tab, pressure warn', 'Mac tab', desk(item('61%', over=True, warn=True, on=True, href='desk-warning'), over=pop(mac_tab(warn=True, prefix='warn'))), keys(Escape='desk-warning', Tab='pop-settings', Shift_Tab='pop-live-warn'))
reg('pop-live-warn', 'Claude tab with the Mac warning dot', 'Mac tab', desk(item('61%', over=True, warn=True, on=True, href='desk-warning'), over=pop(claude(LIVE_LIMITS, tab_prefix='warn', warn=True))), keys(Escape='desk-warning', Tab='pop-mac-warning'))
reg('pop-mac-health', 'Mac tab, battery health unknown: health n/a', 'Mac tab', desk(item('61%', over=True, on=True, href='desk'), over=pop(mac_tab(health=False))), MK)
reg('desk-warning', 'Menu bar with the Mac warning sign', 'Menu bar', desk(item('61%', over=True, warn=True, href='pop-live-warn')))
reg('desk-mac', 'Menu bar with Mac figures in the bar: CPU 9%', 'Menu bar', desk(item('61%', over=True, mac=' CPU 9%', href='pop-settings')))
reg('desk-quit', 'Menu bar after Quit: the item is gone', 'Menu bar', desk(f'<span class="ext"></span>')
    + '')

# Settings tab


def cb(on, label, href, sub=None, indent=' ', subhref=None, subcls='dim'):
    out = L(T(indent), A(href, ('[x]' if on else '[ ]') + ' ' + esc(label), 'cb'), hov=False)
    if sub:
        out += L(T(indent + '    '), A(subhref, esc(sub), subcls) if subhref else T(sub, subcls))
    return out


def settings_tab(login='off', nudge_note=None, awake=False, awake_open=False, awake_note=None, restore=False, hook=True, hook_err=None, login_err=None, prefix='pop', hdr=LIVE_HDR, macbar=False, listprice=True):
    body = header(hdr, 2, False, prefix) + BL
    body += cb(login == 'on', 'Open at login', 'pop-settings-login' if login == 'off' else 'pop-settings')
    if login == 'approval':
        body += L(T('     '), A('sys-loginitems', 'click to allow it in Login Items', 'dim'))
    if login_err:
        body += L(T('     '), T(login_err, 'dim'))
    body += cb(macbar, 'Mac figures in the bar', 'desk-mac')
    body += cb(True, 'Nudge at 80% and before the 5h end', 'pop-settings', nudge_note)
    body += cb(listprice, 'List price equivalent', 'pop-nochip', 'tokens at list prices, not the plan price')
    body += cb(awake, 'Keep the Mac awake while Claude works', 'pop-settings-awake' if not awake else 'pop-settings')
    if awake:
        body += cb(awake_open, 'also while a session waits for you', 'pop-settings-awake-open' if not awake_open else 'pop-settings-awake', awake_note, indent='     ')
    body += cb(restore, 'Reopen sessions after a restart', 'pop-settings-restore' if not restore else 'pop-settings', 'asks first, then opens them in Terminal') + BL
    if hook:
        body += L(T(' '), A('editor-restored', 'Remove the status line entry')) + L(T('     '), T('puts back what statusLine held before', 'dim'))
    else:
        body += L(T(' '), A('editor-after', 'Install the status line entry')) + L(T('     '), T('one statusLine entry in ~/.claude/settings.js', 'dim'))
    if hook_err:
        body += L(T('     '), T(hook_err, 'dim'))
    body += BL + PRIVACY + BL + L(T(' '), A('desk-quit', 'Quit'), T(' ' * 39), A('desk-quit', '&#8984;Q')) + foot(2)
    return body


SK = keys(Escape='desk', Tab='pop-live', Shift_Tab='pop-mac', Meta_q='desk-quit')
reg('pop-settings', 'Settings tab', 'Settings', desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab())), SK)
reg('pop-settings-login', 'Settings, Open at login on: macOS lists it in Login Items', 'Settings',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab(login='on')) + '<div class="alts"><a class="altg" href="pop-settings-approval.html">macOS waits for your OK</a><a class="altg" href="sys-loginitems.html">System Settings, Login Items</a></div>'), SK)
reg('pop-settings-approval', 'Settings, Open at login waits for approval: click to allow it in Login Items', 'Settings', desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab(login='approval'))), SK)
reg('pop-settings-awake', 'Settings, Keep the Mac awake on, one session working', 'Settings', desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab(awake=True, awake_note='awake  1 session working')) + '<div class="alts"><a class="altg" href="term-pmset.html">pmset -g assertions</a></div>'), SK)
reg('pop-settings-awake-open', 'Settings, also while a session waits: awake  1 session open', 'Settings', desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab(awake=True, awake_open=True, awake_note='awake  1 session open', restore=True))), SK)
reg('pop-settings-restore', 'Settings, Reopen sessions after a restart on', 'Settings', desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab(restore=True)) + '<div class="alts"><a class="altg" href="notif-reopen.html">After a restart</a></div>'), SK)
reg('pop-settings-nohook', 'Settings, hook not installed: the second line runs past the edge', 'Settings',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(settings_tab(hook=False, hdr='No usage feed yet  Mac live', prefix='nohook'))
         + mark(ITEM_X - 154, 268, 336, 20) + tip('<b>Friction.</b> "one statusLine entry in ~/.claude/settings.json" is 51 cells in a 47 cell popover and is cut at ".js" (Grammar.swift:318, not cut to width like the error lines). The button says "entry" here and "hook" on the Claude tab.', 520, 380, 320)), keys(Escape='desk-nofeed', Tab='pop-nohook'))
reg('pop-settings-denied', 'Settings, notifications denied: the note is cut and does not open System Settings', 'Settings',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab(nudge_note='Notifications are off for this app in System'))
         + mark(ITEM_X - 154, 156, 336, 20) + tip('<b>Friction.</b> The note is 57 cells and loses "Settings" at the edge; it is plain text, so a click does not open System Settings, Notifications (Grammar.swift:279, Notifier.swift:30).', 520, 170, 320)), SK)
reg('pop-settings-error', 'Settings, the install error under the row', 'Settings',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(settings_tab(hook=False, hook_err='Could not install the entry: cannot read setti', hdr='No usage feed yet  Mac live', prefix='nohook'))
         + tip('The error is here, cut to the width: "Could not install the entry: cannot read setti". The reason (not a JSON object) is cut off.', 560, 420, 300)), keys(Escape='desk-nofeed', Tab='pop-nohook'))

# accessibility
reg('pop-voiceover', 'VoiceOver in the popover: every line is static text, the controls cannot be pressed', 'Access',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook()) + mark(ITEM_X - 186, 172, 222, 20)
         + tip('<b>Broken.</b> VoiceOver reads "Install the status line hook, text". It has no button role and no press action, so a VoiceOver user cannot install the feed, switch tabs or tick a setting. LineView.swift:90-97 makes every line an NSAccessibilityElement of role staticText. The style guide (section 9) promises buttons, tabs and checkboxes with state.', 520, 170, 330)), NK)
reg('pop-keyboard', 'Keyboard in the popover: Tab switches tabs, nothing takes focus, Space does nothing', 'Access',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(settings_tab())
         + tip('<b>Broken.</b> Tab, Shift Tab, Esc, m p s and Command Q are the only keys (Controller.swift:529-541). No row takes focus, so a setting cannot be ticked from the keyboard; the style guide promises a focus ring and Space to toggle. The key hints are #505050 on the glass, about 2.1 to 1.', 520, 150, 330)), SK)

# ---------- system surfaces ----------


def swin(title, side_sel, main, left=210, top=70, w=860, h=600):
    items = ['General', 'Appearance', 'Menu Bar', 'Notifications', 'Privacy &amp; Security', 'Login Items']
    side = ''.join(f'<div class="si{" on" if it == side_sel else ""}"><i></i>{it}</div>' for it in items)
    return (f'<div class="win" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>{title}</div>'
            f'<div class="wbody"><div class="sside">{side}</div><div class="smain">{main}</div></div></div>')


def term(title, lines, left=150, top=80, w=980, h=560):
    body = ''.join(f'<div class="{c}">{t}</div>' for c, t in lines)
    return (f'<div class="win" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>{title}</div>'
            f'<div class="term">{body}</div></div>')


def dlg(title, text, btns, left=490, top=200):
    bt = ''.join(A(h, l, 'btn' + (' pri' if p else '')) for l, h, p in btns)
    return f'<div class="dlg" style="left:{left}px;top:{top}px"><i class="appic" style="width:44px;height:44px;border-radius:10px"></i><h3>{title}</h3><p>{text}</p><div class="btns">{bt}</div></div>'


def notif(title, body, acts=()):
    a = ''.join(A(h, l, 'btn') for l, h in acts)
    return f'<div class="notif"><i class="appic"></i><div><div class="t">{title}</div><div>{body}</div></div>{"<div class=acts>" + a + "</div>" if a else ""}</div>'


def plain(over, clock='Thu 15 Oct 14:20', it=None, app='Finder'):
    return desk(it or f'<span class="ext"></span>', clock, over, app)


reg('browser-release', 'Releases page: tokenpanda-0.1.7.zip and its .sha256', 'Install',
    plain('<div class="win" style="left:150px;top:60px;width:980px;height:640px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>Releases</div>'
          '<div class="urlbar">github.com/tokenpandadev/tokenpanda-app/releases</div><div class="page"><h2>0.1.7</h2>' + b(520) + b(460) + b(380)
          + '<div class="grp" style="margin-top:10px">' + A('term-shasum', '<span>tokenpanda-0.1.7.zip</span><span class="sp"></span><span class="note">1.1 MB</span>', 'asset')
          + A('term-shasum', '<span>tokenpanda-0.1.7.zip.sha256</span><span class="sp"></span><span class="note">96 B</span>', 'asset')
          + '<div class="asset"><span>Source code (zip)</span></div></div></div></div>', app='Safari')
    + '')
reg('term-shasum', 'Terminal: shasum checks the zip, OK', 'Install',
    plain(term('Terminal, ~/Downloads', [('p', '$ shasum -a 256 -c tokenpanda-0.1.7.zip.sha256'), ('ok', 'tokenpanda-0.1.7.zip: OK'), ('p', '$ unzip -q tokenpanda-0.1.7.zip &amp;&amp; mv tokenpanda.app /Applications/')])
          + '<div class="alts"><a class="altg" href="finder-apps.html">Open Applications</a><a class="altg" href="term-brew.html">With Homebrew instead</a></div>', app='Terminal'))
reg('term-brew', 'Terminal: brew install from the tap, the caveats', 'Install',
    plain(term('Terminal', [('p', '$ brew install tokenpandadev/tap/tokenpanda'), ('d', '==&gt; Tapping tokenpandadev/tap'), ('d', '==&gt; Installing Cask tokenpanda'),
                            ('', '==&gt; Caveats'), ('', 'The app is signed ad hoc, not notarised. On first launch macOS blocks it:'), ('', 'open System Settings, Privacy &amp; Security, and click Open Anyway.'),
                            ('', 'Before you uninstall, open tokenpanda\'s Settings tab and click'), ('', '"Remove the status line entry", so ~/.claude/settings.json gets its'), ('', 'previous statusLine back.'),
                            ('ok', 'tokenpanda was successfully installed!')])
          + '<div class="alts"><a class="altg" href="gk-blocked.html">Open the app</a></div>', app='Terminal'))
reg('finder-apps', 'Finder, Applications: tokenpanda.app', 'Install',
    plain('<div class="win" style="left:200px;top:90px;width:880px;height:520px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>Applications</div><div class="fgrid">'
          + ''.join('<div class="fi"><i></i>' + b(56, 6) + '</div>' for _ in range(5)) + A('gk-blocked', '<i></i>tokenpanda', 'fi on')
          + ''.join('<div class="fi"><i></i>' + b(50, 6) + '</div>' for _ in range(6)) + '</div></div>'))
reg('gk-blocked', 'macOS blocks the first open: Apple could not verify tokenpanda', 'Install',
    plain('<div class="win" style="left:200px;top:90px;width:880px;height:520px;opacity:.5"><div class="wtb">Applications</div></div>'
          + dlg('"tokenpanda" Not Opened', 'Apple could not verify "tokenpanda" is free of malware that may harm your Mac or compromise your privacy.', [('Done', 'gk-settings', True), ('Move to Bin', 'finder-apps', False)])
          + tip('<b>Friction, by design.</b> Signed ad hoc, not notarised: spctl says "rejected" for build/tokenpanda.app. Since Sequoia, Control click no longer opens it.', 820, 220, 280)))
reg('gk-settings', 'System Settings, Privacy &amp; Security: Open Anyway, at the bottom', 'Install',
    plain(swin('Privacy &amp; Security', 'Privacy &amp; Security', '<h2>Privacy &amp; Security</h2><div class="grp">' + ''.join(f'<div class="grow"><i class="appic"></i>{b(160)}<span class="sp"></span>{b(40, 7)}</div>' for _ in range(5)) + '</div>'
                                                                  + '<div class="grp"><div class="grow"><span>Security</span></div><div class="grow"><span>"tokenpanda" was blocked to protect your Mac.</span><span class="sp"></span>' + A('gk-confirm', 'Open Anyway', 'btn pri') + '</div></div>')
          + tip('<b>Friction.</b> The button sits below the fold of Privacy &amp; Security, after a scroll, and appears only after a blocked try.', 900, 560, 300), app='System Settings'))
reg('gk-confirm', 'The warning again: Open', 'Install',
    plain(dlg('Open "tokenpanda"?', 'Apple is not able to verify that it is free from malware. Open it only if you are certain it is from a reliable source.', [('Move to Bin', 'finder-apps', False), ('Open Anyway', 'notif-permission', True)])))
reg('notif-permission', 'First launch: the notification permission prompt, before anything is explained', 'Install',
    desk(item('', dim=True, href='pop-nohook'), 'Thu 15 Oct 14:20', over=notif('"tokenpanda" would like to send you notifications', 'Notifications may include alerts, sounds and icon badges.', [('Allow', 'desk-nofeed'), ("Don't Allow", 'desk-nofeed')])
         + tip('<b>Friction.</b> Nudges are on by default and the app asks at launch (Controller.swift:124), before the user has seen the popover or knows what a nudge is. No window, no Dock icon: this prompt is the first sign the app runs.', 760, 140, 330)))
reg('desk-hidden', 'macOS 26 and later: the item is not shown until allowed under Menu Bar', 'Install',
    desk(f'<span class="ext"></span>', 'Thu 15 Oct 14:20', over=tip('<b>Friction.</b> The app runs, but the menu bar shows nothing: on macOS 26 and later it must be allowed in System Settings, Menu Bar (README, Install). A full menu bar behind the notch hides it too. No window or Dock icon says the app is running.', 760, 40, 330)
                                                         + '<div class="alts"><a class="altg" href="sys-menubar.html">System Settings, Menu Bar</a></div>'))
reg('sys-menubar', 'System Settings, Menu Bar: allow tokenpanda', 'Install',
    plain(swin('Menu Bar', 'Menu Bar', '<h2>Menu Bar</h2><div class="grp"><div class="grow"><span>Allow in the Menu Bar</span></div>' + ''.join(f'<div class="grow"><i class="appic"></i>{b(120)}<span class="sp"></span><i class="sw on"></i></div>' for _ in range(3))
                                                + '<div class="grow"><i class="appic"></i><span>tokenpanda</span><span class="sp"></span>' + A('desk-nofeed', '<i class="sw"></i>') + '</div></div>'), app='System Settings'))
reg('sys-loginitems', 'System Settings, General, Login Items: tokenpanda listed', 'Settings',
    plain(swin('Login Items', 'Login Items', '<h2>Login Items &amp; Extensions</h2><div class="grp"><div class="grow"><span>Open at Login</span></div><div class="grow"><i class="appic"></i><span>tokenpanda</span><span class="sp"></span><span class="note">Application</span></div>'
                                             + ''.join(f'<div class="grow"><i class="appic"></i>{b(110)}</div>' for _ in range(2)) + '</div>') + '<div class="alts"><a class="altg" href="pop-settings-login.html">Back to the popover</a></div>', app='System Settings'))


def editor(title, lines, note=''):
    return plain(term(title, lines, left=200, top=80, w=880, h=520) + note, app='TextEdit')


reg('editor-after', '~/.claude/settings.json after Install: one statusLine entry, the rest kept', 'Setup',
    editor('settings.json', [('', '{'), ('', '  "statusLine" : {'), ('', '    "type" : "command",'), ('', '    "command" : "\'~/Library/Application Support/dev.tokenpanda.app/hook.sh\'",'), ('', '    "refreshInterval" : 5'), ('', '  },'),
                             ('d', '  "model" : ...,'), ('d', '  "theme" : ...'), ('', '}')],
           tip('Read with the real Hook code on a throwaway folder: other keys kept, key order and indentation rewritten by the JSON writer. With a status line of your own, padding and your refreshInterval stay and your command is chained.', 760, 520, 330, n=True)
           + '<div class="alts"><a class="altg" href="pop-nosession.html">Back to the popover</a></div>'))
reg('editor-broken', '~/.claude/settings.json that is not valid JSON (a trailing comma)', 'Setup',
    editor('settings.json', [('', '{'), ('', '  "model" : "opus",'), ('bad', '}')], '<div class="alts"><a class="altg" href="pop-install-failed.html">Click Install the status line hook</a></div>'))
reg('editor-restored', '~/.claude/settings.json after Remove: your statusLine back exactly', 'Uninstall',
    editor('settings.json', [('', '{'), ('', '  "statusLine" : {'), ('', '    "type" : "command",'), ('', '    "command" : "~/bin/my-statusline.sh",'), ('', '    "padding" : 2'), ('', '  },'), ('d', '  "model" : ...'), ('', '}')],
           '<div class="alts"><a class="altg" href="editor-empty.html">There was no settings.json before</a><a class="altg" href="finder-bin.html">Quit, move the app to the Bin</a></div>'))
reg('editor-empty', '~/.claude/settings.json after Remove when there was none: an empty object stays', 'Uninstall',
    editor('settings.json', [('', '{'), ('', ''), ('', '}')], tip('<b>Friction, small.</b> The install created the file; the removal leaves "{}" behind instead of deleting what it made (Hook.swift:148 removes only the key).', 760, 520, 300)))
reg('term-claude', 'Terminal: a Claude Code session, the first reply', 'Setup',
    plain(term('Terminal, ~/workspace', [('p', '$ claude'), ('d', ' ...'), ('', '&gt; say ok'), ('', 'ok'), ('d', ' (your status line, unchanged, or nothing)')])
          + '<div class="alts"><a class="altg" href="pop-firstcall.html">Open the popover during the first call</a><a class="altg" href="pop-live.html">Open it after the reply</a></div>', app='Terminal'))
reg('notif-weekly', 'Nudge: Weekly at 80%', 'Nudges',
    desk(item('80%', over=True, href='pop-live'), 'Fri 16 Oct 15:40', over=notif('Weekly at 80%', '2 days 2 h to the reset. At this pace the limit lands Sat 21:30.')))
reg('notif-five', 'Nudge: 5h window ends in 15 min (Max or Pro)', 'Nudges',
    desk(item('61%', over=True, href='pop-live'), 'Thu 15 Oct 17:30', over=notif('5h window ends in 15 min', '34% used.')))
reg('notif-five-false', 'Nudge for a 5h window Ultra no longer has (30 Oct, 23:55)', 'Nudges',
    desk(item('25%', href='desk-ultra'), 'Fri 30 Oct 23:55', over=notif('5h window ends in 15 min', '63% used.')
         + tip('<b>Broken.</b> The frozen record (resets 00:10) passes the nudge test once a session feeds at 23:55 (Controller.swift:420-424). Read from the code and the stored record; not seen on screen in this run.', 760, 130, 330)))
reg('notif-reopen', 'After a restart: n Claude Code sessions were open before the restart, Reopen', 'Reopen',
    desk(item('', dim=True, href='desk-nofeed'), 'Mon 19 Oct 08:02', over=notif('3 Claude Code sessions were open before the restart', 'In tooling, website, workspace. Reopen opens each in Terminal.', [('Reopen', 'term-reopen')])
         + '<div class="alts"><a class="altg" href="desk-reopen-denied.html">Notifications are off</a></div>'))
reg('desk-reopen-denied', 'After a restart with notifications off: no offer, no word', 'Reopen',
    desk(item('', dim=True, href='pop-settings-restore'), 'Mon 19 Oct 08:02', over=tip('<b>Friction.</b> With notifications denied the offer is never posted (Notifier.swift:54 returns) and the Reopen row says nothing about it; the "Notifications are off" note sits only under the Nudge row.', 760, 40, 330)))
reg('term-reopen', 'Terminal: each session resumed, with Remote Control where it had it', 'Reopen',
    plain(term('Terminal, ~/workspace', [('d', '(a 0700 folder in the temporary folder, one script per session, each deletes itself)'), ('p', '$ claude --resume 3f1a9c2e-... --remote-control'), ('d', ' ...'),
                                          ('p', '$ claude --resume 7b2d4e6f-...'), ('d', ' ...')]) + tip('Seen on this Mac: nine tokenpanda-reopen scripts running under zsh -l after the last restart (pgrep).', 760, 560, 300, n=True), app='Terminal'))
reg('term-pmset', 'Terminal: pmset lists the tokenpanda assertion', 'Keep awake',
    plain(term('Terminal', [('p', '$ pmset -g assertions'), ('', '   pid 19948(tokenpanda): ... PreventUserIdleSystemSleep named: "tokenpanda: a Claude Code session is open"')]), app='Terminal'))
reg('term-brew-upgrade', 'Terminal: brew upgrade, then Open Anyway again', 'Update',
    plain(term('Terminal', [('p', '$ brew upgrade --cask tokenpanda'), ('d', '==&gt; Upgrading tokenpanda 0.1.6 -&gt; 0.1.7'), ('d', '==&gt; Quitting dev.tokenpanda.app'), ('ok', 'tokenpanda was successfully upgraded!')])
          + tip('<b>Friction.</b> Each new build is signed ad hoc with a new code hash, so the Open Anyway steps can come back after an update. The app has no version line, so nothing in it says which build runs.', 760, 520, 330)
          + '<div class="alts"><a class="altg" href="gk-blocked.html">Open the new build</a></div>', app='Terminal'))
reg('finder-bin', 'Finder: tokenpanda.app moved to the Bin', 'Uninstall',
    plain('<div class="win" style="left:200px;top:90px;width:880px;height:520px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>Bin</div><div class="fgrid">'
          + '<div class="fi on"><i></i>tokenpanda</div></div></div>'
          + '<div class="alts"><a class="altg" href="term-leftover.html">Moved without Remove first</a><a class="altg" href="term-zap.html">brew uninstall --zap</a></div>'))
reg('term-leftover', 'After the app is gone: the hook keeps writing, files pile up', 'Uninstall',
    plain(term('Terminal', [('p', '$ ls ~/Library/Application\\ Support/dev.tokenpanda.app/sessions'), ('', '0a1f...json  0b77...json  1c02...json  ...  (214 files)'), ('d', '(one file per Claude Code session since the app was removed; only the app deletes them)')])
          + tip('<b>Friction.</b> The statusLine entry still runs hook.sh, so every session leaves a file that nothing removes. Illustration: the count is an example; the behaviour is from Hook.swift and FeedReader.swift:92-95.', 760, 520, 330), app='Terminal'))
reg('term-zap', 'brew uninstall --zap: the hook script is gone, so is your own status line', 'Uninstall',
    plain(term('Terminal, ~/workspace', [('p', '$ brew uninstall --zap tokenpanda'), ('d', '==&gt; Trashing ~/Library/Application Support/dev.tokenpanda.app'), ('p', '$ claude'), ('', '&gt; ...'),
                                         ('bad', ' (status line empty: statusLine still points at the deleted hook.sh, and your own command was chained inside it)')])
          + tip('<b>Broken.</b> zap deletes the folder that holds hook.sh while settings.json still points at it. Claude Code runs a missing script; the status line the user had before is gone too, because it ran only through the hook. The caveat asks to Remove first; nothing enforces it.', 760, 500, 330), app='Terminal'))


# ---------- outcomes and the next place a flow goes: dashed targets, shown with h or in walk mode ----------
ALT = {
    'desk': [('Use of the 5h window stopped for Ultra', 'desk-ultra'), ('Mac under pressure', 'desk-warning'), ('Weekly at 100%', 'desk-weekly-limit')],
    'desk-nofeed': [('Open the popover', 'pop-nohook'), ('On macOS 26 the item is hidden', 'desk-hidden')],
    'desk-ultra': [('Ten sessions open', 'desk-flicker-a'), ('30 Oct evening', 'pop-ultra-evening'), ('A new Ultra user', 'pop-ultra-new'), ('Max or Pro', 'pop-live-max')],
    'pop-live': [('Hover a session figure', 'pop-session-tip'), ('An hour without a session', 'pop-stale'), ('Weekly passes 80%', 'notif-weekly'), ('15 min before the 5h reset', 'notif-five')],
    'pop-ultra-evening': [('Near the stored reset', 'pop-ultra-late'), ('It was at 100%', 'desk-five-limit')],
    'pop-ultra-new': [('The fix', 'pop-ultra-fixed')],
    'pop-stale': [('Last session 20 minutes ago', 'pop-asof'), ('An account without limits', 'pop-nolimits'), ('No transcripts folder', 'pop-notranscripts')],
    'pop-mac': [('Battery health unknown', 'pop-mac-health')],
    'pop-settings': [('Notifications denied', 'pop-settings-denied'), ('With VoiceOver', 'pop-voiceover'), ('With the keyboard', 'pop-keyboard')],
    'pop-settings-awake-open': [('pmset', 'term-pmset')],
    'desk-quit': [('Open the app again', 'desk')],
    'notif-permission': [('Then the item', 'desk-nofeed')],
    'desk-weekly-limit': [('The reset nears', 'pop-week-near')],
}

# the next place each flow goes, where the screen itself has no control for it
NEXT = [
    ('term-brew', 'Or from the zip: Applications', 'finder-apps'),
    ('pop-nohook-chained', 'Click Install', 'editor-after'),
    ('pop-live', 'A settings.json that is not JSON', 'editor-broken'),
    ('pop-live', 'Ten sessions open', 'desk-flicker-a'),
    ('pop-flicker-b', 'Back to one session', 'pop-live'),
    ('notif-permission', 'Days later, weekly at 80%', 'notif-weekly'),
    ('notif-weekly', '15 min before the 5h reset', 'notif-five'),
    ('notif-five', 'On an Ultra account', 'notif-five-false'),
    ('notif-five-false', 'Notifications denied', 'pop-settings-denied'),
    ('pop-settings-denied', 'An hour without a session', 'pop-stale'),
    ('pop-ultra-late', 'It was at 100%', 'desk-five-limit'),
    ('desk-five-limit', 'At 23:55', 'notif-five-false'),
    ('notif-five-false', 'The next morning', 'pop-ultra-today'),
    ('pop-ultra-fixed', 'A new Ultra user, today', 'pop-ultra-new'),
    ('pop-ultra-new', 'A Max or Pro account', 'pop-live-max'),
    ('pop-week-rolled', 'Same reset, sessions open', 'pop-week-rolled-live'),
    ('pop-week-new', 'Week over week with several sessions', 'pop-flicker-b'),
    ('pop-flicker-b', 'A week at 100%', 'desk-weekly-limit'),
    ('pop-asof', 'An hour later', 'pop-stale'),
    ('pop-nolimits', 'No transcripts folder', 'pop-notranscripts'),
    ('pop-notranscripts', 'statusLine removed by hand', 'pop-nohook'),
    ('pop-mac', 'Memory pressure', 'desk-warning'),
    ('pop-mac-warning', 'Battery health unknown', 'pop-mac-health'),
    ('pop-mac-health', 'Mac figures in the bar on', 'desk-mac'),
    ('desk-quit', 'Open it again, Settings', 'pop-settings'),
    ('term-reopen', 'Notifications are off', 'desk-reopen-denied'),
    ('desk-reopen-denied', 'Settings, untick Reopen', 'pop-settings'),
    ('browser-release', 'brew upgrade instead', 'term-brew-upgrade'),
    ('gk-blocked', 'After the update', 'pop-live'),
    ('editor-empty', 'Quit, move the app to the Bin', 'finder-bin'),
    ('term-leftover', 'brew uninstall --zap', 'term-zap'),
    ('term-zap', 'Delete the rest by hand', 'finder-bin'),
    ('desk-ultra', 'Open the popover', 'pop-live'),
    ('pop-live', 'With VoiceOver', 'pop-voiceover'),
    ('pop-voiceover', 'With the keyboard', 'pop-keyboard'),
]
for a, label, b2 in NEXT:
    ALT.setdefault(a, []).append((label, b2))
for sid, items in ALT.items():
    low = 'class="alts"' in SC[sid]['body']
    SC[sid]['body'] += f'<div class="alts" style="bottom:{52 if low else 14}px">' + ''.join(f'<a class="altg" href="{h}.html">{l}</a>' for l, h in items) + '</div>'


# ---------- write ----------

def page(sid, s):
    k = json.dumps(s['keys']).replace("'", '&#39;')
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=1280">'
            f'<title>{re.sub("<[^>]+>", "", s["title"])}</title><link rel="stylesheet" href="../wire.css"></head>'
            f"<body data-keys='{k}'>{s['body']}<script src=\"../wire.js\"></script></body></html>\n")


def main():
    import sys
    sys.path.insert(0, str(HERE))
    from flows_data import FLOWS, write_all
    out = HERE / 'screens'
    out.mkdir(exist_ok=True)
    for old in out.glob('*.html'):
        if old.stem not in SC:
            old.unlink()
    for sid, s in SC.items():
        (out / f'{sid}.html').write_text(page(sid, s))
    missing = sorted({sc for f in FLOWS for st in f['steps'] for sc in st['screens'] if sc not in SC})
    if missing:
        raise SystemExit(f'flow steps name screens that do not exist: {missing}')
    bad = sorted({m for s in SC.values() for m in re.findall(r'href="([\w-]+)\.html"', s['body']) if m not in SC})
    bad += sorted({v[:-5] for s in SC.values() for v in s['keys'].values() if v[:-5] not in SC})
    if bad:
        raise SystemExit(f'links to screens that do not exist: {bad}')
    for sid, s in SC.items():
        text = re.sub(r'<[^>]+>', ' ', s['body'] + s['title'])
        for ch in ['—', '–', '·', '|']:
            assert ch not in text, f'forbidden character {ch!r} in {sid}'
    write_all(HERE, SC, FLOWS)
    print(f'{len(SC)} screens, {len(FLOWS)} flows, {sum(len(f["steps"]) for f in FLOWS)} steps')


if __name__ == '__main__':
    main()
