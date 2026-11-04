// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
export const item = (label, html) => `<div class="demo-item"><div class="demo-label">${esc(label)}</div>${html}</div>`;
export const demo = (...items) => `<div class="demo">${items.join('')}</div>`;
export const note = (t) => `<div class="demo-note">${esc(t)}</div>`;
export const title = (t) => `<div class="demo-title">${esc(t)}</div>`;
