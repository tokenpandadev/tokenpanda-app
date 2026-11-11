#!/usr/bin/env python3
"""Builds the clickable wireframes of tokenpanda as it is built (0.1.15, main at 274b15c).
Every popover screen draws what 0.1.15 draws: the wording of Sources/Text/Grammar.swift and
Sources/UI/ScreenBuilder.swift, the colours of Sources/Text/Tokens.swift (dark appearance), the bar of
Sources/Text/Bar.swift. Names of models, projects, sessions and processes stay filler bars; every figure is sample
data (Sources/UI/Fixtures.swift), never a real reading.

    python3 build.py

Writes next to this file: screens/*.html, flows.js, index.html, walk.html, flow-test.md,
flows/flows.md and flows/NN-*.mmd. The screens share one set of parts (menu bar, the item,
the popover and its lines, system dialogs, terminal, editor), so a change to a part changes
every screen. Flow steps, their screens and the flow test results live in flows_data.py.
"""
import json
import math
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


def rnd(x):
    """Swift's rounded(): half away from zero."""
    return int(math.floor(x + 0.5))


def wrap(s, w):
    """Format.wrap (Sources/Text/Bar.swift): at spaces, never cut; a word longer than w is split."""
    if len(s) <= w:
        return [s]
    out, line = [], ''
    for word in s.split(' '):
        while len(word) > w:
            if line:
                out.append(line)
                line = ''
            out.append(word[:w])
            word = word[w:]
        if not line:
            line = word
        elif len(line) + 1 + len(word) <= w:
            line += ' ' + word
        else:
            out.append(line.strip())
            line = word
    line = line.strip()
    if line:
        out.append(line)
    return out


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
POP_L = ITEM_X - 190   # the popover's left edge
POP_T = 34             # its top
CH = 7.22              # one SF Mono 12 cell, in px


def desk(it, clock='Thu 15 Oct 14:20', over='', app='Finder', wins=True, cls=''):
    return f'<div class="vp{" " + cls if cls else ""}">{bgwins() if wins else ""}{mbar(it, clock, app)}{over}</div>'


def tip(text, left, top, w=290, n=False):
    return f'<div class="tip{" n" if n else ""}" style="left:{left}px;top:{top}px;max-width:{w}px">{text}</div>'


def mark(left, top, w, h):
    return f'<div class="mark" style="left:{left}px;top:{top}px;width:{w}px;height:{h}px"></div>'


def pmark(line, n=1, cell=0, cells=48):
    """A mark around popover lines line..line+n-1 (0 based, the header line is 0), cells counted from the left padding."""
    return mark(POP_L + 10 + round(cell * CH) - 4, POP_T + 12 + 16 * line - 3, round(cells * CH) + 8, 16 * n + 6)


# ---------- Tokens.swift (dark), the colours every popover line uses ----------

TOK = dict(text='#e0e0e0', bold='#ededed', dim='#b3b3b3', dimmer='#949494', quiet='#b8b8b8', accent='#b1b9f9',
           track='#505370', trackStale='rgba(80,83,112,.35)', staleFill='#7e82b0', coral='#d77757', warning='#ffc107', box='#373737',
           magenta='#bd7bcd', yellow='#c4ac62', cyan='#7ccbcd', green='#6caa71', blue='#6d96b4', blue2='#67b5ed',
           procWhite='#dee5eb')
MODEL_HUES = [TOK['magenta'], TOK['yellow'], TOK['cyan'], TOK['green']]   # Fable, Opus, Sonnet, Haiku


# ---------- the popover lines, as Sources/Text/Grammar.swift draws them ----------

def L(*pieces, hov=False, cls=''):
    c = 'ln' + (' hov' if hov else '') + (' ' + cls if cls else '')
    return f'<div class="{c}">' + ''.join(pieces) + '</div>'


def T(s, cls=''):
    return f'<span class="{cls}">{esc(s)}</span>' if cls else f'<span>{esc(s)}</span>'


def G(glyph, cells=1, cls=''):
    """A glyph the app draws in a fixed number of cells (the warning sign, the memory cells, the command key)."""
    return f'<span class="g {cls}" style="width:{cells}ch">{glyph}</span>'


BL = L(T(' '))


def bar(n, used, elapsed=None, over=False, stale=False, color=None, plain=False):
    """Bar.render: full cells plus eighths, the notch (half blocks either side of the tick cell boundary) at the
    elapsed share, coral past it when over pace, the track behind unless plain."""
    used = max(0.0, min(100.0, float(used)))
    f = used / 100 * n
    full = int(math.floor(f))
    e8 = rnd((f - full) * 8)
    w = n if full >= n else full + e8 / 8
    t = None if elapsed is None else max(1, min(n - 1, rnd(elapsed / 100 * n)))
    fill = color or (TOK['staleFill'] if stale else TOK['accent'])
    past = TOK['coral'] if over and not stale else fill
    seg = lambda a, ww, c: f'<i style="left:{a:g}ch;width:{ww:g}ch;background:{c}"></i>' if ww > 0 else ''
    parts = []
    if not plain:
        tc = TOK['trackStale'] if stale else TOK['track']
        for a, z in ([(0, t - 1), (t + 1, n)] if t is not None else [(0, n)]):
            parts.append(seg(a, z - a, tc))
    if t is None:
        parts.append(seg(0, w, fill))
    else:
        parts.append(seg(0, min(w, t - 1), fill))
        if w > t + 1:
            parts.append(seg(t + 1, w - (t + 1), past))
        parts.append(f'<i class="nt" style="left:{t - 0.5:g}ch;background:{TOK["dim"] if stale else TOK["bold"]}"></i>')
    return f'<span class="wb" style="width:{n}ch">{"".join(parts)}</span>'


TABS = {'pop': ('pop-live', 'pop-mac', 'pop-settings'),
        'ultra': ('pop-ultra-today', 'pop-mac-ultra', 'pop-settings-ultra'),
        'nohook': ('pop-nohook', 'pop-mac', 'pop-settings-nohook'),
        'warn': ('pop-live-warn', 'pop-mac-warning', 'pop-settings')}


def header(line, tab, warn=False, prefix='pop'):
    """6.1: the header line dim, the rule in the accent, the tab strip; the selected tab inverted on the accent."""
    tabs = [T(' ')]
    for i, name in enumerate(['Claude', 'Mac', 'Settings']):
        if i:
            tabs.append(T('  '))
        inner = ' Mac <span class="g dotc" style="width:1ch"></span> ' if name == 'Mac' and warn else esc(f' {name} ')
        tabs.append(A(TABS[prefix][i] if i != tab else None, inner, 'tab' + (' on' if i == tab else '')))
    return L(T(' '), T(line, 'dim')) + L(cls='rule') + L(*tabs)


def win(title, mode='live', used=0, elapsed=None, over=False, reset='', countdown='', status='', proj='', allow='', asof=''):
    """6.3, Grammar.windowSection, every mode."""
    out = [L(T(' '), T(title, 'bold'))]
    if mode == 'live':
        out.append(L(T(' '), bar(36, used, elapsed, over), T(f' {used}% used')))
        out.append(L(T(' '), T(f'{reset}  {countdown}', 'dim')))
        out.append(L(T(' '), T(status, 'bold'), T(f'  {proj}', 'dim')) if proj else L(T(' '), T(status, 'bold')))
        out.append(L(T(' '), T(allow, 'dim')))
    elif mode == 'stale':
        out.append(L(T(' '), bar(36, used, elapsed, stale=True), T(f' {used}% used', 'dim')))
        out.append(L(T(' '), T(reset, 'dim')))
        out.append(L(T(' '), T('as of ' + asof, 'dim')))
    elif mode == 'passed':
        out.append(L(T(' '), bar(36, 0)))
        out.append(L(T(' '), T(reset + '  no session since', 'dim')))
    elif mode == 'nextreply':
        out.append(L(T(' '), bar(36, 0)))
        out.append(L(T(' '), T(reset + '  new window on the next reply', 'dim')))
    elif mode == 'absent':
        out.append(L(T(' '), bar(36, 0)))
        out.append(L(T(' '), T('not in the last feed', 'dim')))
    elif mode == 'quiet':
        out.append(L(T(' '), bar(36, used, stale=True), T(f' {used}% used', 'dim')))
        out.append(L(T(' '), T('not in the last feed', 'dim')))
    elif mode in ('nosession', 'firstreply'):
        out.append(L(T(' '), bar(36, 0)))
        out.append(L(T(' '), T('no session yet  open Claude Code once' if mode == 'nosession' else 'waiting for the first reply', 'dim')))
    return ''.join(out)


def dim_lines(text, indent):
    """Grammar.dimLines: dim text at an indent, wrapped to the rule's width (48 cells)."""
    return ''.join(L(T(' ' * indent), T(x, 'dim')) for x in wrap(text, 48 - indent))


STALE_NOTE = L(T(' '), T('limits are shared with the Claude app and other', 'dim')) + L(T(' '), T('Macs, so the real figure may be higher', 'dim'))
PRIVACY = L(T(' '), T('This app makes no network calls. Usage comes', 'dim')) + L(T(' '), T("from Claude Code's own status feed on this Mac.", 'dim'))
NOTIF_OFF = 'Notifications are off in System Settings'


