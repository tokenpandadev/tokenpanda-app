# Flow test of tokenpanda as built (31.10.2026)

Product: main at 4ca4160, release 0.1.7, the running app on this Mac is the same build. No app code was changed for this test.

Method: the product read first (README, CHANGELOG, docs/spec.html, styleguide.html, privacy.html, every file in Sources/ and Tests/, the scripts, the cask), then the flows written as numbered steps (flows/), then every step checked twice:

1. In the real app. swift build and the 97 tests pass with the Command Line Tools (DEVELOPER_DIR, the Xcode licence is not accepted on this Mac). The debug binary ran against throwaway homes (CFFIXED_USER_HOME) with crafted status line feeds, rendering its own tabs with --live-snapshot (live-<name>); --snapshot rendered the fixtures (fixtures/<name>); a harness linked against the debug objects rendered crafted inputs through ScreenBuilder, Grammar and SnapshotWriter (states/<name>) and ran the real Hook install, hook script and uninstall on throwaway folders (hookrun). The real data folder of the running 0.1.7 was read, never written. Screenshots were looked at one by one and are not kept in the repository.
2. In the wireframes: every screen of the step exists, and the step can be reached from the step before by a click or a key, or by a dashed target for another outcome or another start (press h, or walk mode, shows them). "click" below means reachable that way, "next" means the walk moves on with Next, "start" is the first step of a flow.

## Counts

1. Flows: 14. Steps: 83.
2. In the real app: 51 work, 20 friction, 12 broken.
3. In the wireframes: 83 of 83 steps drawn; 69 reached by a click or key from the step before, 14 flow starts, 0 reached with Next.
4. Screens: 80, a 1280 by 800 desktop with the menu bar, the popover at its real 380 point width and 16 point lines.

## The 5 hour window for Ultra, exactly

What happened: on 30 Oct 2026 Anthropic removed the 5 hour window for verified Ultra accounts; Max and Pro keep it. The status line feed stopped carrying rate_limits.five_hour for those accounts. On this Mac the ten live session files carry seven_day only, and limits.json still holds five_hour used 1, resetsAt 31 Oct 00:10, previousResetsAt 30 Oct 19:10, next to a fresh seven_day (asOf 11:11 today).

Why it sticks: Limits.apply (Sources/Feed/FeedReader.swift:23-38) loops over the keys the feed carries and never removes one it does not carry, and the result is persisted to limits.json. ScreenBuilder.windowView (Sources/UI/ScreenBuilder.swift:60-79) only reaches mode .absent (line 62) when no record exists, so once a five_hour record was ever stored it is drawn for good. Staleness is judged by limits.asOf (line 69), which the weekly keeps fresh, so the old 5h record is never shown as stale.

What an Ultra user saw and sees:
1. 30 Oct, from the last five_hour feed until its reset at 00:10: the last 5h percentage as if live, with a running countdown, a moving tick, a status word and a projection computed from a figure that no longer changes (an example figure, the last one on this Mac was 1%; states/ultra-evening: "63% used, Resets 00:10 in 2h 40m, Over pace  limit 22:50 at this rate"; states/ultra-late at 23:58: "Ahead  66% by reset at this rate, 185% an hour left"). The real binary does the same: live-ultra-day1 kept five_hour 63 through 50 s of feeds without it.
2. If that last figure was 100: the panda's - - eyes and "5h limit reached" in the spoken label until 00:10 (ScreenBuilder.swift:292-299), and a "5h window ends in 15 min" nudge can fire at 23:55 (Controller.swift:420-424).
3. From 00:10 on, today and every day after: "5h window", an empty bar, "Reset 00:10  no session since", under the header "Usage live  Mac live" with open sessions listed below (live-ultra-today, the exact state of this Mac). The clock has no day, so it reads as today.
4. A new Ultra user, whose feed never carried five_hour, sees "5h window", an empty bar, "not in the last feed", for good.

