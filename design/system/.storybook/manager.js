// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import { addons } from 'storybook/manager-api';
import { create } from 'storybook/theming';
import { STORY_CHANGED } from 'storybook/internal/core-events';

addons.setConfig({
  theme: create({ base: 'dark', brandTitle: 'tokenpanda design system' }),
  sidebar: { showRoots: false },
});

// The addon panel opens only on stories with a control to pick; every other page gets the whole canvas.
const WITH_CONTROLS = ['flows-mermaid--flow'];
addons.register('tokenpanda/layout', (api) => {
  const fit = () => api.togglePanel(WITH_CONTROLS.includes(api.getUrlState().storyId ?? ''));
  api.on(STORY_CHANGED, fit);
  setTimeout(fit, 0);
});