def nohook(prev=False, err=None, focus=False, href='pop-nosession'):
    """Grammar.limits .noHook: the Install button inverted on the accent, its error under it."""
    btn = A(href, ' Install the status line entry ', 'btnl' + (' focus' if focus else ''))
    return (L(T(' '), T('Weekly and 5h window', 'bold')) + L(T(' '), T("needs Claude Code's status line feed", 'dim'))
            + dim_lines('one statusLine entry in ~/.claude/settings.json', 1)
            + L(T(' '), T('your current status line is kept and chained' if prev else 'chained if one exists', 'dim'))
            + L(T(' '), btn) + (dim_lines(err, 1) if err else '') + BL + PRIVACY)


def two_lines(title, a, b2=None):
    return L(T(' '), T(title, 'bold')) + L(T(' '), T(a, 'dim')) + (L(T(' '), T(b2, 'dim')) if b2 else '')


# (name filler cells, model filler cells, hue, context %, figure)
S_TWO = [(9, 9, TOK['magenta'], 41, '405.6k of 1M'), (7, 8, TOK['yellow'], 9, '88.4k of 1M')]
S_ONE = [(9, 9, TOK['magenta'], 18, '180k of 1M')]


def sessions(rows=S_TWO, waiting=False, tipline=False, more=0):
    """6.14, Grammar.sessionRows: name and model, then the 24 cell plain bar in the model's hue, figure and percent."""
    out = [L(T(' '), T('Open sessions', 'bold'))]
    if not rows:
        return ''.join(out) + L(T(' '), T('no open session', 'dim'))
    for i, (n, m, hue, used, fig) in enumerate(rows):
        out.append(L(T(' '), fb(n, 'k'), T('  '), fb(m)))
        if waiting:
            out.append(L(T(' '), T('waiting for the first reply', 'dim')))
        else:
            out.append(L(T(' '), bar(24, used, color=hue, plain=True), T('  ' + fig + '  ' + f'{used}%'.rjust(3)), hov=tipline and i == 0))
    if more:
        out.append(L(T(' '), T(f'and {more} more', 'dim')))
    return ''.join(out)


TOKEN_DATA = [[(9, 49, '1.02B'), (8, 34, '0.71B'), (10, 11, '0.24B'), (9, 6, '0.13B')],
              [(9, 70, '1.46B'), (7, 20, '0.42B'), (7, 7, '0.14B'), (5, 4, '0.08B')],
              [(8, 43, '31.2M'), (8, 25, '18.0M'), (8, 17, '12.6M'), (5, 15, '10.6M')]]


def tokens(section=0, empty=None, chip=True, linked=True):
    """6.5 to 6.7: the title, the section switch (the selected one inverted on bold), the rows, the chips."""
    title = ['Tokens by model  7 days', 'Tokens by project  7 days', 'Tokens by session  today'][section]
    hrefs = ('pop-live', 'pop-projects', 'pop-sessions') if linked else (None, None, None)
    subs = [T(' ')]
    for i, name in enumerate(['Models', 'Projects', 'Sessions']):
        if i:
            subs.append(T('  '))
        subs.append(A(hrefs[i] if i != section else None, esc(f' {name} '), 'sub' + (' on' if i == section else '')))
    out = [L(T(' '), T(title, 'bold')), L(*subs)]
    if empty:
        return ''.join(out) + L(T(' '), T(empty, 'dim'))
    for k, (n, share, fig) in enumerate(TOKEN_DATA[section]):
        hue = MODEL_HUES[k] if section == 0 else TOK['blue'] if section == 1 else TOK['blue2']
        out.append(L(T(' '), fb(n, 'k'), T(' ' * (15 - n)), bar(24, share, color=hue, plain=True), T('  ' + fig.rjust(5))))
    if chip:
        out.append(L(T(' '), T('[list price equivalent  USD 1,140]', 'dim')))
    out.append(L(T(' '), T('[44% by subagents]', 'dim')))
    return ''.join(out)


def weeks(rows):
    """6.8, Grammar.week: date in 6 cells, the 20 cell bar, the hit sign, the percent in 4, the note dim."""
    out = [L(T(' '), T('Week over week', 'bold'))]
    for date, used, hit, note, el, over in rows:
        pieces = [T(' '), T(f'{date:<6}  ')]
        if used is None:
            pieces += [bar(20, 0), T('  ')]
        else:
            pieces += [bar(20, used, el, over), G('&#9888;', 1, 'warnc') if hit else T(' '), T(' ' + f'{used}%'.rjust(4))]
        if note:
            pieces.append(T('  ' + note, 'dim'))
        out.append(L(*pieces))
    return ''.join(out)


W_SAMPLE = [('21 Sep', 88, False, '', None, False), ('28 Sep', 100, True, 'Thu 16:10', None, False), ('5 Oct', 96, False, '', None, False), ('12 Oct', 61, False, 'so far', 55, True)]
W_FIRST = [('12 Oct', None, False, 'no feed yet', None, False)]   # a first run: no week recorded, no feed
W_ULTRA = [('12 Oct', 80, False, '', None, False), ('19 Oct', 35, False, '', None, False), ('26 Oct', 28, False, 'so far', 82, False)]


def foot(tab):
    return BL + L(T(' '), T('Esc closes  Tab switches  m p s sections' if tab == 0 else 'Esc closes  Tab switches', 'quiet'))


def nlines(html):
    return html.count('<div class="ln')


def pop(lines, left=None, arrow=None, height=None, scroll=0, extra=''):
    """The popover at 380 pt. With height, the panel is capped (PanelSize: the screen's visible height less 60) and its
    lines scroll under an overlay scroller."""
    left = POP_L if left is None else left
    arrow = ITEM_X - left - 7 if arrow is None else arrow
    if height is None:
        return f'<div class="pop" style="left:{left}px;--arrow:{arrow}px">{lines}{extra}</div>'
    content = 22 + 16 * nlines(lines)
    thumb = round(height * height / content)
    scroll = max(0, min(scroll, content - height))
    top = round(scroll / content * height)
    return (f'<div class="pop capped" style="left:{left}px;--arrow:{arrow}px;height:{height}px">'
            f'<div class="clip"><div class="scrolled" style="transform:translateY(-{scroll}px)">{lines}{extra}</div></div>'
            f'<i class="scroller" style="top:{top + 3}px;height:{thumb - 6}px"></i></div>')


def ptip(rows, line, left_px=10):
    """A figure's tooltip (LineView.drawTip): the box ground, above its line, at the panel's left padding when tipLeft."""
    cells = max(len(r) for r in rows)
    top = 12 + 16 * line - 16 * len(rows) - 2
    body = ''.join(f'<div>{esc(r)}</div>' for r in rows)
    return f'<div class="ptip" style="left:{left_px}px;top:{top}px;width:{cells + 2}ch">{body}</div>'


# ---------- popover screens ----------

LIVE = 'Live from Claude Code'
WAITING = 'Waiting for a Claude Code session'
ASOF = lambda t: f'As of {t}, last Claude Code session'


def claude(limits, sess=S_TWO, tok=0, wk=None, hdr=LIVE, tab_prefix='pop', warn=False, chip=True, tok_empty=None, tipline=False,
           waiting=False, nohook_tab=False):
    """Grammar.claudeTab under the header: limits, open sessions (not in the No hook state), tokens, week over week."""
    body = header(hdr, 0, warn, tab_prefix) + BL + limits + BL
    if not nohook_tab:
        body += sessions(sess, waiting, tipline) + BL
    body += tokens(tok, tok_empty, chip, tab_prefix == 'pop') + BL + weeks(wk or W_SAMPLE) + foot(0)
    return body


WEEKLY_OVER = dict(used=61, elapsed=55, over=True, reset='Resets Sun 18:00', countdown='in 3d 3h', status='Over pace', proj='limit Sun 01:20 at this rate', allow='0.5% an hour left')
FIVE_AHEAD = dict(used=24, elapsed=32, reset='Resets 17:45', countdown='in 3h 25m', status='Ahead', proj='76% by reset at this rate', allow='22% an hour left')
WEEKLY_ULTRA = dict(used=28, elapsed=82, reset='Resets Sun 17:00', countdown='in 1d 5h', status='Ahead', proj='34% by reset at this rate', allow='2% an hour left')
TODAY = 'Sat 31 Oct 11:11'
U_WK = [('12 Oct', 80, False, '', None, False), ('19 Oct', 35, False, '', None, False), ('26 Oct', 28, False, 'so far', 82, False)]

LIVE_LIMITS = win('Weekly (all models)', **WEEKLY_OVER) + BL + win('5h window', **FIVE_AHEAD)
POP_KEYS = keys(Escape='desk', Tab='pop-mac', Shift_Tab='pop-settings', m='pop-live', p='pop-projects', s='pop-sessions', Meta_q='desk-quit')

reg('desk', 'Menu bar, the item: panda and the weekly percentage, over pace in semibold', 'Menu bar',
    desk(item('61%', over=True, href='pop-live')))