The smallest correct fix, in two parts:
1. Sources/Feed/FeedReader.swift, Limits.apply, at the start of the function: `for key in windows.keys where rateLimits[key] == nil { windows.removeValue(forKey: key) }`. apply runs only for a snapshot that carries rate_limits (FeedReader.swift:98 and :101), so the first call of a session, which has none, still changes nothing, as the spec requires. The Anthropic doc quoted in spec 3 already says "Each window may be independently absent, and Claude Code drops a window once its resets_at time passes". The next scan writes limits.json without five_hour; the nudge, the eyes and the label stop at once because they read the same record.
2. Sources/UI/ScreenBuilder.swift line 83: draw a fixed key only while its record exists: `var views = keys.filter { limits.windows[$0] != nil }.map { ... }`, and when that leaves nothing, the weekly as .absent. Ultra users then see the weekly alone; without part 2 they see the existing honest mark, an empty bar with "not in the last feed".
Kept for plans that still send it: a Max or Pro feed carries five_hour on every call after the first, so apply keeps setting it and the section stays exactly as today (live-max). Tests to add in FeedTests: a feed with seven_day only after one with both removes five_hour; a first call without rate_limits after that keeps seven_day; the stored record of a Max feed survives. The same change also ends gap 6, the weekly "no session since" after a reset.

## 01 Download and first open

1. works. The releases page offers tokenpanda-0.1.7.zip and tokenpanda-0.1.7.zip.sha256. Screens: browser-release. Do: Download both. Evidence: README.md, Install; build/release-notes-0.1.7.md. Wireframe: start.
2. works. In Terminal, shasum -a 256 -c checks the zip and prints OK; unzip and move tokenpanda.app to Applications. Screens: term-shasum. Do: Run the two lines. Evidence: README.md, Install; build/tokenpanda-0.1.7.zip.sha256. Wireframe: click.
3. works. With Homebrew instead: brew install tokenpandadev/tap/tokenpanda, and the caveats say Open Anyway and Remove before uninstalling. Screens: term-brew. Do: Read the caveats. Evidence: Casks/tokenpanda.rb:26-33. Wireframe: click.
4. friction. Double click in Applications: macOS refuses, "Apple could not verify tokenpanda is free of malware". Screens: finder-apps, gk-blocked. Do: Click Done. Evidence: codesign: Signature=adhoc, TeamIdentifier not set; spctl -a -t exec: rejected. By design for now (spec 17, path one). Wireframe: click.
5. friction. System Settings, Privacy and Security, scroll to the bottom, Open Anyway. Screens: gk-settings. Do: Find the button. Evidence: README.md, Install; spec 17. Not walked on a clean account in this run (left out 1). Wireframe: click.
6. works. The warning comes back once; Open Anyway starts the app. Screens: gk-confirm. Do: Click Open Anyway. Evidence: README.md, Install. Wireframe: click.
7. friction. The first thing the app shows is the notification permission prompt: nudges are on by default and the app asks at launch, before the user has seen it or knows what a nudge is. Screens: notif-permission. Do: Allow or not, without context. Evidence: Controller.swift:124; Settings.swift:21 (nudges default true); Notifier.swift:40-51. Wireframe: click.
8. works. The menu bar shows the panda alone at half strength: no figures yet. No window, no Dock icon. Screens: desk-nofeed. Do: Click the panda. Evidence: fixtures/item-nofeed; ScreenBuilder.swift:315-319; LSUIElement in scripts/build-app.sh. Wireframe: click.
9. friction. On macOS 26 and later the item stays hidden until it is allowed in System Settings, Menu Bar; a crowded menu bar behind the notch hides it too, and nothing else says the app runs. Screens: desk-hidden, sys-menubar. Do: Allow it under Menu Bar. Evidence: README.md, Install; spec 19, by hand. Wireframe: click.

## 02 Set up the feed

1. works. The Claude tab says what is needed: "needs Claude Code's status line feed, one statusLine entry in ~/.claude/settings.json", and one button, Install the status line hook. Screens: pop-nohook. Do: Read, click Install. Evidence: live-nohook tab0; Grammar.swift:100-110. Wireframe: start.
2. works. With a status line of your own it says "your current status line is kept and chained". Screens: pop-nohook-chained. Do: Click Install. Evidence: Grammar.swift:105; hookrun own-statusline: the hook printed MINE, the user's own output. Wireframe: click.
3. works. Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and refreshInterval and is chained. Screens: editor-after. Do: Nothing to do. Evidence: hookrun no-settings, no-statusline, own-statusline; Hook.swift:108-136. Wireframe: click.
4. works. The windows then read "no session yet  open Claude Code once". Screens: pop-nosession. Do: Start Claude Code. Evidence: fixtures/claude-nosession; Grammar.swift:111-113. Wireframe: click.
5. friction. During the first call the open sessions show "waiting for the first reply" while both windows still say "open Claude Code once". Screens: term-claude, pop-firstcall. Do: Send a first prompt. Evidence: states/claude-first-call; Grammar.swift:112; ScreenBuilder.swift:93-95. Wireframe: click.
6. works. After the first reply: header Usage live, both windows with pace, the session with its context bar. Screens: pop-live. Do: Read the figures. Evidence: live-max tab0; fixtures/claude-overpace. Wireframe: click.
7. broken. If settings.json is not valid JSON, Install on the Claude tab changes nothing on screen; the error is drawn only on the Settings tab, cut at the width, without its reason. Screens: editor-broken, pop-install-failed, pop-settings-error. Do: Click Install, wonder, open Settings. Evidence: hookrun broken-json: "cannot read settings.json: settings.json is not a JSON object"; Grammar.swift:100-110 draws no error; ScreenBuilder.swift:284-285 passes hookError to Settings only; states/settings-errors. Wireframe: click.
8. friction. In Settings the row says "Install the status line entry" (the Claude tab says hook), and its second line runs past the popover edge: "...~/.claude/settings.js". Screens: pop-settings-nohook. Do: Click it. Evidence: live-settings tab2 and states/settings-nohook-denied: the line is cut; Grammar.swift:318 (51 cells in a 47 cell popover). Wireframe: click.

