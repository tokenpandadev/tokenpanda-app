# tokenpanda user flows, as built

Main at 4ca4160 (release 0.1.7). Each flow as numbered steps; the screens are in ../screens, the walk in ../walk.html, the results in ../flow-test.md. One Mermaid diagram per flow sits next to this file.

## 01 Download and first open

Diagram: 01-download-and-first-open.mmd

1. The releases page offers tokenpanda-0.1.7.zip and tokenpanda-0.1.7.zip.sha256.
2. In Terminal, shasum -a 256 -c checks the zip and prints OK; unzip and move tokenpanda.app to Applications.
3. With Homebrew instead: brew install tokenpandadev/tap/tokenpanda, and the caveats say Open Anyway and Remove before uninstalling.
4. Double click in Applications: macOS refuses, "Apple could not verify tokenpanda is free of malware".
5. System Settings, Privacy and Security, scroll to the bottom, Open Anyway.
6. The warning comes back once; Open Anyway starts the app.
7. The first thing the app shows is the notification permission prompt: nudges are on by default and the app asks at launch, before the user has seen it or knows what a nudge is.
8. The menu bar shows the panda alone at half strength: no figures yet. No window, no Dock icon.
9. On macOS 26 and later the item stays hidden until it is allowed in System Settings, Menu Bar; a crowded menu bar behind the notch hides it too, and nothing else says the app runs.

## 02 Set up the feed

Diagram: 02-set-up-the-feed.mmd

1. The Claude tab says what is needed: "needs Claude Code's status line feed, one statusLine entry in ~/.claude/settings.json", and one button, Install the status line hook.
2. With a status line of your own it says "your current status line is kept and chained".
3. Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and refreshInterval and is chained.
4. The windows then read "no session yet  open Claude Code once".
5. During the first call the open sessions show "waiting for the first reply" while both windows still say "open Claude Code once".
6. After the first reply: header Usage live, both windows with pace, the session with its context bar.
7. If settings.json is not valid JSON, Install on the Claude tab changes nothing on screen; the error is drawn only on the Settings tab, cut at the width, without its reason.
8. In Settings the row says "Install the status line entry" (the Claude tab says hook), and its second line runs past the popover edge: "...~/.claude/settings.js".

## 03 Read the panel

Diagram: 03-read-the-panel.mmd

1. The item shows the panda and the weekly percentage; semibold when over pace.
2. Weekly: bar with the tick at the elapsed share, "Resets Sun 18:00  in 3d 3h", "Over pace  limit Sun 01:20 at this rate", "0.5% an hour left". Coral past the tick only when over pace.
3. 5h window, the same five lines, for plans that have it.
4. Open sessions: project, model, context bar and "405.6k of 1M  41%"; hovering the figure shows list price, lines added and removed, effort.
5. Tokens by model, project or session with the price chip and the subagent share; click the switch or press m, p, s.
6. Week over week: four rows, the hit week marked with the time it hit.
7. With several sessions open the weekly figure jumps every few seconds between the values each session last saw: 28%, 12%, 28%, 18%, 11% within 30 s, in the bar, the item, the projection and the allowance.
8. Esc closes, Tab and Shift Tab switch tabs, Command Q quits.

## 04 Nudges

Diagram: 04-nudges.mmd

1. Nudges are on by default; permission is asked at launch.
2. The weekly passes 80% while a session feeds: "Weekly at 80%" with the countdown and the landing time, once per weekly window.
3. 15 minutes before the 5h reset: "5h window ends in 15 min" with the percentage, once per window.
4. Ultra: the frozen 5h record can still pass that test once, and announce the end of a window the plan no longer has.
5. Notifications denied: the Nudge row says "Notifications are off for this app in System" and stops at the edge; it does not open System Settings.
6. No nudge comes from stale figures: an hour without a session and the nudges wait.

## 05 The 5 hour window removed for Ultra (30 Oct 2026)

Diagram: 05-the-5-hour-window-removed-for-ultra-30-oct-2026.mmd

1. 30 Oct, evening: the feed stops sending five_hour for verified Ultra accounts. The app keeps the last figure (63% in this example) and draws it as live: countdown running, tick moving, "Over pace  limit 22:50 at this rate".
2. Near the stored reset the same 63% reads "Ahead  66% by reset", "185% an hour left".
3. If the 5h window was at 100% when the feed stopped, the panda shows - - eyes and VoiceOver says "5h limit reached" until the old reset.
4. Around the old reset a "5h window ends in 15 min" nudge can fire for it.
5. Today, 31 Oct: the 5h window is an empty bar with "Reset 00:10  no session since", under "Usage live" and a listed open session, and it stays that way for good. The smallest fix drops the window when a fresh feed comes without it.
6. A new Ultra user, whose feed never had five_hour, sees an empty 5h bar with "not in the last feed" for good.
7. Max and Pro feeds still carry five_hour; their panel is unchanged.