reg('pop-live', 'Claude tab, live: weekly over pace, 5h ahead (Max or Pro)', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS))), POP_KEYS)
reg('pop-session-tip', 'Claude tab, hover on a session figure: list price, lines, effort, over two lines', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tipline=True), extra=ptip(['USD 38.20 list price equivalent  112 added', '9 removed  effort high'], 18))
         + tip('A tooltip wider than the panel breaks over lines at its double spaces (LineView.tipLines), above its line, inside the panel; with no room above it opens below. The keyboard ring on the figure shows it too.', 520, 290, 320, n=True)), POP_KEYS)
reg('pop-projects', 'Claude tab, tokens by project, 7 days (p)', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tok=1))), POP_KEYS)
reg('pop-sessions', 'Claude tab, tokens by session, today (s)', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tok=2))), POP_KEYS)
reg('pop-nochip', 'Claude tab with List price equivalent off: no price chip', 'Claude tab',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, chip=False))), POP_KEYS)

# first run and setup
NK = keys(Escape='desk-nofeed', Tab='pop-mac', Shift_Tab='pop-settings-nohook', Meta_q='desk-quit')


def claude_nohook(prev=False, err=None, focus=False, href='pop-nosession'):
    return claude(nohook(prev, err, focus, href), hdr=WAITING, tab_prefix='nohook', wk=W_FIRST, nohook_tab=True)


INSTALL_ERR = 'Could not install the entry: cannot read settings.json: settings.json is not valid JSON'
DANGLING_ERR = 'Could not install the entry: cannot write settings.json: it is a link into ~/dotfiles/sub, a folder that does not exist'

reg('desk-nofeed', 'Menu bar, first launch: the panda alone, dimmed', 'Menu bar', desk(item('', dim=True, href='pop-nohook')))
reg('pop-nohook', 'Claude tab, first open: Install the status line entry', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook())
         + '<div class="alts"><a class="altg" href="editor-broken.html">settings.json is not valid JSON</a><a class="altg" href="pop-nohook-chained.html">You already have a status line</a></div>'), NK)
reg('pop-nohook-chained', 'Claude tab, first open with a status line of your own: kept and chained', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook(True))), NK)
reg('pop-install-failed', 'Claude tab after Install with a settings.json that is not valid JSON: the reason under the button', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook(err=INSTALL_ERR, href='pop-install-failed')) + pmark(9, 2)
         + tip('The error stands where the click was, under the button, wrapped with its reason (Grammar.dimLines). "is not valid JSON" for a file the reader refuses, "is not a JSON object" for valid JSON that is not an object (Hook.unreadable).', 500, 180, 330, n=True)
         + '<div class="alts"><a class="altg" href="pop-settings-error.html">Open Settings</a></div>'), NK)
reg('pop-install-dangling', 'Claude tab after Install with a settings.json that is a link into a folder that does not exist: refused, nothing written', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook(err=DANGLING_ERR, href='pop-install-dangling')) + pmark(9, 2)
         + tip('Install refuses before it writes anything: no folder made, no script, no backup, no remove.sh (Hook.writableTarget, SettingsFile.reason). Claude Code\'s own write there would fail too. The same line stands under the button in Settings.', 500, 180, 330, n=True)
         + '<div class="alts"><a class="altg" href="pop-settings-dangling.html">Open Settings</a></div>'), NK)
reg('pop-hooks-disabled', 'Claude tab with disableAllHooks on: Claude Code runs no status line', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude(two_lines('Weekly and 5h window', 'disableAllHooks is on in settings.json', 'so Claude Code runs no status line'), sess=[], hdr=WAITING, wk=W_FIRST))), POP_KEYS)
reg('pop-nosession', 'Claude tab, entry installed, no session yet', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude(win('Weekly (all models)', 'nosession') + BL + win('5h window', 'nosession'), sess=[], hdr=WAITING, wk=W_FIRST))
         + '<div class="alts"><a class="altg" href="term-claude.html">Start Claude Code</a></div>'), POP_KEYS)
reg('pop-firstcall', 'Claude tab during the first call: sessions open, both windows wait for the first reply', 'Setup',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude(win('Weekly (all models)', 'firstreply') + BL + win('5h window', 'firstreply'), waiting=True, wk=W_FIRST))
         + '<div class="alts"><a class="altg" href="pop-live.html">After the first reply</a></div>'), POP_KEYS)

# the 5h window, Ultra since 30 Oct 2026
UK = keys(Escape='desk-ultra', Tab='pop-mac-ultra', Shift_Tab='pop-settings-ultra', Meta_q='desk-quit')
reg('desk-ultra', 'Menu bar today, Ultra: the weekly, nothing about a 5h window', 'Menu bar', desk(item('28%', href='pop-ultra-today'), TODAY))
reg('pop-ultra-today', 'Claude tab today, Ultra: the weekly alone, no 5h section', '5h window',
    desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(claude(win('Weekly (all models)', **WEEKLY_ULTRA), sess=S_ONE, wk=U_WK, tab_prefix='ultra'))
         + tip('A window a reply came without is one the plan no longer has: after its old reset the row goes (Limits.apply, ScreenBuilder.limitsView). A new Ultra user sees the weekly alone from the first reply. No 5h nudge, no - - eyes (Limits.active).', 500, 120, 330, n=True)), UK)
U_EVE = win('Weekly (all models)', used=24, elapsed=74, reset='Resets Sun 17:00', countdown='in 1d 19h', status='Ahead', proj='32% by reset at this rate', allow='2% an hour left') + BL + win('5h window', 'quiet', used=63)
reg('pop-ultra-evening', '30 Oct, 21:30, Ultra: the 5h window keeps its last figure dim, not in the last feed', '5h window',
    desk(item('24%', on=True, href='desk-ultra'), 'Fri 30 Oct 21:30', over=pop(claude(U_EVE, wk=[U_WK[0], U_WK[1], ('26 Oct', 24, False, 'so far', 74, False)], tab_prefix='ultra')) + pmark(10, 3)
         + tip('The feed stopped carrying five_hour before the stored window reset: the last percent stays, dim, with "not in the last feed", no countdown, pace or projection (ScreenBuilder .quiet). The eyes, the spoken label and the nudges stop using it at once.', 500, 170, 330, n=True)), UK)
reg('pop-live-max', 'Claude tab, Max or Pro today: both windows, as before', '5h window',
    desk(item('28%', on=True, href='desk'), TODAY, over=pop(claude(win('Weekly (all models)', **WEEKLY_ULTRA) + BL + win('5h window', used=41, elapsed=55, reset='Resets 13:26', countdown='in 2h 15m', status='Ahead', proj='75% by reset at this rate', allow='26% an hour left'), sess=S_ONE, wk=U_WK))), POP_KEYS)
reg('desk-five-limit', 'Menu bar, Max or Pro, the 5h window at 100%: - - eyes until its reset', 'Menu bar',
    desk(item('24%', eyes='five', href='pop-live')))

# weekly reset
U_ROLLED = [U_WK[0], U_WK[1], ('26 Oct', 91, False, '', None, False), ('2 Nov', None, False, 'no reply yet', None, False)]
reg('pop-week-near', 'Claude tab, 40 minutes before the weekly reset', 'Weekly reset',
    desk(item('91%', on=True, href='desk-ultra'), 'Sun 1 Nov 16:20', over=pop(claude(win('Weekly (all models)', used=91, elapsed=99, reset='Resets Sun 17:00', countdown='in 0h 40m', status='Ahead', proj='91% by reset at this rate', allow='14% an hour left'), sess=S_ONE, wk=[U_WK[0], U_WK[1], ('26 Oct', 91, False, 'so far', 99, False)], tab_prefix='ultra'))
         + '<div class="alts"><a class="altg" href="pop-week-rolled.html">17:00 passes, no session open</a><a class="altg" href="pop-week-rolled-live.html">17:00 passes, sessions open and idle</a></div>'), UK)
reg('pop-week-rolled', 'Claude tab, weekly reset passed with no session since: the new week says no reply yet', 'Weekly reset',
    desk(item('', dim=True, on=True, href='desk-ultra'), 'Sun 1 Nov 18:30', over=pop(claude(win('Weekly (all models)', 'passed', reset='Reset Sun 17:00'), sess=[], wk=U_ROLLED, hdr=ASOF('16:52'), tab_prefix='ultra'))
         + tip('The old week keeps its own figure, 91%; the new week is labelled by its own Monday and has no figure until the next reply (ScreenBuilder.weekViews).', 500, 380, 320, n=True)), UK)
reg('pop-week-rolled-live', 'Claude tab, weekly reset passed while idle sessions feed: new window on the next reply', 'Weekly reset',
    desk(item('', dim=True, on=True, href='desk-ultra'), 'Sun 1 Nov 17:20', over=pop(claude(win('Weekly (all models)', 'nextreply', reset='Reset Sun 17:00'), wk=U_ROLLED, tab_prefix='ultra'))
         + '<div class="alts"><a class="altg" href="pop-week-new.html">The next reply</a></div>'), UK)
reg('pop-week-new', 'Claude tab, the new week arrived: 1% used, last week kept', 'Weekly reset',
    desk(item('1%', on=True, href='desk-ultra'), 'Sun 1 Nov 17:24', over=pop(claude(win('Weekly (all models)', used=1, elapsed=0.4, reset='Resets Sun 17:00', countdown='in 6d 23h', status='On pace', proj='too early to project', allow='0.6% an hour left'), wk=[U_WK[0], U_WK[1], ('26 Oct', 91, False, '', None, False), ('2 Nov', 1, False, 'so far', 0.4, False)], tab_prefix='ultra'))), UK)
