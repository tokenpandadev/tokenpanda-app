# tokenpanda user flows, as built

Brought to 0.1.14 (4.11.2026, main at 2bc3011, tag v0.1.14; the screens draw 0.1.14 too). Each flow as numbered steps; the screens are in ../screens, the walk in ../walk.html, the results in ../flow-test.md. One Mermaid diagram per flow sits next to this file.

## 01 Download and first open

Diagram: 01-download-and-first-open.mmd

1. The releases page offers the zip of each version and its .sha256; the README says it runs on a Mac with Apple silicon (M1 or later) on macOS 14 or later.
2. In Terminal, shasum -a 256 -c checks the zip and prints OK; unzip and move tokenpanda.app to Applications.
3. With Homebrew instead: brew trust --cask, then brew install tokenpandadev/tap/tokenpanda; the cask declares Apple silicon only, so an Intel Mac is refused, and the caveats say Open Anyway and explain the zap.
4. Double click in Applications: macOS refuses the ad hoc build, "Apple could not verify tokenpanda is free of malware".
5. System Settings, Privacy and Security, scroll to the bottom, Open Anyway.
6. The warning comes back once; Open Anyway starts the app.
7. No notification prompt at launch: the app asks when the first nudge is due, or when Nudge or Reopen sessions is ticked.
8. The menu bar shows the panda alone at half strength: no figures yet. No window, no Dock icon.
9. If the icon is not on screen five seconds after the first launch, one window: "tokenpanda is running". From macOS 26 the icon "may be switched off in System Settings, Menu Bar, or hidden behind the notch", with "Open Menu Bar Settings" and "OK"; before macOS 26 the menu bar is full and the icon is behind the notch, quitting another menu bar app makes room, with "OK" only. While the screen is locked, the session is switched away or the display sleeps, it waits and asks again. It shows once.
10. Switching the item on in System Settings, Menu Bar, is the user's click.

## 02 Set up the feed

Diagram: 02-set-up-the-feed.mmd

1. The Claude tab says what is needed: "needs Claude Code's status line feed", "one statusLine entry in ~/.claude/settings.json", "chained if one exists", and one button, Install the status line entry.
2. With a status line of your own it says "your current status line is kept and chained".
3. Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and a refreshInterval of 5 or less and is chained.
4. The windows then read "no session yet  open Claude Code once".
5. During the first call both windows and the session say "waiting for the first reply".
6. After the first reply: "Live from Claude Code", the windows with pace, each session with its bar.
7. A settings.json that is not valid JSON, or valid JSON that is not an object: Install says why under the button, wrapped, on the Claude tab and in Settings.
8. Both places name the button "Install the status line entry", and no line runs past the panel edge.
9. Several settings folders each get their own script and backup; a folder with only transcripts is left alone; a lost script offers Install again.
10. A settings.json that is a link stays a link, and the file it names keeps its mode; a created settings.json is 0600.
11. disableAllHooks on: "disableAllHooks is on in settings.json  so Claude Code runs no status line".
12. An entry installed by an earlier version gets the current script at the next launch, its chained command kept.

## 03 Read the panel

Diagram: 03-read-the-panel.mmd

1. The item shows the panda and the weekly percentage; semibold when over pace.
2. Weekly: bar with the notch at the elapsed share, the reset and countdown, the status and projection, the allowance. Coral past the notch only when over pace.
3. 5h window, the same five lines, for plans that have it.
4. Open sessions by name (set with -n or /rename), by folder when unnamed, each with its model, its 24 cell context bar and "405.6k of 1M  41%"; the figure's tooltip breaks over two lines inside the panel.
5. Tokens by model, project or session with the price chip and the subagent share; click the switch or press m, p, s.
6. Week over week: up to four rows, the current week "so far", a hit week marked with the time it hit.
7. With several sessions open the weekly figure holds still: the highest figure at the latest reset, across every session file.
8. Esc closes, Tab and Shift Tab switch tabs, Command Q quits.
9. The header says where the figures come from: "Live from Claude Code", "As of 22:02, last Claude Code session", or "Waiting for a Claude Code session".
10. After midnight the token rows stay: the first pass of a new day sums every record, not only new ones.
11. On a short or scaled screen the panel stops 60 points short of the screen's visible height and scrolls with an overlay scroller and no rubber band, from the top on every open and tab click; the keyboard focus scrolls into view, and a tooltip with no room above opens below its line.

## 04 Nudges

Diagram: 04-nudges.mmd

1. Permission is asked when the first nudge is due or Nudge is ticked, not at launch.
2. The weekly passes 80% while a session feeds: "Weekly at 80%" (the percentage when it fires) with the countdown and the landing time, once per weekly window.
3. 15 minutes before the 5h reset: "5h window ends in 15 min" with the percentage, once per window.
4. No 5h nudge from a window the plan no longer has.
5. Notifications denied: "Notifications are off in System Settings" under Nudge, and under Reopen while it is on, in the accent, a link the keyboard and VoiceOver reach, said once.
6. The click opens System Settings, Notifications, at tokenpanda.
7. Notifications turned on in System Settings count at once: the note goes at the next open of the popover, and the next nudge is posted, no restart.
8. No nudge comes from stale figures: an hour without a session and the nudges wait.

## 05 The 5 hour window removed for Ultra (30 Oct 2026)

Diagram: 05-the-5-hour-window-removed-for-ultra-30-oct-2026.mmd

