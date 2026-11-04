// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import tokens from '../build/json/tokens.json';
import { esc, note, title } from './_demo.js';

export default { title: 'Foundations' };

const table = (cols, head, rows) => `<div class="tbl" style="grid-template-columns:${cols}">${head.map((h) => `<span class="th">${esc(h)}</span>`).join('')}${rows.flat().map((c) => `<span>${c}</span>`).join('')}</div>`;

export const Colour = {
  render: () => {
    const byName = new Map();
    for (const t of tokens.filter((x) => x.type === 'color')) {
      const k = t.path.split('.').slice(2).join('-');
      const r = byName.get(k) ?? { name: k, swift: t.swift, desc: t.description };
      r[t.mode] = t.css;
      byName.set(k, r);
    }
    const sw = (css) => `<span class="sw" style="background:${css}"></span> ${esc(css)}`;
    return `${title('Colour, dark and light')}
      ${note('Every colour of Sources/Text/Tokens.swift. The panel draws the dark table under a dark appearance and the light partner of each token (Tokens.light) under a light one; the layout, the glyphs and the type stay the same. TokensSyncTests holds these values against Tokens.swift.')}
      ${table('max-content max-content max-content max-content minmax(0,1fr)', ['CSS variable', 'Tokens.swift', 'Dark', 'Light', 'Used for'],
        [...byName.values()].map((r) => [`--tp-color-${esc(r.name)}`, `Tokens.${esc(r.swift)}`, sw(r.dark), sw(r.light), `<span class="s-dim">${esc(r.desc)}</span>`]))}`;
  },
};

export const Type = {
  render: () => `${title('Type')}
    ${note('One face, the system monospace (SF Mono), 12 pt on a 16 pt line, regular and bold. Every line of the panel is set in it; columns align by cell count.')}
    <div class="tp" style="display:flex;flex-direction:column;gap:var(--tp-size-line)">
      <div><span class="s-text">Regular 400  61% used  1.02B  405.6k of 1M</span></div>
      <div><span class="s-bold">Bold 700  Weekly (all models)  Over pace</span></div>
      <div><span class="s-dim">Dim  Resets Sun 18:00  in 3d 3h</span></div>
      <div><span class="s-quiet">Quiet  Esc closes  Tab switches</span></div>
    </div>`,
};

export const Measures = {
  render: () => {
    const rows = tokens.filter((t) => ['size', 'cells', 'font'].includes(t.path.split('.')[0]));
    return `${title('Measures')}
      ${note('The panel measures of LineView, PanelSize and Grammar. A bar or a column is a count of cells; one cell is one character of SF Mono 12.')}
      ${table('max-content max-content minmax(0,1fr)', ['CSS variable', 'Value', 'Where'], rows.map((t) => [esc(t.name), esc(t.css), `<span class="s-dim">${esc(t.description)}</span>`]))}`;
  },
};