# pace row (PaceModel.reading, 0.1.15): too early to project, N% by reset, Over pace keeps its limit
reg('pop-pace-early', 'Claude tab, 100 minutes into a new week and 11 minutes into a 5h window: On pace, too early to project', 'Pace',
    desk(item('2%', on=True, href='desk-ultra'), 'Sun 1 Nov 18:41', over=pop(claude(win('Weekly (all models)', used=2, elapsed=1, reset='Resets Sun 17:00', countdown='in 6d 22h', status='On pace', proj='too early to project', allow='0.6% an hour left') + BL
                                                                   + win('5h window', used=3, elapsed=3.7, reset='Resets 23:20', countdown='in 4h 49m', status='On pace', proj='too early to project', allow='20% an hour left'), sess=S_ONE, wk=[U_WK[0], U_WK[1], ('26 Oct', 91, False, '', None, False), ('2 Nov', 2, False, 'so far', 1, False)]))
         + tip('Until 5% of a window has passed (8 h 24 min of a week, 15 min of a 5h window) only Over pace projects. On pace reads "too early to project"; VoiceOver says "On pace, too early to project" (PaceModel.earliestProjection, tooEarly). The weekly nudge names no projection then. Ahead cannot occur this early: it needs 5 points under the elapsed share.', 500, 250, 330, n=True)), POP_KEYS)
reg('pop-pace-reset', 'Claude tab, On pace and Ahead read the share at the reset: 100% by reset at this rate', 'Pace',
    desk(item('57%', on=True, href='desk'), over=pop(claude(win('Weekly (all models)', used=57, elapsed=55, reset='Resets Sun 18:00', countdown='in 3d 3h', status='On pace', proj='100% by reset at this rate', allow='0.6% an hour left') + BL + win('5h window', **FIVE_AHEAD)))
         + tip('On pace or Ahead the projection is the share at the reset, at most 100: 57% at 55% of the week reads "100% by reset at this rate", not a clock time (PaceModel.reading). A "limit ... at this rate" clock time is for Over pace alone.', 500, 250, 330, n=True)), POP_KEYS)
reg('pop-pace-over-early', 'Claude tab, ten minutes into a 5h window: Over pace keeps its limit time even this early', 'Pace',
    desk(item('62%', on=True, href='desk'), 'Sat 31 Oct 14:20', over=pop(claude(win('Weekly (all models)', used=62, elapsed=83.5, reset='Resets Sun 18:00', countdown='in 1d 3h', status='Ahead', proj='74% by reset at this rate', allow='1% an hour left') + BL
                                                                   + win('5h window', used=10, elapsed=3.3, over=True, reset='Resets 19:10', countdown='in 4h 50m', status='Over pace', proj='limit 15:50 at this rate', allow='19% an hour left')))
         + tip('Over pace keeps the limit time in every phase: 10% ten minutes into a 5h window reads "Over pace  limit 15:50 at this rate". The weekly row below is Ahead and reads the share at the reset.', 500, 250, 330, n=True)), POP_KEYS)
reg('desk-weekly-limit', 'Menu bar, weekly limit reached: x x eyes until the reset', 'Menu bar', desk(item('100%', eyes='weekly', over=True, href='pop-live')))

# stale and missing
reg('pop-asof', 'Claude tab, last session closed 20 minutes ago: As of 14:00, pace still computed', 'Stale feed',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, sess=[], hdr=ASOF('14:00')))), POP_KEYS)
STALE = win('Weekly (all models)', 'stale', used=61, elapsed=55, reset='Resets Sun 18:00', asof='13:05') + BL + win('5h window', 'stale', used=24, elapsed=32, reset='Resets 17:45', asof='13:05') + STALE_NOTE
W_STALE = W_SAMPLE[:3] + [('12 Oct', 61, False, 'so far', 55, False)]
reg('pop-stale', 'Claude tab, stale: no session for over an hour', 'Stale feed',
    desk(item('61%', dim=True, on=True, href='desk-stale'), over=pop(claude(STALE, sess=[], hdr=ASOF('13:05'), wk=W_STALE))), POP_KEYS)
reg('desk-stale', 'Menu bar, stale: the item at half strength', 'Menu bar', desk(item('61%', dim=True, href='pop-stale')))
reg('pop-nolimits', 'Claude tab, sessions on an API key, Bedrock or Vertex: no plan limits', 'Stale feed',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude(two_lines('Weekly and 5h window', 'these sessions carry no plan limits'), wk=W_SAMPLE[:3] + [('12 Oct', None, False, 'no feed yet', None, False)]))), POP_KEYS)
reg('pop-notranscripts', 'Claude tab, no transcripts folder', 'Stale feed',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS, tok_empty='No transcripts in ~/.claude/projects'))), POP_KEYS)

# Mac tab


def mac_tab(warn=False, health=True, hdr=LIVE, prefix='pop'):
    """Grammar.macTab: CPU, GPU, the memory grid of glyphs (used accent, free dimmer, swap warning), battery, processes."""
    used, swap = 142, 5   # round(25.5 / 36 * 200), round(0.9 / 36 * 200)
    body = header(hdr, 1, warn, prefix) + BL
    body += L(T(' '), T('CPU', 'bold')) + L(T(' '), bar(36, 9), T(' 9%')) + L(T(' '), T('user 5%  system 4%  10 cores', 'dim')) + BL
    body += L(T(' '), T('GPU', 'bold')) + L(T(' '), bar(36, 11), T(' 11%')) + L(T(' '), T('device utilisation', 'dim')) + BL
    body += L(T(' '), T('Memory', 'bold'))
    for r in range(10):
        cells = []
        for c in range(20):
            i = r * 20 + c
            cells.append(G('&#9921;', 2, 'acc') if i < used else G('&#9949;', 2, 'warnc') if i >= 200 - swap else G('&#9974;', 2, 'dimmer'))
        body += L(T(' '), *cells)
    body += L(T(' '), G('&#9921;', 2, 'acc'), T('Used '), T('25.5 of 36 GB (71%)', 'dim'))
    body += L(T(' '), G('&#9974;', 2, 'dimmer'), T('Free '), T('10.5 GB', 'dim'))
    body += L(T(' '), G('&#9949;', 2, 'warnc'), T('Swap '), T('0.9 GB', 'dim'), T('   '), T('Pressure ' + ('warn' if warn else 'normal'), 'dim')) + BL
    body += L(T(' '), T('Battery', 'bold')) + L(T(' '), bar(36, 75), T(' 75%')) + L(T(' '), T('charging  47.6 W in  94 W adapter', 'dim'))
    body += L(T(' '), T('full in 51 min  ' + ('health normal  ' if health else '') + '316 cycles', 'dim')) + BL
    body += L(T(' '), T('Processes by CPU', 'bold'))
    for n, share, fig in [(6, 68, '6.1%'), (5, 26, '2.3%'), (12, 16, '1.4%'), (8, 9, '0.8%'), (5, 7, '0.6%')]:
        body += L(T(' '), fb(n, 'k'), T(' ' * (15 - n)), bar(24, share, color=TOK['procWhite'], plain=True), T('  ' + fig.rjust(5)))
    return body + foot(1)


MK = keys(Escape='desk', Tab='pop-settings', Shift_Tab='pop-live', Meta_q='desk-quit')
reg('pop-mac', 'Mac tab: CPU, GPU, memory, battery, processes', 'Mac tab', desk(item('61%', over=True, on=True, href='desk'), over=pop(mac_tab())
    + tip('The free cells of the memory grid are #949494 (Tokens.dimmer, 0.1.14), 3 to 1 even over a white desktop; #6e6e73 in light mode.', 500, 300, 300, n=True)), MK)
reg('pop-mac-ultra', 'Mac tab (Ultra, today)', 'Mac tab', desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(mac_tab(prefix='ultra'))), keys(Escape='desk-ultra', Tab='pop-settings-ultra', Shift_Tab='pop-ultra-today'))
reg('pop-mac-warning', 'Mac tab with the warning: dot on the tab, pressure warn', 'Mac tab', desk(item('61%', over=True, warn=True, on=True, href='desk-warning'), over=pop(mac_tab(warn=True, prefix='warn'))), keys(Escape='desk-warning', Tab='pop-settings', Shift_Tab='pop-live-warn'))
reg('pop-live-warn', 'Claude tab with the Mac warning dot', 'Mac tab', desk(item('61%', over=True, warn=True, on=True, href='desk-warning'), over=pop(claude(LIVE_LIMITS, tab_prefix='warn', warn=True))), keys(Escape='desk-warning', Tab='pop-mac-warning'))
reg('pop-mac-health', 'Mac tab, no battery health from macOS: left out', 'Mac tab', desk(item('61%', over=True, on=True, href='desk'), over=pop(mac_tab(health=False))), MK)
reg('desk-warning', 'Menu bar with the Mac warning sign', 'Menu bar', desk(item('61%', over=True, warn=True, href='pop-live-warn')))
reg('desk-mac', 'Menu bar with Mac figures in the bar: CPU 9%', 'Menu bar', desk(item('61%', over=True, mac=' CPU 9%', href='pop-settings')))
reg('desk-quit', 'Menu bar after Quit: the item is gone', 'Menu bar', desk('<span class="ext"></span>'))