## 03 Read the panel

1. works. The item shows the panda and the weekly percentage; semibold when over pace. Screens: desk. Do: Glance. Evidence: fixtures/closed; ItemImage.swift:54-99. Wireframe: start.
2. works. Weekly: bar with the tick at the elapsed share, "Resets Sun 18:00  in 3d 3h", "Over pace  limit Sun 01:20 at this rate", "0.5% an hour left". Coral past the tick only when over pace. Screens: pop-live. Do: Read the weekly. Evidence: fixtures/claude-overpace; spec 7 worked example; PaceTests. Wireframe: click.
3. works. 5h window, the same five lines, for plans that have it. Screens: pop-live. Do: Read the 5h window. Evidence: fixtures/claude-overpace; live-max tab0. Wireframe: click.
4. friction. Open sessions: project, model, context bar and "405.6k of 1M  41%"; hovering the figure shows list price, lines added and removed, effort. Screens: pop-session-tip. Do: Hover the figure. Evidence: The tooltip text is 66 characters plus padding (68 cells) in a 50 cell view, drawn from the left edge and clipped by the view, so it ends at "9 remo" and the effort is never seen: LineView.swift:203-213, ScreenBuilder.swift:106-107. Computed from the code, hover not possible in this run. Wireframe: click.
5. works. Tokens by model, project or session with the price chip and the subagent share; click the switch or press m, p, s. Screens: pop-projects, pop-sessions. Do: Press p, then s. Evidence: fixtures/claude-projects, claude-sessions; Controller.swift:539. Wireframe: click.
6. works. Week over week: four rows, the hit week marked with the time it hit. Screens: pop-live. Do: Read the rows. Evidence: fixtures/claude-overpace. Wireframe: click.
7. broken. With several sessions open the weekly figure jumps every few seconds between the values each session last saw: 28%, 12%, 28%, 18%, 11% within 30 s, in the bar, the item, the projection and the allowance. Screens: desk-flicker-a, desk-flicker-b, pop-flicker-a, pop-flicker-b. Do: Watch the item. Evidence: Real data folder, sampled 11:11:16 to 11:11:45: limits.json used 12, 28, 18, 11 as the newest session file changed; ten session files carried 9 to 28 for the same resets_at. FeedReader.swift:96-101 takes the newest file; idle sessions rewrite their cached figure every 5 s (refreshInterval, Hook.swift:68). Wireframe: click.
8. works. Esc closes, Tab and Shift Tab switch tabs, Command Q quits. Screens: pop-live. Do: Press Tab. Evidence: Controller.swift:529-541. Wireframe: click.

## 04 Nudges

1. friction. Nudges are on by default; permission is asked at launch. Screens: notif-permission. Do: Allow. Evidence: Controller.swift:124 (see 01.7). Wireframe: start.
2. works. The weekly passes 80% while a session feeds: "Weekly at 80%" with the countdown and the landing time, once per weekly window. Screens: notif-weekly. Do: Read the banner. Evidence: Controller.swift:413-419; PaceModel.nudgeBody, PaceTests. Notifications need the app bundle, so not posted by the debug binary (left out 3). Wireframe: click.
3. works. 15 minutes before the 5h reset: "5h window ends in 15 min" with the percentage, once per window. Screens: notif-five. Do: Read the banner. Evidence: Controller.swift:420-424. Wireframe: click.
4. broken. Ultra: the frozen 5h record can still pass that test once, and announce the end of a window the plan no longer has. Screens: notif-five-false. Do: Ignore it. Evidence: Controller.swift:420-424 reads l.windows["five_hour"], kept by FeedReader.swift:23-37; the real record resets_at is 31 Oct 00:10. Read from the code, not seen on screen. Wireframe: click.
5. friction. Notifications denied: the Nudge row says "Notifications are off for this app in System" and stops at the edge; it does not open System Settings. Screens: pop-settings-denied. Do: Find the setting yourself. Evidence: states/settings-nohook-denied; Grammar.swift:279; Notifier.swift:30. Wireframe: click.
6. works. No nudge comes from stale figures: an hour without a session and the nudges wait. Screens: pop-stale. Do: Nothing. Evidence: Controller.swift:412. Wireframe: click.

