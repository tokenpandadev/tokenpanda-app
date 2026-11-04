// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import mermaid from 'mermaid';
import tokens from '../build/json/tokens.json';
import written from '../../wireframes/flows/flows.md?raw';
import { mermaidConfig, flowSource } from '../src/mermaid-theme.js';
import { esc, note } from './_demo.js';

const FLOWS = import.meta.glob('../../wireframes/flows/*.mmd', { query: '?raw', import: 'default', eager: true });
const NAMES = Object.keys(FLOWS).map((p) => p.split('/').pop()).sort();
let n = 0;

export default {
  title: 'Flows/Mermaid',
  argTypes: { flow: { control: 'select', options: NAMES } },
  args: { flow: NAMES[0] },
};

export const Flow = {
  render: ({ flow }) => {
    const mode = document.documentElement.dataset.theme ?? 'dark';
    const el = document.createElement('div');
    el.innerHTML = `<div class="demo-label">design/wireframes/flows/${esc(flow)}, themed from the tokens (${mode})</div><div class="flow" data-ready="false"></div>`
      + note('Steps are marked works, friction (a heavier outline), broken (coral) or by hand (dashed), as the flow test found them.');
    const box = el.querySelector('.flow');
    mermaid.initialize(mermaidConfig(tokens, mode));
    mermaid.render(`flow${n++}`, flowSource(FLOWS[`../../wireframes/flows/${flow}`], tokens, mode))
      .then(({ svg }) => { box.innerHTML = svg; box.dataset.ready = 'true'; })
      .catch((e) => { box.textContent = String(e); box.dataset.ready = 'error'; });
    return el;
  },
};

export const All = {
  name: 'All flows',
  render: () => {
    const mode = document.documentElement.dataset.theme ?? 'dark';
    const el = document.createElement('div');
    el.style.cssText = 'display:flex;flex-direction:column;gap:calc(var(--tp-size-line) * 2)';
    mermaid.initialize(mermaidConfig(tokens, mode));
    for (const name of NAMES) {
      const sec = document.createElement('div');
      sec.innerHTML = `<div class="demo-title">${esc(name)}</div><div class="flow" data-ready="false"></div>`;
      el.appendChild(sec);
      const box = sec.querySelector('.flow');
      mermaid.render(`flowall${n++}`, flowSource(FLOWS[`../../wireframes/flows/${name}`], tokens, mode))
        .then(({ svg }) => { box.innerHTML = svg; box.dataset.ready = 'true'; })
        .catch((e) => { box.textContent = String(e); box.dataset.ready = 'error'; });
    }
    return el;
  },
};

export const Written = {
  name: 'Written flows',
  parameters: { docs: { disable: true } },
  render: () => {
    // flows.md as it is: headings bold, numbered steps as lines, the rest dim
    const html = written.split('\n').map((l) => {
      if (l.startsWith('# ')) return `<div class="demo-title">${esc(l.slice(2))}</div>`;
      if (l.startsWith('## ')) return `<div class="demo-title" style="margin-top:var(--tp-size-line)">${esc(l.slice(3))}</div>`;
      if (/^\d+\. /.test(l)) return `<div class="s-text" style="white-space:pre-wrap">${esc(l)}</div>`;
      return l.trim() ? `<div class="s-dim" style="white-space:pre-wrap">${esc(l)}</div>` : '';
    }).join('');
    return `<div style="max-width:calc(var(--tp-size-panel-width) * 2)">${html}</div>`;
  },
};