# Settings tab


def cb(on, label, href, subs=(), indent=1, focus=False, link=None):
    """Grammar.cbRow: the box and the label one control; dim lines under it wrapped at indent + 4; the notifications
    note a link of its own in the accent."""
    out = L(T(' ' * indent), A(href, ('[x]' if on else '[ ]') + ' ' + esc(label), 'cb' + (' focus' if focus else '')))
    for sub in subs:
        if sub == NOTIF_OFF:
            out += L(T(' ' * (indent + 4)), A(link or 'sys-notifications', esc(sub), 'acc'))
        else:
            out += dim_lines(sub, indent + 4)
    return out


def settings_tab(login='off', nudge_note=None, awake=False, awake_open=False, awake_note=None, restore=False, hook=True,
                 hook_err=None, prefix='pop', hdr=LIVE, macbar=False, listprice=True, focus=None, five=True, folders=False):
    """Grammar.settingsTab, row for row, with the version line of 0.1.15."""
    body = header(hdr, 2, False, prefix) + BL
    body += cb(login == 'on', 'Open at login', 'pop-settings-login' if login == 'off' else 'pop-settings')
    if login == 'approval':
        body += L(T('     '), A('sys-loginitems', 'click to allow it in Login Items', 'dim'))
    body += cb(macbar, 'Mac figures in the bar', 'desk-mac')
    body += cb(True, 'Nudge at 80% and before the 5h end' if five else 'Nudge at 80%', 'pop-settings', [nudge_note] if nudge_note else [], focus=focus == 'nudge')
    body += cb(listprice, 'List price equivalent', 'pop-nochip', ['tokens at list prices, not the plan price'])
    body += cb(awake, 'Keep the Mac awake while Claude works', 'pop-settings-awake' if not awake else 'pop-settings', ['a closed lid on battery still sleeps'])
    if awake:
        body += cb(awake_open, 'also while a session waits for you', 'pop-settings-awake-open' if not awake_open else 'pop-settings-awake', [awake_note] if awake_note else [], indent=5)
    body += cb(restore, 'Reopen sessions after a restart', 'pop-settings-restore' if not restore else 'pop-settings',
               ['asks first, then opens each as it was started, and says when one ends on its own'] + ([nudge_note] if restore and nudge_note else []))
    body += BL
    if folders:
        body += L(T(' '), A('editor-after', 'Install the status line entry')) + dim_lines('one entry in each of ~/.claude, ~/.claude-work', 5)
        body += dim_lines('the hook script is gone, Install puts it back', 5)
        body += L(T(' '), A('editor-restored', 'Remove the status line entry')) + L(T('     '), T('puts back what statusLine held before', 'dim'))
        body += dim_lines('Could not install the entry: ~/.claude-work: cannot write settings.json: You don’t have permission', 5)
        body += dim_lines('Could not write remove.sh, so brew uninstall --zap cannot put your status line back: You don’t have permission', 5)
    elif hook:
        body += L(T(' '), A('editor-restored', 'Remove the status line entry')) + L(T('     '), T('puts back what statusLine held before', 'dim'))
    else:
        body += L(T(' '), A('editor-after', 'Install the status line entry')) + dim_lines('one entry in ~/.claude/settings.json', 5)
    if hook_err:
        body += dim_lines(hook_err, 5)
    body += BL + L(T(' '), A('', 'Copy a problem report')) + dim_lines('versions, switches and errors to paste into an issue or a mail, sends nothing', 5)
    body += BL + PRIVACY + L(T(' '), T('tokenpanda 0.1.15', 'dim')) + BL
    body += L(T(' '), A('desk-quit', 'Quit'), T(' ' * 40), A('desk-quit', G('&#8984;Q', 2)))
    return body + foot(2)


SK = keys(Escape='desk', Tab='pop-live', Shift_Tab='pop-mac', Meta_q='desk-quit')
IT = lambda: item('61%', over=True, on=True, href='desk')
reg('pop-settings', 'Settings tab', 'Settings', desk(IT(), over=pop(settings_tab())), SK)
reg('pop-settings-ultra', 'Settings tab on a plan without a 5h window: Nudge at 80%', 'Settings',
    desk(item('28%', on=True, href='desk-ultra'), TODAY, over=pop(settings_tab(five=False, prefix='ultra'))), keys(Escape='desk-ultra', Tab='pop-ultra-today', Shift_Tab='pop-mac-ultra'))
reg('pop-settings-login', 'Settings, Open at login on: macOS lists it in Login Items', 'Settings',
    desk(IT(), over=pop(settings_tab(login='on')) + '<div class="alts"><a class="altg" href="pop-settings-approval.html">macOS waits for your OK</a><a class="altg" href="sys-loginitems.html">System Settings, Login Items</a></div>'), SK)
reg('pop-settings-approval', 'Settings, Open at login waits for approval: click to allow it in Login Items', 'Settings', desk(IT(), over=pop(settings_tab(login='approval'))), SK)
reg('pop-settings-awake', 'Settings, Keep the Mac awake on, one session working', 'Settings', desk(IT(), over=pop(settings_tab(awake=True, awake_note='awake  1 session working')) + '<div class="alts"><a class="altg" href="term-pmset.html">pmset -g assertions</a></div>'), SK)
reg('pop-settings-awake-open', 'Settings, also while a session waits: awake  1 session open', 'Settings', desk(IT(), over=pop(settings_tab(awake=True, awake_open=True, awake_note='awake  1 session open', restore=True))), SK)
reg('pop-settings-restore', 'Settings, Reopen sessions after a restart on', 'Settings', desk(IT(), over=pop(settings_tab(restore=True)) + '<div class="alts"><a class="altg" href="notif-reopen.html">After a restart</a></div>'), SK)
reg('pop-settings-nohook', 'Settings, entry not installed: Install the status line entry', 'Settings',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(settings_tab(hook=False, hdr=WAITING, prefix='nohook'))), keys(Escape='desk-nofeed', Tab='pop-nohook'))
reg('pop-settings-folders', 'Settings, two settings folders: Install for the one missing, Remove, the errors whole', 'Settings',
    desk(IT(), over=pop(settings_tab(nudge_note=NOTIF_OFF, restore=True, folders=True))
         + tip('With ~/.claude and ~/.claude-work, the entry in one and its script gone in the other, both rows show: Install adds what is missing, Remove takes out what is there (Grammar.hookRow). Every error wraps whole.', 500, 330, 330, n=True)), SK)
reg('pop-settings-denied', 'Settings, notifications denied: the note in the accent, a link, under Reopen too', 'Settings',
    desk(IT(), over=pop(settings_tab(nudge_note=NOTIF_OFF, restore=True)) + pmark(7, 1, 4, 40) + pmark(15, 1, 4, 40)
         + tip('"Notifications are off in System Settings" is a link: in the accent, a control the keyboard and VoiceOver reach, said once. A click opens System Settings, Notifications, at tokenpanda. Turned on there, the note goes the next time the panel opens, with no restart (Notifier.refreshState, 0.1.14).', 500, 170, 330, n=True)), SK)
reg('pop-settings-dangling', 'Settings, the install error for a link into a folder that does not exist, under the row, whole', 'Settings',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(settings_tab(hook=False, hook_err=DANGLING_ERR, hdr=WAITING, prefix='nohook'))), keys(Escape='desk-nofeed', Tab='pop-nohook'))
reg('pop-settings-error', 'Settings, the install error under the row, whole', 'Settings',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(settings_tab(hook=False, hook_err=INSTALL_ERR, hdr=WAITING, prefix='nohook'))), keys(Escape='desk-nofeed', Tab='pop-nohook'))

# accessibility
reg('pop-voiceover', 'VoiceOver in the popover: buttons, tabs and checkboxes with their state, pressable', 'Access',
    desk(item('', dim=True, on=True, href='desk-nofeed'), over=pop(claude_nohook(focus=True))
         + tip('VoiceOver reads "Install the status line entry, button" and VO Space presses it. The tabs are a tab group; every setting is a checkbox with its state, its dim lines its help; the notifications note is a button of its own; a figure\'s tooltip is its help; the privacy sentence is one element (LineView, AccessTests). The manual test is docs/testing.html.', 500, 170, 330, n=True)), NK)
reg('pop-keyboard', 'Keyboard in the popover: the focus ring on a setting, Space ticks it', 'Access',
    desk(IT(), over=pop(settings_tab(focus='nudge'))
         + tip('Down and Up move a 1 pt accent ring through the tab\'s controls and key figures, Left and Right along the tab strip and the section switch, Space or Return presses. Tab still switches tabs and puts the ring on the tab it opened. The key hints are #b8b8b8, 4.5 to 1 or more over a white desktop.', 500, 150, 330, n=True)), SK)

