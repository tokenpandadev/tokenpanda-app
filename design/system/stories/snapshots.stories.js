// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The reference images of PanelSnapshotTests: the real AppKit LineView, rendered offscreen, beside the HTML parts.
import * as T from '../src/panel.js';
import { demo, item, note } from './_demo.js';

export default { title: 'Snapshots' };
const S = T.SAMPLE;
const img = (name, mode) => `<img class="shot" src="snapshots/${name}-${mode}.png" alt="${name}, ${mode}, rendered by LineView">`;
const PARTS = [
  ['tabs-claude', () => T.header(S.header, 0)],
  ['tabs-mac-warning', () => T.header(S.header, 1, true)],
  ['section-switch', () => [T.subTabs(0), T.subTabs(1), T.subTabs(2)]],
  ['window-over-pace', () => [...T.windowSection(S.weekly), T.L([]), ...T.windowSection(S.five)]],
  ['window-too-early', () => [...T.windowSection(S.weeklyEarly), T.L([]), ...T.windowSection(S.fiveEarly)]],
  ['sessions', () => T.sessionRows(S.sessions)],
  ['rows-and-chips', () => T.tokens(0)],
  ['row-hover-tooltip', () => T.tokens(0, { hoverRow: 0, tipOpen: true })],
  ['weeks', () => S.weeks.map(T.week)],
  ['memory-grid', () => T.memGrid(S.memory)],
  ['settings-rows', () => T.settingsTab()],
  ['focus-ring', () => T.settingsTab({ focus: true })],
  ['popover-claude', () => T.popover(0)],
  ['popover-mac', () => T.popover(1)],
  ['popover-settings', () => T.popover(2)],
];

const I = S.items;
const ITEMS = [['item-normal', I.normal], ['item-over-pace', I.over], ['item-stale', I.stale], ['item-weekly-limit', I.weekly],
  ['item-five-limit', I.five], ['item-mac-warning', I.warn], ['item-mac-figure', I.mac], ['item-no-figures', I.none]];

export const AppKitBesideHTML = {
  name: 'AppKit beside HTML',
  render: () => {
    const mode = document.documentElement.dataset.theme ?? 'dark';
    return note('Left: the app, LineView drawn offscreen by the snapshot tests (Tests/tokenpandaTests/Snapshots). Right: the same part in HTML from the tokens. The appearance switch picks dark or light.')
      + PARTS.map(([name, lines]) => demo(item(`${name}, app`, img(name, mode)), item(`${name}, HTML`, T.panel(lines())))).join('')
      + ITEMS.map(([name, st]) => demo(item(`${name}, app`, `<img src="snapshots/${name}-${mode}.png" alt="${name}, ${mode}" style="height:24px">`), item(`${name}, HTML`, T.item(st, mode)))).join('');
  },
};
