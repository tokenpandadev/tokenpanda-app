// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The line grammar of Sources/Text (Bar.swift, Grammar.swift) drawn as HTML. A line is a run of pieces; a piece has its
// text, a style of Tokens.swift Style, a cell count and, for a bar, its cells. Colours are token variables only.
// Every name and figure in SAMPLE is invented sample data, the same as Sources/UI/Fixtures.swift.

export const CELLS = { popover: 47, barWindow: 36, barRow: 24, barWeek: 20, name: 14, figure: 5, memCols: 20, memRows: 10 };
const v = (name) => `var(--tp-color-${name})`;
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const count = (s) => [...s].length;

// ---------------------------------------------------------------- pieces and lines
export const P = (text, style = 'text', o = {}) => ({ text, style, cells: o.cells ?? (o.wide ? count(text) * 2 : count(text)), ...o });
export const L = (pieces, o = {}) => ({ pieces, ...o });
const sp = (s, st) => P(s, st);
const blank = L([]);
export const col = (s, w) => (count(s) > w ? [...s].slice(0, w - 1).join('') + '…' : s + ' '.repeat(w - count(s)));
export const rcol = (s, w) => (count(s) >= w ? s : ' '.repeat(w - count(s)) + s);

// ---------------------------------------------------------------- the bar grammar (Bar.swift)
const EIGHTHS = [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
const FULL = '█', NOTCH_L = '▐', NOTCH_R = '▌';

export function fill(n, u) {
  const f = Math.min(Math.max(u, 0), 100) / 100 * n;
  const full = Math.floor(f);
  const e8 = Math.round((f - full) * 8);
  return { full: Math.min(full, n), eighths: full >= n ? 0 : e8 };
}
export const tick = (n, e) => Math.max(1, Math.min(n - 1, Math.round(e / 100 * n)));

/** Bar.render: cells of { glyph, color, solid }, the track ranges, the tick. color is a token name. */
export function bar(n, used, elapsed = null, o = {}) {
  const f = fill(n, used);
  const base = Array.from({ length: n }, (_, i) => (i < f.full ? FULL : i === f.full ? (f.eighths === 8 ? FULL : EIGHTHS[f.eighths]) : ' '));
  const t = elapsed === null ? null : tick(n, elapsed);
  const fillColor = o.hue ? `hue-${o.hue}` : o.stale ? 'track' : 'accent';
  const pastColor = o.over && !o.stale ? 'coral' : fillColor;
  const markColor = o.stale ? 'dim' : 'bold';
  const cells = base.map((g, i) => {
    if (t !== null && [t - 1, t].includes(i)) return { glyph: i === t - 1 ? NOTCH_L : NOTCH_R, color: markColor, solid: false, notch: true };
    const color = i >= (t ?? n) ? pastColor : fillColor;
    return { glyph: g, color, solid: g === FULL };
  });
  return { width: n, cells, plain: !!o.plain, stale: !!o.stale, tick: t };
}
export const barPiece = (b) => ({ text: b.cells.map((c) => c.glyph).join(''), style: 'text', cells: b.width, bar: b });

// ---------------------------------------------------------------- render
function barHTML(b) {
  const trk = b.stale ? 'trk-stale' : 'trk';
  return `<span class="tp-bar" aria-hidden="true">${b.cells.map((c) => {
    const cls = ['tp-cell'];
    if (!b.plain && !c.notch && !c.solid) cls.push(trk);
    const ground = c.solid ? `--ground:${v(c.color)};` : '';
    return `<span class="${cls.join(' ')}" style="${ground}color:${v(c.color)}"><i>${c.glyph === ' ' ? ' ' : c.glyph}</i></span>`;
  }).join('')}</span>`;
}

function pieceHTML(p) {
  if (p.bar) return barHTML(p.bar);
  const cls = ['tp-pc', `s-${p.style}`];
  const attrs = [`style="width:calc(var(--tp-cell) * ${p.cells})${p.fg ? `;color:${v(p.fg)}` : ''}"`];
  if (p.wide) cls.push('tp-wide');
  if (p.action) {
    cls.push('tp-ctl');
    if (p.role === 'tab') cls.push('tab');
    attrs.push('tabindex="0"', `role="${p.role ?? 'button'}"`);
    if (p.checked !== undefined) attrs.push(p.role === 'tab' ? `aria-selected="${p.checked}"` : `aria-checked="${p.checked}"`);
  }
  if (p.tip) { cls.push('has-tip'); if (!p.action) attrs.push('tabindex="0"'); }
  if (p.open) cls.push('is-open');
  if (p.focus) cls.push('is-focus');
  const text = p.wide ? [...p.text].map((g) => `<i>${esc(g)}</i>`).join('') : esc(p.text);
  const tip = p.tip ? `<span class="tp-tip${p.tipLeft ? ' left' : ''}">${esc(p.tip)}</span>` : '';
  return `<span class="${cls.join(' ')}" ${attrs.join(' ')}>${text}${tip}</span>`;
}

export const lineHTML = (l) => `<div class="tp-ln${l.hover ? ' hover' : ''}${l.isHover ? ' is-hover' : ''}">${l.pieces.map(pieceHTML).join('')}</div>`;

/** A panel of lines on the glass, 380 wide, as LineView draws it. */
export const panel = (lines, label = 'Usage') => `<div class="tp tp-panel" role="group" aria-label="${esc(label)}"><div class="tp-glass">${lines.map(lineHTML).join('')}</div></div>`;

// ---------------------------------------------------------------- the parts (Grammar.swift, by style guide section)
// 6.1 header line and tab strip
export function header(line, sel = 0, warn = false) {
  const tabs = [];
  ['Claude', 'Mac', 'Settings'].forEach((name, i) => {
    if (i > 0) tabs.push(sp('  '));
    const style = i === sel ? 'tab-selected' : 'text';
    const o = { action: `tab${i}`, role: 'tab', checked: i === sel };
    if (name === 'Mac' && warn) {
      tabs.push(P(' Mac ', style, o), P('●', style, { ...o, fg: 'warning' }), P(' ', style, o));
    } else tabs.push(P(` ${name} `, style, o));
  });
  return [L([sp(' '), sp(line, 'dim')]), L([sp('▔'.repeat(CELLS.popover + 1), 'accent')]), L([sp(' '), ...tabs])];
}

// 6.3 window section; w: { title, used, elapsed, over, stale, reset, countdown, status, projection, allowance, asOf }
export function windowSection(w) {
  const out = [L([sp(' '), sp(w.title, 'bold')])];
  const pct = sp(` ${Math.round(w.used)}% used`, w.stale ? 'dim' : 'text');
  out.push(L([sp(' '), barPiece(bar(CELLS.barWindow, w.used, w.elapsed, { over: w.over, stale: w.stale })), pct]));
  if (w.stale) {
    out.push(L([sp(' '), sp(w.reset, 'dim')]), L([sp(' '), sp('as of ' + w.asOf, 'dim')]));
    return out;
  }
  out.push(L([sp(' '), sp(w.reset + '  ' + w.countdown, 'dim')]));
  out.push(L([sp(' '), sp(w.status, 'bold'), ...(w.projection ? [sp('  ' + w.projection, 'dim')] : [])]));
  out.push(L([sp(' '), sp(w.allowance, 'dim')]));
  return out;
}

// 6.14 open sessions; s: { name, model, hue, used, figure, tip }
export function sessionRows(list) {
  const out = [L([sp(' '), sp('Open sessions', 'bold')])];
  if (!list.length) return [...out, L([sp(' '), sp('no open session', 'dim')])];
  for (const s of list) {
    out.push(L([sp(' '), sp(s.name), sp('  '), sp(s.model, 'dim')]));
    if (s.waiting) { out.push(L([sp(' '), sp('waiting for the first reply', 'dim')], { hover: true })); continue; }
    const fig = P(s.figure + '  ' + rcol(`${s.used}%`, 3), 'text', { tip: s.tip, tipLeft: true });
    out.push(L([sp(' '), barPiece(bar(CELLS.barRow, s.used, null, { hue: s.hue, plain: true })), sp('  '), fig], { hover: true }));
  }
  return out;
}

// 6.5 table row; r: { name, hue, share, figure, tip }
export function row(r, o = {}) {
  const lead = o.selected ? P('❯', 'accent') : sp(' ');
  const fig = P(rcol(r.figure, CELLS.figure), 'text', { tip: r.tip, open: o.tipOpen });
  return L([lead, sp(col(r.name, CELLS.name), o.selected ? 'bold' : 'text'), sp(' '), barPiece(bar(CELLS.barRow, r.share, null, { hue: r.hue, plain: true })), sp('  '), fig],
    { hover: true, isHover: o.hover });
}

// 6.6 section switch
export function subTabs(sel = 0) {
  const pieces = [sp(' ')];
  ['Models', 'Projects', 'Sessions'].forEach((name, i) => {
    if (i > 0) pieces.push(sp('  '));
    pieces.push(P(` ${name} `, i === sel ? 'sub-selected' : 'text', { action: `section${i}`, role: 'tab', checked: i === sel }));
  });
  return L(pieces);
}

// 6.7 chip
export const chip = (text) => L([sp(' '), sp(text, 'dim')]);

// the token section: title, switch, rows, chips
export function tokens(section = 0, o = {}) {
  const title = ['Tokens by model  7 days', 'Tokens by project  7 days', 'Tokens by session  today'][section];
  const rows = SAMPLE.rows[['models', 'projects', 'sessions'][section]];
  return [L([sp(' '), sp(title, 'bold')]), subTabs(section), ...rows.map((r, i) => row(r, i === o.hoverRow ? { hover: true, tipOpen: o.tipOpen } : {})),
    chip(SAMPLE.chips.price), chip(SAMPLE.chips.agents)];
}

// 6.8 weeks; w: { date, used, elapsed, over, hit, note }
export function week(w) {
  const pieces = [sp(' '), sp(col(w.date, 6)), sp('  '), barPiece(bar(CELLS.barWeek, w.used, w.elapsed ?? null, { over: w.over }))];
  pieces.push(w.hit ? P('⚠', 'warning', { cells: 1 }) : sp(' '), sp(' ' + rcol(`${w.used}%`, 4)));
  if (w.note) pieces.push(sp('  ' + w.note, 'dim'));
  return L(pieces);
}

// 6.9 memory grid; m: { usedCells, swapCells, usedLine, freeLine, swapLine, pressure }
export function memGrid(m) {
  const total = CELLS.memCols * CELLS.memRows, out = [];
  for (let r = 0; r < CELLS.memRows; r++) {
    const pieces = [sp(' ')];
    let run = '', style = 'accent';
    const flush = () => { if (run) { pieces.push(P(run, style, { wide: true })); run = ''; } };
    for (let c = 0; c < CELLS.memCols; c++) {
      const i = r * CELLS.memCols + c;
      const [g, st] = i < m.usedCells ? ['⛁', 'accent'] : i >= total - m.swapCells ? ['⛝', 'warning'] : ['⛶', 'dimmer'];
      if (st !== style) { flush(); style = st; }
      run += g;
    }
    flush();
    out.push(L(pieces));
  }
  out.push(L([sp(' '), P('⛁', 'accent', { wide: true }), sp('Used '), sp(m.usedLine, 'dim')]));
  out.push(L([sp(' '), P('⛶', 'dimmer', { wide: true }), sp('Free '), sp(m.freeLine, 'dim')]));
  out.push(L([sp(' '), P('⛝', 'warning', { wide: true }), sp('Swap '), sp(m.swapLine, 'dim'), sp('   '), sp('Pressure ' + m.pressure, 'dim')]));
  return out;
}

// a Mac figure: title, the 36 cell bar without a tick, the dim lines
export const macBar = (title, pct, lines) => [L([sp(' '), sp(title, 'bold')]), L([sp(' '), barPiece(bar(CELLS.barWindow, pct)), sp(` ${pct}%`)]),
  ...lines.map((t) => L([sp(' '), sp(t, 'dim')]))];

// 6.10 checkbox rows; a sub line in the accent is a link
export function cbRow(label, on, subs = [], o = {}) {
  const indent = o.indent ?? ' ';
  const ctl = { action: `toggle-${label}`, role: 'checkbox', checked: on, focus: o.focus };
  const out = [L([sp(indent), P(on ? '[x]' : '[ ]', 'text', ctl), P(' ' + label, 'text', { action: ctl.action, role: 'checkbox', checked: on })], { hover: true, isHover: o.hover })];
  const pad = ' '.repeat(count(indent) + 4);
  for (const s of subs) {
    if (typeof s === 'object') out.push(L([sp(pad), P(s.link, 'accent', { action: 'link', role: 'link' })], { hover: true }));
    else for (const t of wrap(s, CELLS.popover + 1 - count(pad))) out.push(L([sp(pad), sp(t, 'dim')]));
  }
  return out;
}
export const actionRow = (label, sub) => [L([sp(' '), P(label, 'text', { action: label })], { hover: true }), L([sp('     '), sp(sub, 'dim')])];

export function wrap(s, w) {
  if (count(s) <= w) return [s];
  const out = [];
  let line = '';
  for (const word of s.split(' ')) {
    if (!line) line = word;
    else if (count(line) + 1 + count(word) <= w) line += ' ' + word;
    else { out.push(line); line = word; }
  }
  if (line) out.push(line);
  return out;
}

export const foot = (tab) => [blank, L([sp(' '), sp(tab === 0 ? 'Esc closes  Tab switches  m p s sections' : 'Esc closes  Tab switches', 'quiet')])];

// ---------------------------------------------------------------- the sample (Fixtures.swift, Thursday 15 October 2026, 14:20)
export const SAMPLE = {
  header: 'Live from Claude Code',
  weekly: { title: 'Weekly (all models)', used: 61, elapsed: 54.96, over: true, reset: 'Resets Sun 18:00', countdown: 'in 3d 3h', status: 'Over pace', projection: 'limit Sun 01:20 at this rate', allowance: '0.5% an hour left' },
  weeklyAhead: { title: 'Weekly (all models)', used: 45, elapsed: 54.96, over: false, reset: 'Resets Sun 18:00', countdown: 'in 3d 3h', status: 'Ahead', projection: '82% by reset at this rate', allowance: '0.7% an hour left' },
  weeklyStale: { title: 'Weekly (all models)', used: 61, elapsed: 54.96, stale: true, reset: 'Resets Sun 18:00', asOf: '13:05' },
  five: { title: '5h window', used: 24, elapsed: 31.67, over: false, reset: 'Resets 17:45', countdown: 'in 3h 25m', status: 'Ahead', projection: '76% by reset at this rate', allowance: '22% an hour left' },
  sessions: [
    { name: 'workspace', model: 'Fable 5.1', hue: 'magenta', used: 41, figure: '405.6k of 1M', tip: 'USD 38.20 list price equivalent  112 added  9 removed  effort high' },
    { name: 'tooling', model: 'Opus 5.5', hue: 'yellow', used: 9, figure: '88.4k of 1M', tip: 'USD 6.10 list price equivalent  0 added  0 removed  effort high' },
  ],
  rows: {
    models: [
      { name: 'Fable 5.1', hue: 'magenta', share: 49, figure: '1.02B', tip: '1.02B tokens  49% of 7 days' },
      { name: 'Opus 5.5', hue: 'yellow', share: 34, figure: '0.71B', tip: '0.71B tokens  34% of 7 days' },
      { name: 'Sonnet 5.5', hue: 'cyan', share: 11, figure: '0.24B', tip: '0.24B tokens  11% of 7 days' },
      { name: 'Haiku 4.5', hue: 'green', share: 6, figure: '0.13B', tip: '0.13B tokens  6% of 7 days' },
    ],
    projects: [
      { name: 'workspace', hue: 'blue', share: 70, figure: '1.46B', tip: '1.46B tokens  70% of 7 days' },
      { name: 'website', hue: 'blue', share: 20, figure: '0.42B', tip: '0.42B tokens  20% of 7 days' },
      { name: 'tooling', hue: 'blue', share: 7, figure: '0.14B', tip: '0.14B tokens  7% of 7 days' },
      { name: 'other', hue: 'blue', share: 4, figure: '0.08B', tip: '0.08B tokens  4% of 7 days' },
    ],
    sessions: [
      { name: '3f1a9c2e', hue: 'blue2', share: 43, figure: '31.2M', tip: '31.2M tokens  43% of today' },
      { name: '7b2d4e6f', hue: 'blue2', share: 25, figure: '18.0M', tip: '18.0M tokens  25% of today' },
      { name: 'c91e0a44', hue: 'blue2', share: 17, figure: '12.6M', tip: '12.6M tokens  17% of today' },
      { name: 'other', hue: 'blue2', share: 15, figure: '10.6M', tip: '10.6M tokens  15% of today' },
    ],
    processes: [
      { name: 'Safari', hue: 'proc-white', share: 67.8, figure: '6.1%', tip: '6.1% CPU  6.2 GB memory' },
      { name: 'Xcode', hue: 'proc-white', share: 25.6, figure: '2.3%', tip: '2.3% CPU  1.4 GB memory' },
      { name: 'WindowServer', hue: 'proc-white', share: 15.6, figure: '1.4%', tip: '1.4% CPU  512 MB memory' },
      { name: 'Terminal', hue: 'proc-white', share: 8.9, figure: '0.8%', tip: '0.8% CPU  128 MB memory' },
      { name: 'Music', hue: 'proc-white', share: 6.7, figure: '0.6%', tip: '0.6% CPU  2.1 GB memory' },
    ],
  },
  chips: { price: '[list price equivalent  USD 1,140]', agents: '[44% by subagents]' },
  weeks: [
    { date: '21 Sep', used: 88 },
    { date: '28 Sep', used: 100, hit: true, note: 'Thu 16:10' },
    { date: '5 Oct', used: 96 },
    { date: '12 Oct', used: 61, elapsed: 54.96, over: true, note: 'so far' },
  ],
  memory: { usedCells: 142, swapCells: 5, usedLine: '25.5 of 36 GB (71%)', freeLine: '10.5 GB', swapLine: '0.9 GB', pressure: 'normal' },
  mac: { cpu: 9, cpuLine: 'user 5%  system 4%  10 cores', gpu: 11, battery: 75, battery1: 'charging  47.6 W in  94 W adapter', battery2: 'full in 51 min  health 89%  316 cycles' },
  version: 'tokenpanda 0.1.14',
};

// ---------------------------------------------------------------- the three tabs, assembled (6.15)
export function claudeTab() {
  const s = SAMPLE;
  return [...windowSection(s.weekly), blank, ...windowSection(s.five), blank, ...sessionRows(s.sessions), blank, ...tokens(0), blank,
    L([sp(' '), sp('Week over week', 'bold')]), ...s.weeks.map(week)];
}
export function macTab() {
  const s = SAMPLE, m = s.mac;
  return [...macBar('CPU', m.cpu, [m.cpuLine]), blank, ...macBar('GPU', m.gpu, ['device utilisation']), blank, L([sp(' '), sp('Memory', 'bold')]),
    ...memGrid(s.memory), blank, ...macBar('Battery', m.battery, [m.battery1, m.battery2]), blank, L([sp(' '), sp('Processes by CPU', 'bold')]),
    ...s.rows.processes.map((r) => row(r))];
}
export function settingsTab(o = {}) {
  return [
    ...cbRow('Open at login', true),
    ...cbRow('Mac figures in the bar', false, [], { focus: o.focus }),
    ...cbRow('Nudge at 80% and before the 5h end', true, [], { hover: o.hover }),
    ...cbRow('List price equivalent', true, ['tokens at list prices, not the plan price']),
    ...cbRow('Keep the Mac awake while Claude works', true, ['a closed lid on battery still sleeps']),
    ...cbRow('also while a session waits for you', false, ['awake  2 sessions working'], { indent: '     ' }),
    ...cbRow('Reopen sessions after a restart', true, ['asks first, then opens each as it was started, and says when one ends on its own']),
    blank,
    ...actionRow('Remove the status line entry', 'puts back what statusLine held before'),
    blank,
    L([sp(' '), sp('This app makes no network calls. Usage comes', 'dim')]),
    L([sp(' '), sp("from Claude Code's own status feed on this Mac.", 'dim')]),
    L([sp(' '), sp(SAMPLE.version, 'dim')]),
    blank,
    L([sp(' '), P('Quit', 'text', { action: 'quit' }), P(rcol('⌘Q', CELLS.popover - 5), 'text', { action: 'quit' })], { hover: true }),
  ];
}
export function popover(tab = 0, o = {}) {
  const body = tab === 0 ? claudeTab() : tab === 1 ? macTab() : settingsTab(o);
  return [...header(SAMPLE.header, tab, o.warn), blank, ...body, ...foot(tab)];
}

// ---------------------------------------------------------------- the menu bar item (ItemImage.swift)
const PANDA = ['XX...XX', 'XXXXXXX', 'XXXXXXX', 'X..X..X', 'X.XXX.X', 'XXX.XXX', '.XXXXX.'];

/** ItemImage.mask: the 7 by 7 panda doubled to 14 by 14, the eye areas redrawn at a limit: x x weekly, - - 5h. */
export function mask(eyes = 'normal') {
  const grid = PANDA.flatMap((row) => { const d = [...row].flatMap((c) => [c, c]); return [d, [...d]]; });
  if (eyes !== 'normal') {
    for (const left of [2, 8]) for (let r = 6; r <= 9; r++) for (let c = 0; c < 4; c++) {
      const hole = eyes === 'weekly' ? [r - 6, 9 - r].includes(c) : r === 8;
      grid[r][left + c] = hole ? '.' : 'X';
    }
  }
  return grid.map((r) => r.join(''));
}

/** The item on a menu bar strip; st: { used, over, stale, warn, mac, eyes }, bar: 'dark' or 'light'. */
export function item(st, bar = 'dark') {
  const m = mask(st.eyes);
  const px = m.flatMap((row, y) => [...row].map((ch, x) => (ch === 'X' ? `<rect x="${x}" y="${y}" width="1" height="1"/>` : ''))).join('');
  const panda = `<svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor" aria-hidden="true" style="flex:none;shape-rendering:crispEdges">${px}</svg>`;
  const parts = [panda];
  if (st.used !== undefined && st.used !== null) parts.push(`<span style="font-weight:${st.over ? 'var(--tp-font-weight-semibold)' : 'var(--tp-font-weight-regular)'}">${st.used}%</span>`);
  if (st.warn) parts.push('<span style="font-family:var(--tp-font-family-mono);font-size:var(--tp-font-size-body)">⚠</span>');
  const mac = st.mac ? `<span style="font-weight:${st.over ? 'var(--tp-font-weight-semibold)' : 'var(--tp-font-weight-regular)'};margin-left:calc(var(--tp-size-item-gap) * -1)">${esc(st.mac)}</span>` : '';
  return `<div class="tp-strip ${bar}" role="img" aria-label="${esc(st.label ?? 'menu bar item')}"><span class="tp-item"${st.stale ? ' style="opacity:var(--tp-chrome-item-stale-opacity)"' : ''}>${parts.join('')}${mac}</span></div>`;
}

// ---------------------------------------------------------------- the nudge banner (NudgeRules, drawn by the OS)
export const banner = (title, body, time = 'now') => `<div class="tp-banner" role="img" aria-label="${esc(title)}">
  <div class="tx"><b>${esc(title)}</b><p>${esc(body)}</p></div><time>${esc(time)}</time></div>`;

SAMPLE.weeklyEarly = { title: 'Weekly (all models)', used: 2, elapsed: 1.79, over: false, reset: 'Resets Sun 18:00', countdown: 'in 6d 21h', status: 'On pace', projection: 'too early to project', allowance: '0.6% an hour left' };
SAMPLE.fiveEarly = { title: '5h window', used: 3, elapsed: 43.33, over: false, reset: 'Resets 23:50', countdown: 'in 2h 50m', status: 'Ahead', projection: '7% by reset at this rate', allowance: '34% an hour left' };
SAMPLE.items = {
  normal: { used: 45, label: 'Weekly 45% used, ahead, resets Sunday 18:00' },
  over: { used: 61, over: true, label: 'Weekly 61% used, over pace, resets Sunday 18:00' },
  stale: { used: 61, stale: true, label: 'Weekly 61% used, over pace, resets Sunday 18:00, as of 13:05' },
  weekly: { used: 100, over: true, eyes: 'weekly', label: 'weekly limit reached' },
  five: { used: 61, over: true, eyes: 'five', label: '5h limit reached' },
  warn: { used: 61, over: true, warn: true, label: 'Weekly 61% used, over pace, resets Sunday 18:00, Mac warning' },
  mac: { used: 61, over: true, mac: ' CPU 9%', label: 'Weekly 61% used, over pace, with the Mac figure' },
  none: { stale: true, label: 'Claude usage, no figures yet' },
};
SAMPLE.nudges = [
  ['Weekly at 86%', '3 days 3 h to the reset. At this pace the limit lands Fri 07:20.'],
  ['5h window ends in 15 min', '34% used.'],
];
