// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import '../build/css/tokens.css';
import '../src/panel.css';
import './preview.css';

export const globalTypes = {
  theme: {
    description: 'Appearance',
    toolbar: { title: 'Appearance', icon: 'mirror', items: [{ value: 'dark', title: 'Dark' }, { value: 'light', title: 'Light' }], dynamicTitle: true },
  },
};
export const initialGlobals = { theme: 'dark' };

export const decorators = [
  (storyFn, context) => {
    document.documentElement.dataset.theme = context.globals.theme ?? 'dark';
    const out = storyFn();
    const el = document.createElement('div');
    el.className = 'tp stage';
    if (typeof out === 'string') el.innerHTML = out; else el.appendChild(out);
    return el;
  },
];

export const parameters = {
  layout: 'fullscreen',
  controls: { expanded: true },
  options: {
    storySort: { order: ['Foundations', 'Parts', 'Panel', 'Snapshots', 'Flows', ['Mermaid', 'Written flows']] },
  },
};
