// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import * as T from '../src/panel.js';
import { demo, item, note } from './_demo.js';

export default { title: 'Panel' };

export const Assembled = {
  name: 'The three tabs',
  render: () => demo(
    item('Claude', T.panel(T.popover(0))),
    item('Mac', T.panel(T.popover(1))),
    item('Settings', T.panel(T.popover(2))),
  ) + note('The panel as LineView draws it, with the sample of Fixtures.swift. The Snapshots page shows the same parts rendered by the app.'),
};
