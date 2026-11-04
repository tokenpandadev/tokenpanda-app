// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// Mermaid theme from the tokenpanda tokens. The flow files in design/wireframes/flows carry their own classDef lines
// from the wireframe stage; flowSource() swaps them for token based ones, so every flow takes the panel palette.
const pick = (tokens, path) => {
  const t = tokens.find((x) => x.path === path);
  if (!t) throw new Error(`no token ${path}`);
  return t.css;
};

export function mermaidConfig(tokens, mode) {
  const c = (n) => pick(tokens, `color.${mode}.${n}`);
  return {
    startOnLoad: false,
    securityLevel: 'strict',
    theme: 'base',
    fontFamily: pick(tokens, 'font.family.mono'),
    flowchart: { htmlLabels: true, curve: 'basis', wrappingWidth: 400 },
    themeVariables: {
      darkMode: mode === 'dark',
      background: c('stage'),
      fontFamily: pick(tokens, 'font.family.mono'),
      fontSize: pick(tokens, 'font.size.body'),
      primaryColor: c('box'),
      primaryTextColor: c('text'),
      primaryBorderColor: c('track'),
      lineColor: c('dim'),
      textColor: c('text'),
      mainBkg: c('box'),
      nodeBorder: c('track'),
      edgeLabelBackground: c('stage'),
    },
  };
}

/** The four kinds of step of the flow test: works, friction, broken, by hand. */
export function classDefs(tokens, mode) {
  const c = (n) => pick(tokens, `color.${mode}.${n}`);
  const ring = pick(tokens, 'size.focus-ring');
  return [
    `classDef works fill:${c('stage')},stroke:${c('track')},color:${c('text')},stroke-width:${ring}`,
    `classDef friction fill:${c('box')},stroke:${c('bold')},color:${c('bold')},stroke-width:2px`,
    `classDef broken fill:${c('stage')},stroke:${c('coral')},color:${c('coral')},stroke-width:2px`,
    `classDef byhand fill:${c('stage')},stroke:${c('dim')},color:${c('text')},stroke-width:${ring},stroke-dasharray:4 3`,
  ].map((l) => '  ' + l).join('\n');
}

export function flowSource(src, tokens, mode) {
  const lines = src.split('\n').filter((l) => !/^\s*classDef\s/.test(l));
  const at = lines.findIndex((l) => /^\s*flowchart\b/.test(l) ? true : /^\s*graph\b/.test(l));
  lines.splice(at + 1, 0, classDefs(tokens, mode));
  return lines.join('\n');
}