## 05 The 5 hour window removed for Ultra (30 Oct 2026)

1. broken. 30 Oct, evening: the feed stops sending five_hour for verified Ultra accounts. The app keeps the last figure (63% in this example) and draws it as live: countdown running, tick moving, "Over pace  limit 22:50 at this rate". Screens: pop-ultra-evening. Do: Believe it. Evidence: live-ultra-day1: after 50 s of feeds without five_hour, limits.json still held five_hour used 63 and the tab showed it with pace lines. FeedReader.swift:23-37 (apply only touches keys present); ScreenBuilder.swift:60-78 (asOf is shared, so it is never stale). Wireframe: start.
2. broken. Near the stored reset the same 63% reads "Ahead  66% by reset", "185% an hour left". Screens: pop-ultra-late. Do: Read nonsense. Evidence: states/ultra-late. Wireframe: click.
3. broken. If the 5h window was at 100% when the feed stopped, the panda shows - - eyes and VoiceOver says "5h limit reached" until the old reset. Screens: desk-five-limit. Do: Think you are blocked. Evidence: states/ultra-five-at-limit: label "... 5h limit reached"; ScreenBuilder.swift:292-299. Wireframe: click.
4. broken. Around the old reset a "5h window ends in 15 min" nudge can fire for it. Screens: notif-five-false. Do: Ignore it. Evidence: Controller.swift:420-424 (see 04.4). Wireframe: click.
5. broken. Today, 31 Oct: the 5h window is an empty bar with "Reset 00:10  no session since", under "Usage live" and a listed open session, and it stays that way for good. The smallest fix drops the window when a fresh feed comes without it. Screens: pop-ultra-today, pop-ultra-fixed. Do: Read a contradiction. Evidence: Real limits.json: five_hour used 1, resetsAt 31 Oct 00:10, asOf 11:11 today; all ten live session files carry seven_day only. live-ultra-today tab0 shows exactly this. ScreenBuilder.swift:62 (.absent is never reached once a record exists), :65-66 (resetPassed). Wireframe: click.
6. friction. A new Ultra user, whose feed never had five_hour, sees an empty 5h bar with "not in the last feed" for good. Screens: pop-ultra-new. Do: Wonder what it means. Evidence: states/ultra-new; ScreenBuilder.swift:62. Wireframe: click.
7. works. Max and Pro feeds still carry five_hour; their panel is unchanged. Screens: pop-live-max. Do: Nothing. Evidence: live-max tab0; states/max-both. Wireframe: click.

## 06 Weekly reset

1. works. Before the reset the countdown reads in hours and minutes. Screens: pop-week-near. Do: Plan the last hour. Evidence: PaceModel.countdown; PaceTests. Wireframe: start.
2. works. The reset passes with no session open: the weekly reads "Reset Sun 17:00  no session since", the item dims, the week row says "last seen 91%". Screens: pop-week-rolled. Do: Open Claude Code. Evidence: fixtures/claude-resetpassed; ScreenBuilder.swift:176-178. Wireframe: click.
3. friction. The reset passes while idle sessions feed: Claude Code drops the passed window, the app keeps it, and the weekly reads "no session since" under "Usage live" with sessions listed, until the next reply. Screens: pop-week-rolled-live. Do: Send a prompt. Evidence: states/weekly-rolled-live; Claude Code docs as quoted in spec 3 ("Claude Code drops a window once its resets_at time passes"); real weeks.json: the 25 Oct week was last updated 22 min after its reset, so the old record outlived it. Wireframe: click.
4. works. The next reply brings the new week: "1% used", "On pace", a new row in week over week. Screens: pop-week-new. Do: Read the new week. Evidence: states/weekly-new; Feed/Weeks.swift:22-32. Wireframe: click.
5. broken. Week over week keeps the last value seen per week; with several sessions that is whichever session wrote last, often an idle one with a lower figure. Screens: pop-flicker-b. Do: Trust the history. Evidence: Real weeks.json: current week lastUsed 12 while the account is at 28; Controller.swift:197-201 applies whatever limits holds. Wireframe: click.
6. works. At 100% the panda shows x x until the reset. Screens: desk-weekly-limit. Do: Wait for the reset. Evidence: fixtures/item-weekly-limit; ItemImage.swift:32-48. Wireframe: click.