1. The feed stops carrying five_hour while the stored 5h window still runs: the last percent dim, "not in the last feed", no countdown or pace.
2. A retired 5h window at 100% gives normal eyes and no "5h limit reached".
3. No false "5h window ends in 15 min".
4. After the old reset the 5h row goes for good: a reply without five_hour hides it.
5. A new Ultra user sees the weekly alone after the first reply.
6. Max and Pro keep both windows.
7. Before the first reply a new Ultra user still sees a "5h window" row, and the Install text is titled "Weekly and 5h window".
8. On Ultra the nudge row reads "Nudge at 80%".

## 06 Weekly reset

Diagram: 06-weekly-reset.mmd

1. Before the reset the countdown reads in days and hours, then hours and minutes.
2. The reset passes with no session: "Reset Sun 17:00  no session since", the item dims; the old week keeps its figure and the new week says "no reply yet".
3. The reset passes while idle sessions feed: "new window on the next reply".
4. The next reply brings the new week: a low figure, "On pace" or "Ahead", a new row in week over week.
5. Week over week keeps the highest value seen per week.
6. At 100% the panda shows x x until the reset.

## 07 Stale or missing feed

Diagram: 07-stale-or-missing-feed.mmd

1. The last session closes: its row leaves after 60 s and the header says "As of 13:05, last Claude Code session"; pace is still computed for an hour.
2. After an hour: the stale form, dim bars, "as of 13:05", the note that limits are shared with the Claude app and other Macs, the item at half strength.
3. Use on the web, in the Claude app or on another Mac shows only with the next Claude Code reply on this Mac; the stale note says so.
4. Sessions on an API key, Bedrock or Vertex: "these sessions carry no plan limits".
5. No transcripts folder: "No transcripts in ~/.claude/projects" in the token section; a read error shows its own message.
6. The statusLine entry removed by hand: the app notices the settings.json change on the next tick and offers Install again.

## 08 The Mac tab

Diagram: 08-the-mac-tab.mmd

1. Click Mac or press Tab: CPU, GPU, the memory grid with pressure and swap, battery, the busiest processes.
2. The free cells of the memory grid are #949494, 3 to 1 even over a white desktop.
3. Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign.
4. Battery health unknown: "health n/a", never a dash.
5. Mac figures in the bar appends " CPU 9%" to the item.
6. Claude Code's processes show as "Claude Code".

## 09 Settings

Diagram: 09-settings.mmd

1. Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, the version line, Quit.
2. Open at login: the box shows what macOS says; while macOS waits for approval a dim line opens Login Items.
3. List price equivalent off: the price chip goes.
4. Quit and Command Q end the app; the item goes.
5. The version line says what runs: "tokenpanda 0.1.14".
6. Light mode: the same layout on a light glass, switching with the Mac's appearance.
7. A tall Settings tab on a short screen scrolls inside the panel, so Quit stays reachable.

## 10 Keep the Mac awake

Diagram: 10-keep-the-mac-awake.mmd

1. Keep the Mac awake while Claude works: while a session's figures move, "awake  1 session working" and one power assertion.
2. Also while a session waits for you: idle sessions count too, "awake  1 session open".
3. The row says "a closed lid on battery still sleeps".

## 11 Reopen sessions after a restart

Diagram: 11-reopen-sessions-after-a-restart.mmd

1. Turn on Reopen sessions after a restart: the app keeps the open sessions with their names and start options in restore.json, readable only by you.
2. After a restart, one notification names the sessions that were open, with Reopen.
3. Reopen opens each session in Terminal as it was started, with --remote-control where it had it, and the fallbacks.
4. With notifications off the Reopen row says so, as the same link as under Nudge; turned on again, the offer and the end notices come without a restart.
5. Turning it off deletes restore.json.
6. A print run is never reopened; a start prompt is not sent again.
7. The end notice also comes after a deliberate /exit in a window you keep.

## 12 Update

Diagram: 12-update.mmd

1. The app never checks for updates (no network); a new version is found on the releases page or with brew outdated.
2. brew upgrade --cask tokenpanda quits and replaces the app.
3. A new ad hoc build can bring back the Open Anyway steps; the version line in Settings confirms what runs.
4. Settings, the entry and the records survive the update, and the installed script is brought up to date at launch.

## 13 Uninstall

Diagram: 13-uninstall.mmd

1. Settings, Remove the status line entry puts the previous statusLine back exactly, or removes the key.
2. A settings.json Install created is deleted on Remove; when it is a link whose file Install created, the file goes and the link stays.
3. Quit and move the app to the Bin.
4. Moved to the Bin without Remove: the script deletes its folder's session files that stopped changing over a minute ago, so the leftover stays small.
5. brew uninstall --zap runs remove.sh, which puts the previous status line back, the same way through a link (readlink -f), before the data folder goes.
6. Delete Application Support and the preferences file by hand; nothing else was created.

## 14 VoiceOver and the keyboard

Diagram: 14-voiceover-and-the-keyboard.mmd

1. VoiceOver on the item says "tokenpanda, Weekly 28% used, ahead, resets Sunday 17:00".
2. The privacy sentence is one element, and each window, week and Mac figure is one sentence.
3. Tabs are radio buttons, settings checkboxes with values, Install, Remove, Quit and the notifications link buttons with press.
4. The keyboard reaches every control: Down and Up, Left and Right, Space or Return; a thin accent ring shows where.
5. The key hints read clearly over white, at 4.5 to 1 or more.
6. Reduce motion: the popover opens without animation.
7. Down also stops on the key figures, and in a panel shorter than its lines the focused one is scrolled into view.
8. In a panel capped by a small screen VoiceOver reads every line, but before macOS 26 its outline is not shown on a line outside the visible part, since VoiceOver cannot ask the app to scroll there.