# a small screen: the panel capped at the visible height less 60, scrolling inside the glass
SCREEN_H = 497   # a small or scaled display; the panel then holds 25 lines
SMALL_H = SCREEN_H - 25 - 60
OFFSCREEN = f'<div class="offscreen" style="top:{SCREEN_H}px"><span>the screen ends here: a small or scaled display</span></div>'
reg('pop-small', 'Claude tab on a small or scaled screen: the panel stops short of the screen and scrolls, from the top', 'Small screen',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(claude(LIVE_LIMITS), height=SMALL_H)
         + OFFSCREEN
         + tip('The panel is never taller than the screen\'s visible height less 60 points (PanelSize, Controller.fitPanel). It scrolls with an overlay scroller and no rubber band, from the top on every open and tab click.', 500, 120, 320, n=True)
         + '<div class="alts"><a class="altg" href="pop-small-settings.html">Settings, the ring on Quit</a></div>', cls='small'), POP_KEYS)
SMALL_SET = settings_tab(awake=True, awake_open=True, awake_note='awake  1 session open', restore=True, nudge_note=NOTIF_OFF).replace(
    '<a href="desk-quit.html">Quit</a>', '<a class="focus" href="desk-quit.html">Quit</a>')
reg('pop-small-settings', 'Settings on a small screen: the keyboard ring scrolls Quit into view', 'Small screen',
    desk(item('61%', over=True, on=True, href='desk'), over=pop(SMALL_SET, height=SMALL_H, scroll=22 + 16 * nlines(SMALL_SET) - SMALL_H)
         + OFFSCREEN
         + tip('Down to the end: the focused control is scrolled into view with a line of room around it (LineView.focus, scrollToVisible). VoiceOver reads every line; before macOS 26 its outline does not show on a line outside the visible part.', 500, 200, 320, n=True), cls='small'), SK)

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


def dlg(title, text, btns, left=490, top=200, stack=False):
    bt = ''.join(A(h, l, 'btn' + (' pri' if p else '')) for l, h, p in btns)
    return (f'<div class="dlg{" stack" if stack else ""}" style="left:{left}px;top:{top}px"><i class="appic" style="width:44px;height:44px;border-radius:10px"></i>'
            f'<h3>{title}</h3><p>{text}</p><div class="btns">{bt}</div></div>')


def notif(title, body, acts=()):
    a = ''.join(A(h, l, 'btn') for l, h in acts)
    return f'<div class="notif"><i class="appic"></i><div><div class="t">{title}</div><div>{body}</div></div>{"<div class=acts>" + a + "</div>" if a else ""}</div>'


def plain(over, clock='Thu 15 Oct 14:20', it=None, app='Finder'):
    return desk(it or '<span class="ext"></span>', clock, over, app)


reg('browser-release', 'Releases page: tokenpanda-0.1.15.zip and its .sha256', 'Install',
    plain('<div class="win" style="left:150px;top:60px;width:980px;height:640px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>Releases</div>'
          '<div class="urlbar">github.com/tokenpandadev/tokenpanda-app/releases</div><div class="page"><h2>0.1.15</h2>' + b(520) + b(460) + b(380)
          + '<div class="grp" style="margin-top:10px">' + A('term-shasum', '<span>tokenpanda-0.1.15.zip</span><span class="sp"></span><span class="note">629 KB</span>', 'asset')
          + A('term-shasum', '<span>tokenpanda-0.1.15.zip.sha256</span><span class="sp"></span><span class="note">88 Bytes</span>', 'asset')
          + '<div class="asset"><span>Source code (zip)</span></div></div></div></div>', app='Safari'))
reg('term-shasum', 'Terminal: shasum checks the zip, OK', 'Install',
    plain(term('Terminal, ~/Downloads', [('p', '$ shasum -a 256 -c tokenpanda-0.1.15.zip.sha256'), ('ok', 'tokenpanda-0.1.15.zip: OK'), ('p', '$ unzip -q tokenpanda-0.1.15.zip &amp;&amp; mv tokenpanda.app /Applications/')])
          + '<div class="alts"><a class="altg" href="finder-apps.html">Open Applications</a><a class="altg" href="term-brew.html">With Homebrew instead</a></div>', app='Terminal'))
reg('term-brew', 'Terminal: brew trust, brew install from the tap, the caveats', 'Install',
    plain(term('Terminal', [('p', '$ brew trust --cask tokenpandadev/tap/tokenpanda'), ('p', '$ brew install tokenpandadev/tap/tokenpanda'), ('d', '==&gt; Tapping tokenpandadev/tap'), ('d', '==&gt; Installing Cask tokenpanda'),
                            ('', '==&gt; Caveats'), ('', 'The app is signed ad hoc, not notarised. On first launch macOS blocks it:'), ('', 'open System Settings, Privacy &amp; Security, and click Open Anyway.'), ('', ' '),
                            ('', 'brew uninstall --zap removes the status line entry and puts back the one'), ('', 'you had before, once tokenpanda 0.1.9 or later has run at least once.'),
                            ('', 'With a plain brew uninstall, first open tokenpanda\'s Settings tab and'), ('', 'click "Remove the status line entry".'),
                            ('ok', 'tokenpanda was successfully installed!'), ('d', '(on an Intel Mac the cask refuses: depends_on arch: :arm64)')])
          + '<div class="alts"><a class="altg" href="gk-blocked.html">Open the app</a></div>', app='Terminal'))
reg('finder-apps', 'Finder, Applications: tokenpanda.app', 'Install',
    plain('<div class="win" style="left:200px;top:90px;width:880px;height:520px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>Applications</div><div class="fgrid">'
          + ''.join('<div class="fi"><i></i>' + b(56, 6) + '</div>' for _ in range(5)) + A('gk-blocked', '<i></i>tokenpanda', 'fi on')
          + ''.join('<div class="fi"><i></i>' + b(50, 6) + '</div>' for _ in range(6)) + '</div></div>'))
reg('gk-blocked', 'macOS blocks the first open: Apple could not verify tokenpanda', 'Install',
    plain('<div class="win" style="left:200px;top:90px;width:880px;height:520px;opacity:.5"><div class="wtb">Applications</div></div>'
          + dlg('"tokenpanda" Not Opened', 'Apple could not verify "tokenpanda" is free of malware that may harm your Mac or compromise your privacy.', [('Done', 'gk-settings', True), ('Move to Bin', 'finder-apps', False)])
          + tip('<b>Friction, by design.</b> Signed ad hoc, not notarised: spctl rejects the build. Since Sequoia, Control click no longer opens it.', 820, 220, 280)))
reg('gk-settings', 'System Settings, Privacy &amp; Security: Open Anyway, at the bottom', 'Install',
    plain(swin('Privacy &amp; Security', 'Privacy &amp; Security', '<h2>Privacy &amp; Security</h2><div class="grp">' + ''.join(f'<div class="grow"><i class="appic"></i>{b(160)}<span class="sp"></span>{b(40, 7)}</div>' for _ in range(5)) + '</div>'
                                                                  + '<div class="grp"><div class="grow"><span>Security</span></div><div class="grow"><span>"tokenpanda" was blocked to protect your Mac.</span><span class="sp"></span>' + A('gk-confirm', 'Open Anyway', 'btn pri') + '</div></div>')
          + tip('<b>Friction.</b> The button sits below the fold of Privacy &amp; Security, after a scroll, and appears only after a blocked try.', 900, 560, 300), app='System Settings'))
reg('gk-confirm', 'The warning again: Open Anyway', 'Install',
    plain(dlg('Open "tokenpanda"?', 'Apple is not able to verify that it is free from malware. Open it only if you are certain it is from a reliable source.', [('Move to Bin', 'finder-apps', False), ('Open Anyway', 'desk-nofeed', True)])))
reg('notif-permission', 'The notification permission prompt: when Nudge or Reopen is ticked on, or the first nudge is due', 'Nudges',
    desk(item('61%', over=True, href='pop-settings-restore'), 'Thu 15 Oct 14:20', over=notif('"tokenpanda" would like to send you notifications', 'Notifications may include alerts, sounds and icon badges.', [('Allow', 'pop-settings-restore'), ("Don't Allow", 'pop-settings-denied')])
         + tip('Never at launch: the prompt comes with the first nudge that is due, or when the user ticks Nudge or Reopen sessions on; a choice made before is read without asking (Notifier.authorize).', 760, 140, 330, n=True)))
HID_MGR = 'an app that hides menu bar icons, such as Bartender or Ice'
# the texts are Grammar.hiddenIconHint, word for word, for each notch case (notch true, false, nil = not known)
H26_FULL = {'notch': 'hidden behind the notch when the menu bar is full', 'nonotch': 'left out when the menu bar is full', 'unknown': 'left out or hidden behind the notch when the menu bar is full'}
H15_CAUSE = {'notch': 'the menu bar is full and the icon is hidden behind the notch', 'nonotch': 'the menu bar is full', 'unknown': 'the menu bar is full and the icon is left out or hidden behind the notch'}
H_CASE = {'notch': 'a Mac with a notch', 'nonotch': 'a Mac with no notch', 'unknown': 'notch not known (a connected screen has one, the item\'s screen is not known)'}
H_SUF = {'notch': '', 'nonotch': '-nonotch', 'unknown': '-unknown'}
H_SHORT = {'notch': 'with a notch', 'nonotch': 'no notch', 'unknown': 'notch not known'}


def h26(k):
    return f'Its icon is not visible in the menu bar. It may be switched off in System Settings, Menu Bar, {H26_FULL[k]}, or kept out of view by {HID_MGR}.'