## 07 Stale or missing feed

1. works. The last session closes: its row leaves after 60 s and the header says "Usage as of 13:05, last Claude Code session"; pace is still computed for an hour. Screens: pop-asof. Do: Read the time. Evidence: FeedTests openSessionsTiming; ScreenBuilder.swift:275-279. Wireframe: start.
2. works. After an hour: the stale form, dim bars, "as of 13:05", the note that limits are shared, the item at half strength. Screens: pop-stale, desk-stale. Do: Open Claude Code to refresh. Evidence: fixtures/claude-stale, item-stale. Wireframe: click.
3. friction. Use on the web or in the Claude app moves the limits, but the app sees it only when a Claude Code session feeds; the stale note says so. Screens: pop-stale. Do: Keep it in mind. Evidence: README.md, By the rules; spec 3. By design: no network. Wireframe: click.
4. works. An account without plan limits: "this account has no plan limits to show". Screens: pop-nolimits. Do: Nothing. Evidence: fixtures/claude-nolimits. Wireframe: click.
5. works. No transcripts folder: "No transcripts in ~/.claude/projects" in the token section; a read error shows its own message. Screens: pop-notranscripts. Do: Nothing. Evidence: states/claude-no-transcripts, claude-transcripts-denied. Wireframe: click.
6. works. The statusLine entry removed by hand: the app notices the settings.json change on the next tick and offers Install again. Screens: pop-nohook. Do: Install again or not. Evidence: Controller.swift:196; Hook.swift:75-81. Wireframe: click.

## 08 The Mac tab

1. works. Click Mac or press Tab: CPU, GPU, the memory grid with pressure and swap, battery, the busiest processes. Screens: pop-mac. Do: Read. Evidence: fixtures/mac; live-max tab1. Wireframe: start.
2. works. Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign. Screens: desk-warning, pop-mac-warning. Do: Open the Mac tab. Evidence: fixtures/mac-warning, item-warning; live runs on this Mac showed the dot and the sign. Wireframe: click.
3. works. Battery health unknown: "health n/a", never a dash. Screens: pop-mac-health. Do: Nothing. Evidence: fixtures/mac-health-na. Wireframe: click.
4. works. Mac figures in the bar appends " CPU 9%" to the item. Screens: desk-mac. Do: Tick it in Settings. Evidence: ScreenBuilder.swift:314. Wireframe: click.

## 09 Settings

1. works. Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, Quit. Screens: pop-settings. Do: Read the rows. Evidence: fixtures/settings; live-settings tab2. Wireframe: start.
2. works. Open at login: the box shows what macOS says; while macOS waits for approval a dim line opens Login Items. Screens: pop-settings-login, pop-settings-approval, sys-loginitems. Do: Tick it. Evidence: Controller.swift:283-304; spec 10, seen on the build Mac. Not clicked in this run (left out 2). Wireframe: click.
3. works. List price equivalent off: the price chip goes. Screens: pop-nochip. Do: Untick it. Evidence: ScreenBuilder.swift:136-140. Wireframe: click.
4. works. Quit and Command Q end the app; the item goes. Screens: desk-quit. Do: Click Quit. Evidence: Grammar.swift:291; Controller.swift:531. Wireframe: click.
5. friction. Nowhere in the app is the version: no About, no line in Settings. Screens: pop-settings. Do: Look for the version. Evidence: No read of CFBundleShortVersionString in Sources/. Wireframe: click.

## 10 Keep the Mac awake

1. works. Keep the Mac awake while Claude works: while a session's figures move, "awake  1 session working" and one power assertion. Screens: pop-settings-awake. Do: Tick it. Evidence: live-settings: pmset -g assertions listed "tokenpanda: a Claude Code session is open" for the throwaway run; Controller.swift:254-265. Wireframe: start.
2. works. Also while a session waits for you: idle sessions count too, "awake  1 session open". Screens: pop-settings-awake-open, term-pmset. Do: Tick the second row. Evidence: live-settings tab2 showed "awake  1 session open". Wireframe: click.
3. friction. A closed lid on battery still sleeps the Mac; the README says so, the row does not. Screens: pop-settings-awake. Do: Read the README. Evidence: README.md, What it shows. Wireframe: click.