## 06 Weekly reset

Diagram: 06-weekly-reset.mmd

1. Before the reset the countdown reads in hours and minutes.
2. The reset passes with no session open: the weekly reads "Reset Sun 17:00  no session since", the item dims, the week row says "last seen 91%".
3. The reset passes while idle sessions feed: Claude Code drops the passed window, the app keeps it, and the weekly reads "no session since" under "Usage live" with sessions listed, until the next reply.
4. The next reply brings the new week: "1% used", "On pace", a new row in week over week.
5. Week over week keeps the last value seen per week; with several sessions that is whichever session wrote last, often an idle one with a lower figure.
6. At 100% the panda shows x x until the reset.

## 07 Stale or missing feed

Diagram: 07-stale-or-missing-feed.mmd

1. The last session closes: its row leaves after 60 s and the header says "Usage as of 13:05, last Claude Code session"; pace is still computed for an hour.
2. After an hour: the stale form, dim bars, "as of 13:05", the note that limits are shared, the item at half strength.
3. Use on the web or in the Claude app moves the limits, but the app sees it only when a Claude Code session feeds; the stale note says so.
4. An account without plan limits: "this account has no plan limits to show".
5. No transcripts folder: "No transcripts in ~/.claude/projects" in the token section; a read error shows its own message.
6. The statusLine entry removed by hand: the app notices the settings.json change on the next tick and offers Install again.

## 08 The Mac tab

Diagram: 08-the-mac-tab.mmd

1. Click Mac or press Tab: CPU, GPU, the memory grid with pressure and swap, battery, the busiest processes.
2. Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign.
3. Battery health unknown: "health n/a", never a dash.
4. Mac figures in the bar appends " CPU 9%" to the item.

## 09 Settings

Diagram: 09-settings.mmd

1. Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, Quit.
2. Open at login: the box shows what macOS says; while macOS waits for approval a dim line opens Login Items.
3. List price equivalent off: the price chip goes.
4. Quit and Command Q end the app; the item goes.
5. Nowhere in the app is the version: no About, no line in Settings.

## 10 Keep the Mac awake

Diagram: 10-keep-the-mac-awake.mmd

1. Keep the Mac awake while Claude works: while a session's figures move, "awake  1 session working" and one power assertion.
2. Also while a session waits for you: idle sessions count too, "awake  1 session open".
3. A closed lid on battery still sleeps the Mac; the README says so, the row does not.

## 11 Reopen sessions after a restart

Diagram: 11-reopen-sessions-after-a-restart.mmd

1. Turn on Reopen sessions after a restart: the app keeps the open sessions in restore.json, readable only by you.
2. After a restart, one notification: "3 Claude Code sessions were open before the restart", with Reopen.
3. Reopen opens each session in Terminal with claude --resume, and --remote-control where it had it.
4. With notifications off the offer never comes and the Reopen row does not say why.
5. Turning it off deletes restore.json.

## 12 Update

Diagram: 12-update.mmd

1. The app never checks for updates (no network); a new version is found on the releases page or with brew outdated.
2. brew upgrade --cask tokenpanda quits and replaces the app.
3. A new ad hoc build can bring back the Open Anyway steps, and the app has no version line to confirm what runs.
4. Settings, the hook, limits.json and weeks.json survive the update; Open at login keeps working.

## 13 Uninstall

Diagram: 13-uninstall.mmd

1. Settings, Remove the status line entry puts the previous statusLine back exactly, or removes the key.
2. If there was no settings.json before, an empty "{}" file stays.
3. Quit and move the app to the Bin.
4. Moved to the Bin without Remove first: the hook keeps running from Application Support and leaves one session file per session that nothing deletes.
5. brew uninstall --zap deletes the folder that holds hook.sh while settings.json still points at it: the Claude Code status line goes blank, including the status line the user had before.
6. Delete Application Support and the preferences file by hand; nothing else was created.

## 14 VoiceOver and the keyboard

Diagram: 14-voiceover-and-the-keyboard.mmd

1. VoiceOver on the item reads the state in words: "Weekly 28% used, ahead, resets sun 17:00".
2. Inside the popover VoiceOver reads each line as text, so the figures are heard.
3. The Install button, the tabs, the section switch and every checkbox are static text to VoiceOver: no role, no state, no press. A VoiceOver user cannot set up the feed or change a setting.
4. From the keyboard only Tab, Esc, m, p, s and Command Q work; no row takes focus and Space does nothing, so settings need a pointer.
5. The key hints are #505050 on the glass, about 2.1 to 1.
6. Reduce motion: the popover opens without animation.