def h15(k):
    return f'Its icon is not visible in the menu bar, most likely because {H15_CAUSE[k]}. Quitting another menu bar app makes room for it. An app that hides menu bar icons, such as Bartender or Ice, can also keep it out of view.'


reg('desk-hidden', 'First launch, the icon not visible: switched off in Menu Bar settings, behind the notch, or kept out of view by a menu bar manager', 'Install',
    desk('<span class="ext"></span>', 'Thu 15 Oct 14:20', over=tip('The app runs, but its icon is not on screen. Five seconds after the first launch the app checks (Controller.checkItemShows) and shows one window, once. While the screen is locked, another user is on the Mac or the display sleeps, it waits and asks again. The text is picked by the macOS version and by the notch: named only on a Mac with one, both causes when it is not known.', 700, 30, 400, n=True)
                                                         + '<div class="alts"><a class="altg" href="dlg-hidden-26.html">macOS 26, with a notch</a><a class="altg" href="dlg-hidden-26-nonotch.html">macOS 26, no notch</a><a class="altg" href="dlg-hidden-26-unknown.html">macOS 26, notch not known</a>'
                                                         '<a class="altg" href="dlg-hidden-15.html">macOS 14 and 15, with a notch</a><a class="altg" href="dlg-hidden-15-nonotch.html">macOS 14 and 15, no notch</a><a class="altg" href="dlg-hidden-15-unknown.html">macOS 14 and 15, notch not known</a></div>'))
for k in ('notch', 'nonotch', 'unknown'):
    n = {'notch': 'true', 'nonotch': 'false', 'unknown': 'nil'}[k]
    reg('dlg-hidden-26' + H_SUF[k], f'macOS 26 and later, {H_SHORT[k]}: tokenpanda is running, with Open Menu Bar Settings', 'Install',
        plain(dlg('tokenpanda is running', h26(k), [('Open Menu Bar Settings', 'sys-menubar', True), ('OK', 'desk-hidden', False)], stack=True)
              + tip(f'Grammar.hiddenIconHint(switchInSettings: true, notch: {n}), {H_CASE[k]}. From macOS 26 an app\'s icon can be switched off in System Settings, Menu Bar, so the window names the causes and offers the pane; it also names a menu bar manager.', 840, 120, 300, n=True)))
for k in ('notch', 'nonotch', 'unknown'):
    n = {'notch': 'true', 'nonotch': 'false', 'unknown': 'nil'}[k]
    reg('dlg-hidden-15' + H_SUF[k], f'macOS 14 and 15, {H_SHORT[k]}: tokenpanda is running, the full menu bar, OK only', 'Install',
        plain(dlg('tokenpanda is running', h15(k), [('OK', 'desk-hidden', True)], stack=True)
              + tip(f'Grammar.hiddenIconHint(switchInSettings: false, notch: {n}), {H_CASE[k]}. Before macOS 26 only Apple\'s own items have a switch, so the window names a full menu bar, has no button to a pane, and names a menu bar manager.', 840, 120, 300, n=True)))
reg('sys-menubar', 'System Settings, Menu Bar: allow tokenpanda (macOS 26)', 'Install',
    plain(swin('Menu Bar', 'Menu Bar', '<h2>Menu Bar</h2><div class="grp"><div class="grow"><span>Allow in the Menu Bar</span></div>' + ''.join(f'<div class="grow"><i class="appic"></i>{b(120)}<span class="sp"></span><i class="sw on"></i></div>' for _ in range(3))
                                                + '<div class="grow"><i class="appic"></i><span>tokenpanda</span><span class="sp"></span>' + A('desk-nofeed', '<i class="sw"></i>') + '</div></div>'), app='System Settings'))
reg('sys-loginitems', 'System Settings, General, Login Items: tokenpanda listed', 'Settings',
    plain(swin('Login Items', 'Login Items', '<h2>Login Items &amp; Extensions</h2><div class="grp"><div class="grow"><span>Open at Login</span></div><div class="grow"><i class="appic"></i><span>tokenpanda</span><span class="sp"></span><span class="note">Application</span></div>'
                                             + ''.join(f'<div class="grow"><i class="appic"></i>{b(110)}</div>' for _ in range(2)) + '</div>') + '<div class="alts"><a class="altg" href="pop-settings-login.html">Back to the popover</a></div>', app='System Settings'))
reg('sys-notifications', 'System Settings, Notifications, tokenpanda: the link from Settings lands here', 'Nudges',
    plain(swin('Notifications', 'Notifications', '<h2>tokenpanda</h2><div class="grp"><div class="grow"><span>Allow notifications</span><span class="sp"></span>' + A('pop-settings', '<i class="sw"></i>') + '</div>'
                                                 + ''.join(f'<div class="grow">{b(140)}<span class="sp"></span>{b(60, 7)}</div>' for _ in range(3)) + '</div>')
          + tip('Opened by "Notifications are off in System Settings" in the panel (x-apple.systempreferences, at dev.tokenpanda.app). Switched on, it counts at once: the note goes the next time the panel opens, and the next nudge is posted.', 760, 520, 330, n=True), app='System Settings'))


def editor(title, lines, note=''):
    return plain(term(title, lines, left=200, top=80, w=880, h=520) + note, app='TextEdit')


reg('editor-after', '~/.claude/settings.json after Install: one statusLine entry, the rest kept', 'Setup',
    editor('settings.json', [('', '{'), ('', '  "statusLine" : {'), ('', '    "type" : "command",'), ('', '    "command" : "\'/Users/someone/Library/Application Support/dev.tokenpanda.app/hook.sh\'",'), ('', '    "refreshInterval" : 5'), ('', '  },'),
                             ('d', '  "model" : ...,'), ('d', '  "theme" : ...'), ('', '}')],
           tip('Other keys kept, key order and indentation rewritten by the JSON writer. With a status line of your own, its padding and a refreshInterval of 5 or less stay and your command is chained. A settings.json that is a link stays a link; a created one is 0600.', 760, 520, 330, n=True)
           + '<div class="alts"><a class="altg" href="pop-nosession.html">Back to the popover</a></div>'))
reg('editor-broken', '~/.claude/settings.json that is not valid JSON (a trailing comma)', 'Setup',
    editor('settings.json', [('', '{'), ('', '  "model" : "opus",'), ('bad', '}')], '<div class="alts"><a class="altg" href="pop-install-failed.html">Click Install the status line entry</a></div>'))
reg('editor-restored', '~/.claude/settings.json after Remove: your statusLine back exactly', 'Uninstall',
    editor('settings.json', [('', '{'), ('', '  "statusLine" : {'), ('', '    "type" : "command",'), ('', '    "command" : "~/bin/my-statusline.sh",'), ('', '    "padding" : 2'), ('', '  },'), ('d', '  "model" : ...'), ('', '}')],
           '<div class="alts"><a class="altg" href="term-settings-gone.html">There was no settings.json before</a><a class="altg" href="finder-bin.html">Quit, move the app to the Bin</a></div>'))
reg('term-settings-gone', 'After Remove, when Install had created settings.json: the file is gone', 'Uninstall',
    plain(term('Terminal', [('p', '$ ls ~/.claude/settings.json'), ('', 'ls: /Users/someone/.claude/settings.json: No such file or directory')])
          + tip('Remove deletes a settings.json that Install created and nothing else changed; a file that was there before stays, even empty. When settings.json is a link into a dotfiles folder, the file goes and the link stays (Hook.uninstall, 0.1.14).', 760, 520, 330, n=True), app='Terminal'))
reg('term-claude', 'Terminal: a Claude Code session, the first reply', 'Setup',
    plain(term('Terminal, ~/workspace', [('p', '$ claude'), ('d', ' ...'), ('', '&gt; say ok'), ('', 'ok'), ('d', ' (your status line, unchanged, or nothing)')])
          + '<div class="alts"><a class="altg" href="pop-firstcall.html">Open the popover during the first call</a><a class="altg" href="pop-live.html">Open it after the reply</a></div>', app='Terminal'))
reg('notif-weekly', 'Nudge: Weekly at 80%', 'Nudges',
    desk(item('80%', over=True, href='pop-live'), 'Fri 16 Oct 15:40', over=notif('Weekly at 80%', '2 days 2 h to the reset. At this pace the limit lands Sat 21:30.')))
reg('notif-five', 'Nudge: 5h window ends in 15 min (Max or Pro)', 'Nudges',
    desk(item('61%', over=True, href='pop-live'), 'Thu 15 Oct 17:30', over=notif('5h window ends in 15 min', '34% used.')))
reg('notif-reopen', 'After a restart: the sessions that were open, by name, with Reopen', 'Reopen',
    desk(item('', dim=True, href='desk-nofeed'), 'Mon 19 Oct 08:02', over=notif('3 Claude Code sessions were open before the restart', 'Backend, Docs and Website. Reopen opens each in Terminal as they were started.', [('Reopen', 'term-reopen')])
         + tip('The names are the ones set with -n or /rename; a session without one shows its folder, counted when several share it; past five, "and N more" (SessionNames.list). Sample names.', 760, 230, 330, n=True)
         + '<div class="alts"><a class="altg" href="desk-reopen-denied.html">Notifications are off</a></div>'))