## 11 Reopen sessions after a restart

1. works. Turn on Reopen sessions after a restart: the app keeps the open sessions in restore.json, readable only by you. Screens: pop-settings-restore. Do: Tick it. Evidence: live-settings: restore.json written with mode 0600, entries id, folder, lastSeen. Wireframe: start.
2. works. After a restart, one notification: "3 Claude Code sessions were open before the restart", with Reopen. Screens: notif-reopen. Do: Click Reopen. Evidence: Controller.swift:318-337; RestoreTests. Wireframe: click.
3. works. Reopen opens each session in Terminal with claude --resume, and --remote-control where it had it. Screens: term-reopen. Do: Work on. Evidence: pgrep on this Mac: nine tokenpanda-reopen .command scripts running under zsh -l; Restore.swift:82-88. Wireframe: click.
4. friction. With notifications off the offer never comes and the Reopen row does not say why. Screens: desk-reopen-denied. Do: Nothing happens. Evidence: Notifier.swift:53-54; Grammar.swift:279-285 (the note sits under the Nudge row only). Wireframe: click.
5. works. Turning it off deletes restore.json. Screens: pop-settings. Do: Untick it. Evidence: Controller.swift:468-471. Wireframe: click.

## 12 Update

1. friction. The app never checks for updates (no network); a new version is found on the releases page or with brew outdated. Screens: browser-release. Do: Look on GitHub. Evidence: spec 16; privacy 5. Wireframe: start.
2. works. brew upgrade --cask tokenpanda quits and replaces the app. Screens: term-brew-upgrade. Do: Run it. Evidence: Casks/tokenpanda.rb (uninstall quit). Wireframe: click.
3. friction. A new ad hoc build can bring back the Open Anyway steps, and the app has no version line to confirm what runs. Screens: term-brew-upgrade, gk-blocked. Do: Open Anyway again. Evidence: codesign adhoc; no version in Sources/. Not walked across two releases in this run (left out 1). Wireframe: click.
4. works. Settings, the hook, limits.json and weeks.json survive the update; Open at login keeps working. Screens: pop-live. Do: Nothing. Evidence: Application Support and preferences are outside the bundle; SMAppService.mainApp. Wireframe: click.

## 13 Uninstall

1. works. Settings, Remove the status line entry puts the previous statusLine back exactly, or removes the key. Screens: editor-restored. Do: Click it. Evidence: hookrun own-statusline: command, padding back as before; Hook.swift:141-161. Wireframe: start.
2. friction. If there was no settings.json before, an empty "{}" file stays. Screens: editor-empty. Do: Delete it by hand. Evidence: hookrun no-settings: settings.json after uninstall is {}. Wireframe: click.
3. works. Quit and move the app to the Bin. Screens: finder-bin. Do: Drag to the Bin. Evidence: privacy 9. Wireframe: click.
4. friction. Moved to the Bin without Remove first: the hook keeps running from Application Support and leaves one session file per session that nothing deletes. Screens: term-leftover. Do: Find the folder. Evidence: Hook.swift:59-67; FeedReader.swift:92-95 is the only deleter. Wireframe: click.
5. broken. brew uninstall --zap deletes the folder that holds hook.sh while settings.json still points at it: the Claude Code status line goes blank, including the status line the user had before. Screens: term-zap. Do: Repair settings.json by hand. Evidence: Casks/tokenpanda.rb:21-24 zap; HookScript chains PREV inside hook.sh (Hook.swift:25); the caveat asks to Remove first, nothing enforces it. Wireframe: click.
6. works. Delete Application Support and the preferences file by hand; nothing else was created. Screens: finder-bin. Do: Delete two paths. Evidence: privacy 9. Wireframe: click.

## 14 VoiceOver and the keyboard

