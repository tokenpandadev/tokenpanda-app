// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
/** Storybook 9, plain HTML stories on Vite. The snapshot references of the AppKit views are served as they are. */
export default {
  stories: ['../stories/**/*.stories.js'],
  framework: { name: '@storybook/html-vite', options: {} },
  core: { disableTelemetry: true },
  staticDirs: [{ from: '../../../Tests/tokenpandaTests/Snapshots', to: '/snapshots' }],
  // the flows live next to the wireframes, one folder up
  viteFinal: (config) => ({ ...config, server: { ...config.server, host: '127.0.0.1', fs: { ...(config.server?.fs ?? {}), allow: ['..', '../../..'] } } }),
};