reg('notif-ended', 'A session ended while its Terminal window stays open: its name, the time, Reopen', 'Reopen',
    desk(item('61%', over=True, href='pop-live'), 'Thu 15 Oct 14:20', over=notif('Docs ended', 'At 14:20. Its Terminal window is still open. Reopen starts it again as it was started.', [('Reopen', 'term-reopen')])
         + tip('<b>Friction.</b> It also comes after a deliberate /exit in a window you keep: Controller.watchEnds cannot tell the two apart. A closed window or a shutdown gets none. Behind the same switch, Reopen sessions after a restart.', 760, 230, 330)))
reg('desk-reopen-denied', 'After a restart with notifications off: no offer; the Reopen row says so', 'Reopen',
    desk(item('', dim=True, href='pop-settings-denied'), 'Mon 19 Oct 08:02', over=tip('<b>Friction.</b> With notifications denied the offer is not posted (Notifier.post). Settings says so under Reopen sessions too, as the link to System Settings, Notifications; turned on there, the next notices come without a restart.', 760, 40, 330)))
reg('term-reopen', 'Terminal: each session started again as it was started, with Remote Control where it had it', 'Reopen',
    plain(term('Terminal, ~/workspace', [('d', '(a 0700 folder in the temporary folder, one script per session, each deletes itself)'), ('p', '$ claude --resume 3f1a9c2e-... --name Backend --remote-control'), ('d', ' ...'),
                                          ('p', '$ claude --resume 7b2d4e6f-... --permission-mode plan --name Docs'), ('d', ' ...')])
          + tip('The options the session was started with come back, then its name, then Remote Control. If that start fails within 20 s, the same without Remote Control follows, then a plain claude --resume; a start prompt is not sent again (Reopen.script). The window keeps a shell when the session ends.', 760, 520, 330, n=True), app='Terminal'))
reg('term-pmset', 'Terminal: pmset lists the tokenpanda assertion', 'Keep awake',
    plain(term('Terminal', [('p', '$ pmset -g assertions'), ('', '   pid 4242(tokenpanda): ... PreventUserIdleSystemSleep named: "tokenpanda: a Claude Code session is open"')]), app='Terminal'))
reg('term-brew-upgrade', 'Terminal: brew upgrade, then Open Anyway again', 'Update',
    plain(term('Terminal', [('p', '$ brew upgrade --cask tokenpanda'), ('d', '==&gt; Upgrading tokenpanda 0.1.14 -&gt; 0.1.15'), ('d', '==&gt; Quitting dev.tokenpanda.app'), ('ok', 'tokenpanda was successfully upgraded!')])
          + tip('<b>Friction.</b> Each new build is signed ad hoc with a new code hash, so the Open Anyway steps can come back after an update. Settings says which build runs: "tokenpanda 0.1.15".', 760, 520, 330)
          + '<div class="alts"><a class="altg" href="gk-blocked.html">Open the new build</a></div>', app='Terminal'))
reg('finder-bin', 'Finder: tokenpanda.app moved to the Bin', 'Uninstall',
    plain('<div class="win" style="left:200px;top:90px;width:880px;height:520px"><div class="wtb"><span class="tl"><i></i><i></i><i></i></span>Bin</div><div class="fgrid">'
          + '<div class="fi on"><i></i>tokenpanda</div></div></div>'
          + '<div class="alts"><a class="altg" href="term-leftover.html">Moved without Remove first</a><a class="altg" href="term-zap.html">brew uninstall --zap</a></div>'))
reg('term-leftover', 'Moved to the Bin without Remove: the script cleans up after itself, the folder stays small', 'Uninstall',
    plain(term('Terminal', [('p', '$ ls ~/Library/Application\\ Support/dev.tokenpanda.app/sessions'), ('', '3f1a...json  7b2d...json'), ('d', '(the sessions still open: the script deletes the files that stopped changing over a minute ago)')])
          + tip('The statusLine entry still runs the hook script, and since 0.1.13 the script deletes stale session files itself, the same rule the app uses. An entry installed by an earlier version got the new script at the last launch.', 760, 520, 330, n=True), app='Terminal'))
reg('term-zap', 'brew uninstall --zap: remove.sh takes the entry out first, your own status line comes back', 'Uninstall',
    plain(term('Terminal, ~/workspace', [('p', '$ brew uninstall --zap tokenpanda'), ('d', '(the zap runs remove.sh from the data folder)'), ('', 'tokenpanda: status line entry removed from /Users/someone/.claude/settings.json'),
                                         ('d', '==&gt; Trashing ~/Library/Application Support/dev.tokenpanda.app'), ('p', '$ claude'), ('', '&gt; ...'),
                                         ('ok', ' (your own status line, as before the install)')])
          + tip('The cask\'s zap runs remove.sh, which the app keeps in its data folder, before it trashes that folder, for every settings folder, through a link too (readlink -f). It needs no app binary. A plain uninstall does not run it, because it also runs on every upgrade.', 760, 500, 330, n=True), app='Terminal'))


# ---------- outcomes and the next place a flow goes: dashed targets, shown with h or in walk mode ----------
ALT = {
    'desk': [('Ultra, today', 'desk-ultra'), ('Mac under pressure', 'desk-warning'), ('Weekly at 100%', 'desk-weekly-limit'), ('5h window at 100%', 'desk-five-limit')],
    'desk-nofeed': [('Open the popover', 'pop-nohook'), ('The icon is not visible', 'desk-hidden')],
    'desk-ultra': [('30 Oct evening', 'pop-ultra-evening'), ('Max or Pro', 'pop-live-max'), ('Settings', 'pop-settings-ultra')],
    'pop-live': [('Hover a session figure', 'pop-session-tip'), ('An hour without a session', 'pop-stale'), ('Weekly passes 80%', 'notif-weekly'), ('15 min before the 5h reset', 'notif-five'), ('A small screen', 'pop-small')],
    'pop-ultra-evening': [('The next morning', 'pop-ultra-today')],
    'pop-stale': [('Last session 20 minutes ago', 'pop-asof'), ('No plan limits', 'pop-nolimits'), ('No transcripts folder', 'pop-notranscripts')],
    'pop-mac': [('No battery health from macOS', 'pop-mac-health')],
    'pop-settings': [('Notifications denied', 'pop-settings-denied'), ('Two settings folders', 'pop-settings-folders'), ('With VoiceOver', 'pop-voiceover'), ('With the keyboard', 'pop-keyboard'), ('A small screen', 'pop-small-settings')],
    'pop-settings-awake-open': [('pmset', 'term-pmset')],
    'desk-quit': [('Open the app again', 'desk')],
    'desk-weekly-limit': [('The reset nears', 'pop-week-near')],
}

# the next place each flow goes, where the screen itself has no control for it
NEXT = [
    ('term-brew', 'Or from the zip: Applications', 'finder-apps'),
    ('pop-nohook-chained', 'Click Install', 'editor-after'),
    ('pop-nohook', 'disableAllHooks on', 'pop-hooks-disabled'),
    ('pop-live', 'A settings.json that is not JSON', 'editor-broken'),
    ('pop-settings-denied', 'Click the link', 'sys-notifications'),
    ('sys-notifications', 'An hour without a session', 'pop-stale'),
    ('notif-weekly', '15 min before the 5h reset', 'notif-five'),
    ('notif-five', 'On an Ultra account', 'pop-ultra-today'),
    ('notif-five', 'Notifications denied', 'pop-settings-denied'),
    ('pop-ultra-today', 'A Max or Pro account', 'pop-live-max'),
    ('pop-week-rolled', 'Same reset, sessions open', 'pop-week-rolled-live'),
    ('pop-week-new', 'A week at 100%', 'desk-weekly-limit'),
    ('pop-asof', 'An hour later', 'pop-stale'),
    ('pop-nolimits', 'No transcripts folder', 'pop-notranscripts'),
    ('pop-notranscripts', 'statusLine removed by hand', 'pop-nohook'),
    ('pop-mac', 'Memory pressure', 'desk-warning'),
    ('pop-mac-warning', 'No battery health from macOS', 'pop-mac-health'),
    ('pop-mac-health', 'Mac figures in the bar on', 'desk-mac'),
    ('desk-quit', 'Open it again, Settings', 'pop-settings'),
    ('term-reopen', 'A session ends, its window stays', 'notif-ended'),
    ('notif-ended', 'Notifications are off', 'desk-reopen-denied'),
    ('desk-reopen-denied', 'Settings, untick Reopen', 'pop-settings'),
    ('browser-release', 'brew upgrade instead', 'term-brew-upgrade'),
    ('gk-blocked', 'After the update', 'pop-live'),
    ('term-settings-gone', 'Quit, move the app to the Bin', 'finder-bin'),
    ('term-leftover', 'brew uninstall --zap', 'term-zap'),
    ('term-zap', 'Delete the rest by hand', 'finder-bin'),
    ('desk-ultra', 'Open the popover', 'pop-ultra-today'),
    ('pop-live', 'With VoiceOver', 'pop-voiceover'),
    ('pop-voiceover', 'With the keyboard', 'pop-keyboard'),
    ('pop-keyboard', 'A small screen', 'pop-small-settings'),
    ('pop-small', 'With VoiceOver', 'pop-voiceover'),
    ('desk-hidden', 'Switched on, the item', 'desk-nofeed'),
    ('pop-settings-folders', 'Click Install', 'editor-after'),
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