1. works. VoiceOver on the item reads the state in words: "Weekly 28% used, ahead, resets sun 17:00". Screens: desk-ultra. Do: Listen. Evidence: live and states item labels; ScreenBuilder.swift:327-331. The weekday is lower case and abbreviated; the style guide says "Sunday". Wireframe: start.
2. works. Inside the popover VoiceOver reads each line as text, so the figures are heard. Screens: pop-live. Do: Read with VO keys. Evidence: LineView.swift:90-97. Wireframe: click.
3. broken. The Install button, the tabs, the section switch and every checkbox are static text to VoiceOver: no role, no state, no press. A VoiceOver user cannot set up the feed or change a setting. Screens: pop-voiceover. Do: Try to press Install. Evidence: LineView.swift:95 role staticText for every line; style guide 9 promises button, tab list and checkbox roles. Wireframe: click.
4. broken. From the keyboard only Tab, Esc, m, p, s and Command Q work; no row takes focus and Space does nothing, so settings need a pointer. Screens: pop-keyboard. Do: Try Space on a row. Evidence: Controller.swift:529-541; style guide 9 promises focus and Space. Wireframe: click.
5. friction. The key hints are #505050 on the glass, about 2.1 to 1. Screens: pop-keyboard. Do: Squint. Evidence: Tokens.swift:19; style guide 9 measures 2.0 to 2.3. Wireframe: click.
6. works. Reduce motion: the popover opens without animation. Screens: pop-live. Do: Nothing. Evidence: Controller.swift:98. Wireframe: click.

## Gaps, by user impact

Each with the smallest fix found and its size.

1. The 5h window shows a dead figure for Ultra accounts (steps 05.1 to 05.5, 04.4)
   Why it matters: Since 30 Oct every verified Ultra user sees a 5h figure that is not real: first a frozen percentage with live pace and possibly - - eyes and a nudge, then for good "Reset 00:10  no session since" under "Usage live". The panel contradicts itself on its main screen.
   Fix: Limits.apply (FeedReader.swift:23-38) drops every stored window whose key is missing from the feed it applies; apply only runs for a snapshot that carries rate_limits, so the first call of a session still changes nothing. Then limitsView (ScreenBuilder.swift:83) draws the fixed keys only while their record exists, with the empty weekly row kept. Max and Pro feeds carry five_hour and see no change. Two tests: a later feed without five_hour removes it; the first call without rate_limits keeps it.
   Size: about 6 lines and 2 tests.

2. The weekly figure jumps between sessions (steps 03.7, 06.5)
   Why it matters: With several Claude Code sessions open, which is the normal case for this user, the item and the bar change every few seconds between 9% and 28%, and the week over week history records whichever value was last. The one number the app exists for is unreliable.
   Fix: In FeedReader.scan (FeedReader.swift:89-106) merge the rate_limits of every snapshot read in the scan instead of taking the newest file: per key, the latest resets_at, and for that reset the highest used_percentage (usage inside a window never goes down). Keep limits.asOf at the newest write. One test with two sessions writing 12 and 28.
   Size: about 12 lines and 1 test.

3. VoiceOver and the keyboard cannot use any control (steps 14.3, 14.4)
   Why it matters: Install, the tabs, the section switch and every setting are drawn text with no role or action, and nothing takes keyboard focus. A VoiceOver or keyboard user cannot set up the feed at all. The style guide already specifies the roles.
   Fix: In LineView.rebuildHits give lines with an action an element of role button or checkbox (with its value) and an accessibilityPerformPress that calls onAction; make those elements the key view loop and draw the focus ring the style guide names; Space presses the focused one.
   Size: medium, LineView.swift and Controller.handleKey.

4. Install from the Claude tab fails silently (steps 02.7)
   Why it matters: A settings.json the JSON reader refuses is common after a hand edit. The click does nothing visible where it was made, and the Settings error is cut before its reason.
   Fix: Pass hookError into LimitsView.noHook and draw it under the button, wrapped over two lines instead of cut (Grammar.swift:100-110, ScreenBuilder.swift:91).
   Size: small.

5. Lines run past the popover edge (steps 02.8, 04.5)
   Why it matters: "one statusLine entry in ~/.claude/settings.json" and "Notifications are off for this app in System Settings" are cut mid word; the second is the only hint about why nudges never come.
   Fix: Shorten to fit 42 cells at the 5 cell indent ("one entry in ~/.claude/settings.json", "Notifications are off in System Settings") and make the notification note open System Settings, Notifications on a click.
   Size: two strings and one action.

6. After a weekly reset the weekly reads "no session since" while sessions are open (steps 06.3)
   Why it matters: For the minutes between the reset and the next reply the main figure says no session ran, under "Usage live".
   Fix: The same drop as gap 1 covers it: when the feed comes without seven_day the stored one goes, and the weekly shows its empty row until the new week arrives. Better copy for that empty row: "new week starts with the next reply".
   Size: covered by gap 1, plus one string.

