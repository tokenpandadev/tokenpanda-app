// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The parts of the panel, each in its states, drawn from the token variables by src/panel.js. Sample data only.
import * as T from '../src/panel.js';
import { demo, item, note } from './_demo.js';

export default { title: 'Parts' };
const S = T.SAMPLE;
const one = (lines) => T.panel(lines);

export const Tabs = {
  render: () => demo(
    item('Claude selected, a session feeds', one(T.header(S.header, 0))),
    item('Mac selected', one(T.header(S.header, 1))),
    item('with the Mac warning dot', one(T.header(S.header, 0, true))),
    item('Settings selected', one(T.header(S.header, 2))),
    item('between sessions', one(T.header('As of 13:05, last Claude Code session', 0))),
  ) + note('Line one is the updated line, dim. The rule in accent across the full width. The selected tab is inverted on the accent and bold; the others are text, white under the pointer.'),
};

export const SectionSwitch = {
  name: 'Section switch',
  render: () => demo(item('Models, Projects, Sessions selected', one([T.subTabs(0), T.subTabs(1), T.subTabs(2)])))
    + note('The selected sub tab is inverted on bold with the ink on bold; keys m, p and s switch it.'),
};

export const Bars = {
  render: () => {
    const b = (n, u, e, o) => T.L([T.P(' '), T.barPiece(T.bar(n, u, e, o)), T.P(` ${u}%`)]);
    return demo(
      item('36 cells: ahead 45 of 55, on pace 57 of 55, over pace 61 of 55, stale', one([b(36, 45, 54.96), b(36, 57, 54.96), b(36, 61, 54.96, { over: true }), b(36, 61, 54.96, { stale: true })])),
      item('24 cells, plain, in the row hues', one(['magenta', 'yellow', 'cyan', 'green', 'blue', 'blue2', 'proc-white'].map((h, i) => b(24, 70 - i * 9, null, { hue: h, plain: true })))),
      item('20 cells: a week', one([T.week(S.weeks[0]), T.week(S.weeks[1]), T.week(S.weeks[3])])),
    ) + note('Full cells and one eighth block for the remainder. The notch stands at the elapsed share in bold; the fill goes coral past it when over pace. Stale: the fill in the track colour on a track at 35%, the notch dim.');
  },
};

export const WindowSection = {
  name: 'Window section',
  render: () => demo(
    item('weekly, over pace', one(T.windowSection(S.weekly))),
    item('weekly, ahead', one(T.windowSection(S.weeklyAhead))),
    item('5h window, ahead', one(T.windowSection(S.five))),
    item('weekly, stale, as of 13:05', one(T.windowSection(S.weeklyStale))),
    item('three hours into the week: too early to project', one([...T.windowSection(S.weeklyEarly), T.L([]), ...T.windowSection(S.fiveEarly)])),
  ) + note('Before 5% of a window has passed, only Over pace projects; the other states say too early to project.'),
};

export const OpenSessions = {
  name: 'Open sessions',
  render: () => demo(
    item('two open sessions, hover a figure', one(T.sessionRows(S.sessions))),
    item('before the first reply', one(T.sessionRows([{ name: 'workspace', model: 'Fable 5.1', waiting: true }]))),
    item('none open', one(T.sessionRows([]))),
  ),
};

export const Rows = {
  name: 'Rows and chips',
  render: () => demo(
    item('models, 7 days', one(T.tokens(0))),
    item('projects, 7 days, first row under the pointer, its tooltip open', one(T.tokens(1, { hoverRow: 0, tipOpen: true }))),
    item('sessions, today', one(T.tokens(2))),
    item('processes by CPU, a selected row', one(S.rows.processes.map((r, i) => T.row(r, { selected: i === 0 })))),
  ) + note('Name column 14 cells, one space, a 24 cell plain bar in the family hue, two spaces, the figure right aligned in 5 cells. The chips under the rows are dim, in brackets.'),
};

export const Weeks = {
  render: () => demo(item('week over week, the current week so far', one([T.L([T.P(' '), T.P('Week over week', 'bold')]), ...S.weeks.map(T.week)]))),
};

export const MemoryGrid = {
  name: 'Memory grid',
  render: () => demo(item('25.5 of 36 GB, pressure normal, swap 0.9 GB', one(T.memGrid(S.memory))))
    + note('20 by 10 cells: used in accent, free in dimmer, swap in warning from the end. Each glyph sits in a two cell box.'),
};

export const MacBars = {
  name: 'Mac bars',
  render: () => demo(item('CPU, GPU, battery', one([...T.macBar('CPU', S.mac.cpu, [S.mac.cpuLine]), T.L([]), ...T.macBar('GPU', S.mac.gpu, ['device utilisation']), T.L([]),
    ...T.macBar('Battery', S.mac.battery, [S.mac.battery1, S.mac.battery2])]))),
};

export const SettingsRows = {
  name: 'Settings rows',
  render: () => demo(
    item('off, on, click to toggle', one([...T.cbRow('Mac figures in the bar', false), ...T.cbRow('List price equivalent', true, ['tokens at list prices, not the plan price'])])),
    item('a link under a row', one(T.cbRow('Nudge at 80% and before the 5h end', true, [{ link: 'Notifications are off in System Settings' }]))),
    item('the settings tab, the nudge row under the pointer, the keyboard on the second row', one(T.settingsTab({ hover: true, focus: true }))),
  ) + note('The bracket checkbox, a label after it, a dim explanation indented under the label. The focus ring is a 1 pt accent outline outside the control.'),
};

export const Tooltip = {
  render: () => {
    const r = S.rows.models[0];
    return demo(
      item('readout, open', one([T.L([]), T.L([]), T.row(r, { tipOpen: true })])),
      item('session figure, left aligned', one([T.L([]), T.L([]), T.L([T.P(' '), T.barPiece(T.bar(24, 41, null, { hue: 'magenta', plain: true })), T.P('  '),
        T.P('405.6k of 1M  41%', 'text', { tip: S.sessions[0].tip, tipLeft: true, open: true })])])),
    ) + note('The box ground, text in the default colour, one cell of padding each side, above the figure.');
  },
};

export const MenuBarItem = {
  name: 'Menu bar item',
  render: () => {
    const I = S.items;
    const states = [['normal, ahead', I.normal], ['over pace, semibold', I.over], ['stale, half strength', I.stale], ['weekly limit, x x', I.weekly],
      ['5h limit, - -', I.five], ['Mac warning', I.warn], ['with the Mac figure', I.mac], ['no figures yet', I.none]];
    return ['dark', 'light'].map((bar) => demo(...states.map(([label, st]) => item(`${label}, ${bar} bar`, T.item(st, bar))))).join('')
      + note('The panda as a 7 by 7 pixel mark, a 5 pt gap, the weekly percentage in SF with tabular digits. Monochrome: a template image the OS inks for the menu bar.');
  },
};

export const NudgeBanner = {
  name: 'Nudge banner',
  render: () => demo(...S.nudges.map(([t, b], i) => item(i === 0 ? 'at 80%' : 'before the 5h end', T.banner(t, b))))
    + note('The macOS notification banner as the OS draws it, no icon. The texts are NudgeRules with the sample.'),
};
