# tokenpanda design system

The panel's design in code: one token file, a Storybook of the parts and flows, and snapshot tests of the real AppKit views.

## What is where

- `tokens.json`: every value, in W3C DTCG format. Colour has two modes. Dark is the table in `Sources/Text/Tokens.swift`; light is its partner from `Tokens.light`, plus `tintLight` and `stageLight`. It also holds the panel measures of `LineView`, `PanelSize` and `Grammar`.
- `style-dictionary.config.js`: builds three files from `tokens.json`:
  - `build/css/tokens.css`: CSS variables `--tp-*`, dark and light under `[data-theme]`
  - `build/json/tokens.json`: a flat list for the Storybook pages
  - `../../Tests/tokenpandaTests/Generated/DesignTokens.swift`: the tokens as Swift, compiled into the tests only

  `build/` is gitignored; the generated Swift is committed.
- `Tests/tokenpandaTests/TokensSyncTests.swift`: holds `tokens.json`, the generated Swift, `Tokens.swift` and the panel measures against each other. It reads `Tokens.swift`, so a colour added there and not to the token file fails the test, and so does the other way round.
- `src/panel.js`, `src/panel.css`: the line grammar (bars, rows, tabs, chips, weeks, memory grid, settings rows, tooltip), drawn in HTML from the token variables. It uses the sample data of `Sources/UI/Fixtures.swift`.
- `src/mermaid-theme.js`: themes the flows in `../wireframes/flows/*.mmd` from the tokens.
- `stories/`: the Storybook pages.
  - Foundations: colour, type, measures
  - Parts: every part in its states
  - Panel: the three tabs
  - Snapshots: the AppKit renders beside the HTML parts
  - Flows: each Mermaid flow, all flows, and `flows.md`
- `Tests/tokenpandaTests/ItemSnapshotTests.swift`: the real `ItemImage` in 8 states (normal, over pace, stale, weekly and 5h limit eyes, Mac warning, Mac figure, no figures) on a dark and a light menu bar strip. The strip colours are the `chrome` tokens. The nudge banner is drawn by the OS and has no view to render, so the test checks its texts against `NudgeRules` and Storybook draws it.
- `Tests/tokenpandaTests/PanelSnapshotTests.swift`: draws 17 panel parts with the real `LineView`, offscreen through `bitmapImageRepForCachingDisplay`, in dark and light. Each render is compared with its PNG in `Tests/tokenpandaTests/Snapshots/`. On CI (`CI` is set) the parts are still drawn and measured, but the pixels are not compared, because another Mac renders the font differently.

## Regenerate

From this folder (`npm ci --offline` installs from the npm cache; the versions are pinned in `package.json`):

```sh
npm ci --offline
npm run tokens            # tokens.json to CSS, JSON and the test Swift
npm run build-storybook   # static output in storybook-static/ (gitignored)
npm run storybook         # dev server on 127.0.0.1:6007
```

To check the tokens and the snapshots, run this from the repository root:

```sh
swift test --filter TokensSyncTests --filter PanelSnapshotTests
```

After a deliberate change to the look, write the references anew and look at every image before committing:

```sh
TP_RECORD_SNAPSHOTS=1 swift test --filter PanelSnapshotTests
```

To change a value, edit `tokens.json`, run `npm run tokens`, then make the same change in `Tokens.swift` or the view. The sync test fails until all three agree.

## Dependency advisories

Everything here is a dev tool: none of it ships in the app, the cask or the docs site. `package.json` pins Storybook 9.1.21 and sets three overrides that clear the moderate advisories without leaving 9.1.21:

- `glob` 14.0.3 and `minimatch` 11.0.4, under style-dictionary's bundled glob (GHSA-3g3m-2fjr-6pw4, GHSA-g3hv-75wg-m249)
- `@vitest/mocker` 4.1.12, under storybook (GHSA-82fw-gwwq-j7x9, GHSA-qxg6-89mg-rqv8)

With the overrides, `npm run tokens`, `npm run build-storybook` and `npm run storybook` were all run, and every story was drawn in both appearances.

One advisory stays open: `deepmerge` (GHSA-gcqx-w48m-w2h4, prototype pollution in `mergeObject`), which npm audit reports as low. Every deepmerge version from 4.2.0 is affected, and the only fix npm offers is style-dictionary 3, a breaking downgrade. Here deepmerge only merges this repository's own `tokens.json` and config at build time on the developer's Mac. No outside or user input reaches it, so it is accepted until style-dictionary ships a fixed dependency.