7. brew uninstall --zap leaves Claude Code pointing at a deleted script (steps 13.5, 13.4)
   Why it matters: The user's own status line, chained inside the hook, disappears with the zap; without Remove first, session files pile up for ever.
   Fix: Make the cask zap safe: an uninstall script stanza that runs the app's own remove (a release build flag such as --remove-status-line that calls Hook.uninstall) before trashing. In the app, nothing else is needed.
   Size: small, a flag in main.swift and the cask.

8. The first call reads "open Claude Code once" while sessions are open (steps 02.5)
   Why it matters: Right after setup, the user does what the screen says and the screen keeps saying it until the first reply.
   Fix: When sessions are open and none has replied yet, draw "waiting for the first reply" in both windows (ScreenBuilder.limitsView has the facts).
   Size: one condition, one string.

9. The notification prompt comes at launch, out of context (steps 01.7, 04.1)
   Why it matters: It is the first thing a new user sees, before the popover explains anything.
   Fix: Ask when the user first opens the popover after the feed works, or on the first nudge that would fire; keep asking at once when the user ticks the row.
   Size: small, Controller.swift:124.

10. No version anywhere in the app (steps 09.5, 12.3)
   Why it matters: A user cannot tell which build runs after an update or for a bug report.
   Fix: Add the version to the privacy line in Settings, "tokenpanda 0.1.7  no network calls", from CFBundleShortVersionString.
   Size: one line.

11. Smaller ones (steps 03.4, 07.3, 10.3, 11.4, 13.2, 14.1, 14.5)
   Why it matters: The session tooltip is cut after "9 remo"; use elsewhere is invisible until a session runs; the keep awake row does not say a closed lid on battery still sleeps; the Reopen row does not say notifications are off; an empty settings.json stays after Remove; the spoken weekday is "sun"; the key hints fail contrast.
   Fix: Wrap the tooltip over two lines or drop the list price from it; keep the README line for use elsewhere; add "not with the lid closed on battery" under keep awake; show the notifications note under Reopen too; delete settings.json on Remove when the install created it; use the full weekday in labels; lift quiet to #8a8a8a or drop the hints.
   Size: small each.

## Apple standards (P-APPLE)

1. Lint: python3 -I ~/Developer/apple-native/skills/apple-native/scripts/lint.py on the repository: 33 files, 0 errors, 0 warnings. It checks SwiftUI and Apple API usage; this app is AppKit drawn by hand, so most of what follows is outside its reach.
2. HIG by eye on the screenshots: a menu bar extra with a template image that follows the light and dark menu bar, a transient popover anchored to it, Esc and Command Q, no Dock icon. The popover is a terminal grammar on purpose (SF Mono 12, block bars), consistent and calm; it does not use system controls, which is where the accessibility gaps come from. Text is cut at the edge in two places (gap 5).
3. Accessibility: the item has a full spoken label. Inside the popover every line is static text: no button, tab or checkbox roles, no press action, no keyboard focus (gap 3). The style guide section 9 already specifies the right roles, so the code is behind its own spec. Contrast: text 13 to 1, dim 6 to 1, coral 5.5 to 1, key hints 2.1 to 1 (fails).
4. Reduce motion: honoured (no popover animation). Reduce transparency and Increase contrast: the glass is an NSVisualEffectView, which the system adapts; the tint on top stays at 82 percent.
5. Dynamic Type: macOS apps have no Dynamic Type; the popover is fixed at SF Mono 12 and ignores the macOS text size setting, while the style guide says text size follows the system monospace font. Friction, not a HIG violation.
6. Notifications: asked at launch, not in context (gap 9). Permission denial is handled with a note, cut at the edge.

## Left out or read from the code

1. Gatekeeper on a clean account and across two releases: not walked; this Mac runs the local build. The steps follow the README and spec 17; spctl confirms the ad hoc build is rejected.
2. Clicks in the running app: this session has no Accessibility or Screen Recording permission, so the popover could not be clicked or captured from the screen. Every screen state was rendered by the app itself (--snapshot, --live-snapshot and the ScreenBuilder harness), and the click paths were read from LineView and Controller. Open at login was not clicked.
3. Notifications: the debug binary is not an app bundle, so the notifier is unavailable (it says so in Settings); the banner texts come from Controller.swift. The running 0.1.7 bundle was left alone.
4. The user's real ~/.claude was never written. Hook install and remove ran on throwaway folders; the live runs used CFFIXED_USER_HOME on throwaway homes. The real data folder of the running app was only read.
5. Light menu bar, a desktop Mac without a battery, an Intel Mac: not available in this run.
