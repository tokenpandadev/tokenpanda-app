# Flow test of tokenpanda as built (31.10.2026)

Product: main at 4ca4160, release 0.1.7, the running app on this Mac is the same build. No app code was changed for this test.

Method: the product read first (README, CHANGELOG, docs/spec.html, styleguide.html, privacy.html, every file in Sources/ and Tests/, the scripts, the cask), then the flows written as numbered steps (flows/), then every step checked twice:

1. In the real app. swift build and the 97 tests pass with the Command Line Tools (DEVELOPER_DIR, the Xcode licence is not accepted on this Mac). The debug binary ran against throwaway homes (CFFIXED_USER_HOME) with crafted status line feeds, rendering its own tabs with --live-snapshot (live-<name>); --snapshot rendered the fixtures (fixtures/<name>); a harness linked against the debug objects rendered crafted inputs through ScreenBuilder, Grammar and SnapshotWriter (states/<name>) and ran the real Hook install, hook script and uninstall on throwaway folders (hookrun). The real data folder of the running 0.1.7 was read, never written. Screenshots were looked at one by one and are not kept in the repository.
2. In the wireframes: every screen of the step exists, and the step can be reached from the step before by a click or a key, or by a dashed target for another outcome or another start (press h, or walk mode, shows them). "click" below means reachable that way, "next" means the walk moves on with Next, "start" is the first step of a flow.

## Counts

1. Flows: 14. Steps: 105.
2. In the real app: 86 work, 6 friction, 0 broken.
3. In the wireframes: 105 of 105 steps drawn; 73 reached by a click or key from the step before, 14 flow starts, 18 reached with Next.
4. Screens: 91, a 1280 by 800 desktop with the menu bar, the popover at its real 380 point width and 16 point lines.

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

1. works. The releases page offers the zip of each version and its .sha256; the README says it runs on a Mac with Apple silicon (M1 or later) on macOS 14 or later. Screens: browser-release. Do: Download both. Evidence: README.md, Install (0.1.15); flow-test-0.1.13 01.1. Wireframe: start.
2. works. In Terminal, shasum -a 256 -c checks the zip and prints OK; unzip and move tokenpanda.app to Applications. Screens: term-shasum. Do: Run the two lines. Evidence: README.md, Install; flow-test-0.1.13 01.2. Wireframe: click.
3. works. With Homebrew instead: brew install --cask tokenpandadev/tap/tokenpanda, with no trust step; the cask declares Apple silicon only, so an Intel Mac is refused, and the caveats say Open Anyway and explain the zap. Screens: term-brew. Do: Read the caveats. Evidence: Casks/tokenpanda.rb: depends_on arch: :arm64 (0.1.14), caveats; README.md, Install. Wireframe: click.
4. friction. Double click in Applications: macOS refuses the ad hoc build, "Apple could not verify tokenpanda is free of malware". Screens: finder-apps, gk-blocked. Do: Click Done. Evidence: codesign Signature=adhoc; spctl rejected (flow-test-0.1.13 01.4). By design until Developer ID signing (spec 17, path two). Wireframe: click.
5. by hand. System Settings, Privacy and Security, scroll to the bottom, Open Anyway. Screens: gk-settings. Do: Find the button. Evidence: README.md, Install; flow-test-0.1.13 01.5. Wireframe: click.
6. by hand. The warning comes back once; Open Anyway starts the app. Screens: gk-confirm. Do: Click Open Anyway. Evidence: README.md, Install. Wireframe: click.
7. works. No notification prompt at launch: the app asks when the first nudge is due, or when Nudge or Reopen sessions is ticked. Screens: desk-nofeed. Do: Nothing. Evidence: Notifier.swift, refreshState and authorize; Controller.swift, applicationDidFinishLaunching. Wireframe: click.
8. works. The menu bar shows the panda alone at half strength: no figures yet. No window, no Dock icon. Screens: desk-nofeed. Do: Click the panda. Evidence: ScreenBuilder.itemFigures; LSUIElement in scripts/build-app.sh. Wireframe: click.
9. works. If the icon is not on screen five seconds after the first launch, one window: "tokenpanda is running". From macOS 26 the icon "may be switched off in System Settings, Menu Bar, hidden behind the notch when the menu bar is full, or kept out of view by an app that hides menu bar icons, such as Bartender or Ice", with "Open Menu Bar Settings" and "OK"; before macOS 26 the menu bar is "most likely" full, quitting another menu bar app makes room, and a menu bar manager can also keep the icon out of view, with "OK" only. The notch is named only on a Mac with one: with no notch the text says "left out when the menu bar is full", and when it is not known (a connected screen has a notch, the item's screen is not known) both causes are named. While the screen is locked, the session is switched away or the display sleeps, it waits and asks again. It shows once. Screens: desk-hidden, dlg-hidden-26, dlg-hidden-26-nonotch, dlg-hidden-26-unknown, dlg-hidden-15, dlg-hidden-15-nonotch, dlg-hidden-15-unknown. Do: Click Open Menu Bar Settings. Evidence: Grammar.hiddenIconHint and Grammar.notch (0.1.15: the notch named only on a Mac with one, a menu bar manager named in every text; texts approved 2026-11-04) and Controller.checkItemShows (0.1.14: the switch offered only from macOS 26, no verdict while locked, away or asleep); tests theHiddenIconHintOffersTheSwitchOnlyWhereThereIsOne, theNotchFollowsTheScreenThatHoldsTheItem. The real macOS 26 switch and the notch were not reproduced. Wireframe: click.
10. by hand. Switching the item on in System Settings, Menu Bar, is the user's click. Screens: sys-menubar. Do: Switch tokenpanda on. Evidence: testing.html, section 5. Wireframe: click.

## 02 Set up the feed

1. works. The Claude tab says what is needed: "needs Claude Code's status line feed", "one statusLine entry in ~/.claude/settings.json", "chained if one exists", and one button, Install the status line entry. Screens: pop-nohook. Do: Read, click Install. Evidence: Grammar.limits .noHook; flow-test-0.1.13 02.1. Wireframe: start.
2. works. With a status line of your own it says "your current status line is kept and chained". Screens: pop-nohook-chained. Do: Click Install. Evidence: flow-test-0.1.13 02.2: the hook printed the user's own output. Wireframe: click.
3. works. Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and a refreshInterval of 5 or less and is chained. Screens: editor-after. Do: Nothing to do. Evidence: Hook.install; flow-test-0.1.13 02.3. Wireframe: click.
4. works. The windows then read "no session yet  open Claude Code once". Screens: pop-nosession. Do: Start Claude Code. Evidence: Grammar.limits .noSession; flow-test-0.1.13 02.4. Wireframe: click.
5. works. During the first call both windows and the session say "waiting for the first reply". Screens: term-claude, pop-firstcall. Do: Send a first prompt. Evidence: ScreenBuilder.limitsView .firstReply; flow-test-0.1.13 02.5. Wireframe: click.
6. works. After the first reply: "Live from Claude Code", the windows with pace, each session with its bar. Screens: pop-live. Do: Read the figures. Evidence: flow-test-0.1.13 02.6. Wireframe: click.
7. works. A settings.json that is not valid JSON, or valid JSON that is not an object: Install says why under the button, wrapped, on the Claude tab and in Settings. Screens: editor-broken, pop-install-failed, pop-settings-error. Do: Fix the file, click Install again. Evidence: Hook.unreadable; flow-test-0.1.13 02.7 and 02.12. Wireframe: click.
8. works. A settings.json that is a link into a folder that does not exist: Install refuses, says why under the button ("it is a link into ~/dotfiles/sub, a folder that does not exist"), and writes nothing: no folder, no script, no backup. Screens: pop-install-dangling, pop-settings-dangling. Do: Make the folder, or fix the link, and click Install again. Evidence: Hook.writableTarget, SettingsFile.reason (0.1.15, audit F-6; text approved 2026-11-04); test in HardeningTests (a dangling ~/.claude link, the reason string). Wireframe: next.
9. works. Both places name the button "Install the status line entry", and no line runs past the panel edge. Screens: pop-settings-nohook. Do: Click it. Evidence: Grammar.hookRow and dimLines; flow-test-0.1.13 02.8. Wireframe: click.
10. works. Several settings folders each get their own script and backup; a folder with only transcripts is left alone; a lost script offers Install again. Screens: pop-settings-folders. Do: Click Install. Evidence: HookSet; flow-test-0.1.13 02.9. Wireframe: next.
11. works. A settings.json that is a link stays a link, and the file it names keeps its mode; a created settings.json is 0600. Screens: editor-after. Do: Nothing. Evidence: SettingsFile; flow-test-0.1.13 02.10. Wireframe: click.
12. works. disableAllHooks on: "disableAllHooks is on in settings.json  so Claude Code runs no status line". Screens: pop-hooks-disabled. Do: Turn it off, or not. Evidence: Grammar.limits .hooksDisabled; flow-test-0.1.13 02.11. Wireframe: next.
13. works. An entry installed by an earlier version gets the current script at the next launch, its chained command kept. Screens: editor-after. Do: Nothing. Evidence: HookSet.refreshScripts; flow-test-0.1.13 02.13. Wireframe: next.

## 03 Read the panel

1. works. The item shows the panda and the weekly percentage; semibold when over pace. Screens: desk. Do: Glance. Evidence: ItemImage; flow-test-0.1.13 03.1. Wireframe: start.
2. works. Weekly: bar with the notch at the elapsed share, the reset and countdown, the status and projection, the allowance. Coral past the notch only when over pace. Screens: pop-live. Do: Read the weekly. Evidence: Grammar.windowSection; PaceTests; flow-test-0.1.13 03.2. Wireframe: click.
3. works. 5h window, the same five lines, for plans that have it. Screens: pop-live. Do: Read the 5h window. Evidence: flow-test-0.1.13 03.3. Wireframe: click.
4. works. Open sessions by name (set with -n or /rename), by folder when unnamed, each with its model, its 24 cell context bar and "405.6k of 1M  41%"; the figure's tooltip breaks over two lines inside the panel. Screens: pop-session-tip. Do: Hover the figure. Evidence: ScreenBuilder.sessionViews, Grammar.sessionRows, LineView.tipLines; flow-test-0.1.13 03.4 and 03.12. Hover itself is by hand. Wireframe: click.
5. works. Tokens by model, project or session with the price chip and the subagent share; click the switch or press m, p, s. Screens: pop-projects, pop-sessions. Do: Press p, then s. Evidence: flow-test-0.1.13 03.5. Wireframe: click.
6. works. Week over week: up to four rows, the current week "so far", a hit week marked with the time it hit. Screens: pop-live. Do: Read the rows. Evidence: ScreenBuilder.weekViews; flow-test-0.1.13 03.6. Wireframe: click.
7. works. With several sessions open the weekly figure holds still: the highest figure at the latest reset, across every session file. Screens: pop-live. Do: Watch the item. Evidence: Limits.merge and apply (0.1.8); WindowsTests; flow-test-0.1.13 03.7: 28 in all 26 samples. Wireframe: click.
8. works. Esc closes, Tab and Shift Tab switch tabs, Command Q quits. Screens: pop-live. Do: Press Tab. Evidence: Controller.handleKey. Wireframe: click.
9. works. The header says where the figures come from: "Live from Claude Code", "As of 22:02, last Claude Code session", or "Waiting for a Claude Code session". Screens: pop-live, pop-asof. Do: Read the header. Evidence: ScreenBuilder.headerLine; flow-test-0.1.13 03.9 to 03.11. Wireframe: click.
10. works. After midnight the token rows stay: the first pass of a new day sums every record, not only new ones. Screens: pop-live. Do: Open the panel after midnight. Evidence: TokenRefresh.needsAllRecords in Controller.refreshTranscripts (0.1.14); test theTokenRowsSurviveMidnightWithoutANewTranscriptLine. Until 0.1.13 the rows read "nothing in the last 7 days" until the next reply (flow-test-0.1.13 03.13). Wireframe: click.
11. works. On a short or scaled screen the panel stops 60 points short of the screen's visible height and scrolls with an overlay scroller and no rubber band, from the top on every open and tab click; the keyboard focus scrolls into view, and a tooltip with no room above opens below its line. Screens: pop-small. Do: Scroll, or press Down. Evidence: PanelSize and Controller.fitPanel (0.1.14); test thePanelIsNeverTallerThanTheScreen. The real scroll on a small screen is by hand (testing.html, section 5). Wireframe: click.

## 04 Nudges

1. works. Permission is asked when the first nudge is due or Nudge is ticked, not at launch. Screens: pop-settings. Do: Allow. Evidence: Notifier.postAsking and requestIfNeeded. Wireframe: start.
2. by hand. The weekly passes 80% while a session feeds: "Weekly at 80%" (the percentage when it fires) with the countdown and the landing time, once per weekly window. Screens: notif-weekly. Do: Read the banner. Evidence: Controller.checkNudges; PaceModel.nudgeBody. Not posted by the debug binary (flow-test-0.1.13 04.2). Wireframe: next.
3. by hand. 15 minutes before the 5h reset: "5h window ends in 15 min" with the percentage, once per window. Screens: notif-five. Do: Read the banner. Evidence: Controller.checkNudges. Wireframe: click.
4. works. No 5h nudge from a window the plan no longer has. Screens: pop-ultra-today. Do: Nothing. Evidence: Limits.active; flow-test-0.1.13 04.4. Wireframe: click.
5. works. Notifications denied: "Notifications are off in System Settings" under Nudge, and under Reopen while it is on, in the accent, a link the keyboard and VoiceOver reach, said once. Screens: pop-settings-denied. Do: Click it. Evidence: Grammar.cbRow (0.1.14: accent, not also the checkbox's help); AccessTests; flow-test-0.1.13 04.5 and 04.7. Wireframe: next.
6. by hand. The click opens System Settings, Notifications, at tokenpanda. Screens: sys-notifications. Do: Turn notifications on. Evidence: Controller.perform .openNotificationSettings. Wireframe: click.
7. works. Notifications turned on in System Settings count at once: the note goes at the next open of the popover, and the next nudge is posted, no restart. Screens: pop-settings. Do: Open the popover. Evidence: Notifier.refreshState on every popover open and authorize before each post, from any state (0.1.14). Until 0.1.13 a denial held until a restart. No test covers the Notifier; a banner on screen is by hand. Wireframe: click.
8. works. No nudge comes from stale figures: an hour without a session and the nudges wait. Screens: pop-stale. Do: Nothing. Evidence: Controller.checkNudges. Wireframe: next.

## 05 The 5 hour window removed for Ultra (30 Oct 2026)

1. works. The feed stops carrying five_hour while the stored 5h window still runs: the last percent dim, "not in the last feed", no countdown or pace. Screens: pop-ultra-evening. Do: Nothing. Evidence: Limits.apply retired; ScreenBuilder .quiet; flow-test-0.1.13 05.1 and 05.2. Wireframe: start.
2. works. A retired 5h window at 100% gives normal eyes and no "5h limit reached". Screens: desk-ultra. Do: Nothing. Evidence: ScreenBuilder.eyes uses Limits.active; flow-test-0.1.13 05.3. Wireframe: click.
3. works. No false "5h window ends in 15 min". Screens: pop-ultra-evening. Do: Nothing. Evidence: See 04.4. Wireframe: click.
4. works. After the old reset the 5h row goes for good: a reply without five_hour hides it. Screens: pop-ultra-today. Do: Nothing. Evidence: Limits.apply hidden; flow-test-0.1.13 05.5. Wireframe: click.
5. works. A new Ultra user sees the weekly alone after the first reply. Screens: pop-ultra-today. Do: Nothing. Evidence: flow-test-0.1.13 05.6. Wireframe: click.
6. works. Max and Pro keep both windows. Screens: pop-live-max. Do: Nothing. Evidence: flow-test-0.1.13 05.7. Wireframe: click.
7. friction. Before the first reply a new Ultra user still sees a "5h window" row, and the Install text is titled "Weekly and 5h window". Screens: pop-nosession, pop-firstcall. Do: Wait for the first reply. Evidence: Grammar.limits .noSession, .firstReply, .noHook; still open in 0.1.14 (flow-test-0.1.13 05.8). Wireframe: next.
8. works. On Ultra the nudge row reads "Nudge at 80%". Screens: pop-settings-ultra. Do: Nothing. Evidence: ScreenBuilder.screen, fiveHour. Wireframe: next.

## 06 Weekly reset

1. works. Before the reset the countdown reads in days and hours, then hours and minutes. Screens: pop-week-near. Do: Plan the last hour. Evidence: PaceModel.countdown. Wireframe: start.
2. works. The reset passes with no session: "Reset Sun 17:00  no session since", the item dims; the old week keeps its figure and the new week says "no reply yet". Screens: pop-week-rolled. Do: Open Claude Code. Evidence: ScreenBuilder.windowView .resetPassed, weekViews; flow-test-0.1.13 06.2 and 06.7. Wireframe: click.
3. works. The reset passes while idle sessions feed: "new window on the next reply". Screens: pop-week-rolled-live. Do: Send a prompt. Evidence: ScreenBuilder.windowView .nextReply; flow-test-0.1.13 06.3. Wireframe: click.
4. works. The next reply brings the new week: a low figure, "On pace" or "Ahead", a new row in week over week. Screens: pop-week-new. Do: Read the new week. Evidence: FeedTests; Weeks.swift. Wireframe: click.
5. works. Early in a window the pace row does not guess: "On pace  too early to project" until 5% of the window has passed (8 h 24 min of a week, 15 min of a 5h window). The new week above shows it. Screens: pop-pace-early, pop-week-new. Do: Read the pace row in the first hours. Evidence: PaceModel.reading, earliestProjection (0.1.15, flow test 06.8; texts approved 2026-11-04); test theFirstMinutesOfAWindowProjectOnlyOverPace. Wireframe: next.
6. works. On pace or Ahead the projection reads "N% by reset at this rate", N at most 100; Over pace keeps "limit ... at this rate" in every phase, also ten minutes in. Screens: pop-pace-reset, pop-pace-over-early. Do: Read the pace row. Evidence: PaceModel.reading (0.1.15; texts approved 2026-11-04); test aLimitIsNamedOnlyOverPace. Wireframe: next.
7. works. Week over week keeps the highest value seen per week. Screens: pop-live. Do: Trust the history. Evidence: WindowsTests weekOverWeekKeepsTheHighestValuePerWeek; flow-test-0.1.13 06.5. Wireframe: click.
8. works. At 100% the panda shows x x until the reset, and the weekly window reads "limit reached, resets Sun 18:00" in place of the pace lines. Screens: desk-weekly-limit, pop-live-limit. Do: Wait for the reset. Evidence: ItemImage; Grammar.windowSection (spec 24.33); flow-test-0.1.13 06.6. Wireframe: next.

## 07 Stale or missing feed

1. works. The last session closes: its row leaves after 60 s and the header says "As of 13:05, last Claude Code session"; pace is still computed for an hour. Screens: pop-asof. Do: Read the time. Evidence: FeedTests openSessionsTiming; flow-test-0.1.13 07.1. Wireframe: start.
2. works. After an hour: the stale form, dim bars, "as of 13:05", the note that limits are shared with the Claude app and other Macs, the item at half strength. Screens: pop-stale, desk-stale. Do: Open Claude Code to refresh. Evidence: flow-test-0.1.13 07.2. Wireframe: click.
3. friction. Use on the web, in the Claude app or on another Mac shows only with the next Claude Code reply on this Mac; the stale note says so. Screens: pop-stale. Do: Keep it in mind. Evidence: By design: no network (README.md; flow-test-0.1.13 07.3). Wireframe: click.
4. works. Sessions on an API key, Bedrock or Vertex: "these sessions carry no plan limits". Screens: pop-nolimits. Do: Nothing. Evidence: Limits.planless; flow-test-0.1.13 07.4. Wireframe: click.
5. works. No transcripts folder: "No transcripts in ~/.claude/projects" in the token section; a read error shows its own message. Screens: pop-notranscripts. Do: Nothing. Evidence: ScreenBuilder.tokensView. Wireframe: click.
6. works. The statusLine entry removed by hand: the app notices the settings.json change on the next tick and offers Install again. Screens: pop-nohook. Do: Install again or not. Evidence: Controller.refreshFeed, settingsModified. Wireframe: click.

## 08 The Mac tab

1. works. Click Mac or press Tab: CPU, GPU, the memory grid with pressure and swap, battery, the busiest processes. Screens: pop-mac. Do: Read. Evidence: flow-test-0.1.13 08.1. Wireframe: start.
2. works. The free cells of the memory grid are #949494, 3 to 1 even over a white desktop. Screens: pop-mac. Do: Read the grid over a bright wallpaper. Evidence: Tokens.dimmer (0.1.14, was #888888, 2.7 to 1); AccessTests. Wireframe: click.
3. works. Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign. Screens: desk-warning, pop-mac-warning. Do: Open the Mac tab. Evidence: flow-test-0.1.13 08.2. Wireframe: click.
4. works. Battery health unknown: "health n/a", never a dash. Screens: pop-mac-health. Do: Nothing. Evidence: flow-test-0.1.13 08.3. Wireframe: click.
5. works. Mac figures in the bar appends " CPU 9%" to the item. Screens: desk-mac. Do: Tick it in Settings. Evidence: flow-test-0.1.13 08.4. Wireframe: click.
6. works. Claude Code's processes show as "Claude Code". Screens: pop-mac. Do: Nothing. Evidence: flow-test-0.1.13 08.5. Wireframe: next.

## 09 Settings

1. works. Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, the version line, Quit. Screens: pop-settings. Do: Read the rows. Evidence: Grammar.settingsTab; flow-test-0.1.13 09.1. Wireframe: start.
2. by hand. Open at login: the box shows what macOS says; while macOS waits for approval a dim line opens Login Items. Screens: pop-settings-login, pop-settings-approval, sys-loginitems. Do: Tick it. Evidence: Controller.clickLogin; not clicked in the flow tests. Wireframe: click.
3. works. List price equivalent off: the price chip goes. Screens: pop-nochip. Do: Untick it. Evidence: ScreenBuilder.tokensView. Wireframe: click.
4. works. Quit and Command Q end the app; the item goes. Screens: desk-quit. Do: Click Quit. Evidence: Controller.handleKey; flow-test-0.1.13 09.4. Wireframe: click.
5. works. The version line says what runs: "tokenpanda 0.1.15". Screens: pop-settings. Do: Read it. Evidence: ScreenBuilder.screen, CFBundleShortVersionString. Wireframe: click.
6. works. Light mode: the same layout on a light glass, switching with the Mac's appearance. Screens: pop-settings. Do: Change the appearance. Evidence: Ground in Controller.swift; Tokens.light; flow-test-0.1.13 09.6. The live switch is by hand. Wireframe: click.
7. works. A tall Settings tab on a short screen scrolls inside the panel, so Quit stays reachable. Screens: pop-small-settings. Do: Scroll to Quit. Evidence: PanelSize (0.1.14); see 03.11. Wireframe: click.

## 10 Keep the Mac awake

1. works. Keep the Mac awake while Claude works: while a session's figures move, "awake  1 session working" and one power assertion. Screens: pop-settings-awake. Do: Tick it. Evidence: Controller.updateAwake; FeedTests keep awake. Wireframe: start.
2. works. Also while a session waits for you: idle sessions count too, "awake  1 session open". Screens: pop-settings-awake-open, term-pmset. Do: Tick the second row. Evidence: flow-test-0.1.13 10.2. Wireframe: click.
3. works. The row says "a closed lid on battery still sleeps". Screens: pop-settings-awake. Do: Read it. Evidence: Grammar.settingsTab; flow-test-0.1.13 10.3. Wireframe: click.

## 11 Reopen sessions after a restart

1. works. Turn on Reopen sessions after a restart: the app keeps the open sessions with their names and start options in restore.json, readable only by you. Screens: pop-settings-restore. Do: Tick it. Evidence: flow-test-0.1.13 11.1. Wireframe: start.
2. by hand. After a restart, one notification names the sessions that were open, with Reopen. Screens: notif-reopen. Do: Click Reopen. Evidence: Controller.offerRestore; flow-test-0.1.13 11.2 and 11.7. Wireframe: click.
3. by hand. Reopen opens each session in Terminal as it was started, with --remote-control where it had it, and the fallbacks. Screens: term-reopen. Do: Work on. Evidence: Reopen.script; flow-test-0.1.13 11.3. Wireframe: click.
4. works. With notifications off the Reopen row says so, as the same link as under Nudge; turned on again, the offer and the end notices come without a restart. Screens: pop-settings-denied. Do: Click the link. Evidence: Grammar.settingsTab; Notifier.refreshState and authorize (0.1.14). Wireframe: next.
5. works. Turning it off deletes restore.json. Screens: pop-settings. Do: Untick it. Evidence: Controller.perform .toggle. Wireframe: click.
6. works. A print run is never reopened; a start prompt is not sent again. Screens: term-reopen. Do: Nothing. Evidence: LaunchOptions; flow-test-0.1.13 11.6. Wireframe: next.
7. friction. The end notice also comes after a deliberate /exit in a window you keep. Screens: notif-ended. Do: Dismiss it. Evidence: Controller.watchEnds has no working check; still open in 0.1.14 (flow-test-0.1.13 11.8). Wireframe: click.

## 12 Update

1. friction. The app never checks for updates (no network); a new version is found on the releases page or with brew outdated. Screens: browser-release. Do: Look on GitHub. Evidence: By design (spec 16). Wireframe: start.
2. by hand. brew upgrade --cask tokenpandadev/tap/tokenpanda quits and replaces the app. Screens: term-brew-upgrade. Do: Run it. Evidence: Casks/tokenpanda.rb, uninstall quit. Wireframe: click.
3. by hand. A new ad hoc build can bring back the Open Anyway steps; the version line in Settings confirms what runs. Screens: term-brew-upgrade, gk-blocked. Do: Open Anyway again. Evidence: codesign adhoc; flow-test-0.1.13 12.3. Wireframe: click.
4. works. Settings, the entry and the records survive the update, and the installed script is brought up to date at launch. Screens: pop-live. Do: Nothing. Evidence: flow-test-0.1.13 12.4. Wireframe: click.

## 13 Uninstall

1. works. Settings, Remove the status line entry puts the previous statusLine back exactly, or removes the key. Screens: editor-restored. Do: Click it. Evidence: Hook.uninstall; flow-test-0.1.13 13.1. Wireframe: start.
2. works. A settings.json Install created is deleted on Remove; when it is a link whose file Install created, the file goes and the link stays. Screens: term-settings-gone. Do: Nothing. Evidence: Hook.uninstall resolves the link (0.1.14); test aDanglingLinkStaysALinkAfterRemoveInTheAppAndInTheScript. Until 0.1.13 the link went and the entry stayed in the file. Wireframe: click.
3. works. Quit and move the app to the Bin. Screens: finder-bin. Do: Drag to the Bin. Evidence: privacy 9. Wireframe: click.
4. works. Moved to the Bin without Remove: the script deletes its folder's session files that stopped changing over a minute ago, so the leftover stays small. Screens: term-leftover. Do: Nothing. Evidence: hook/statusline.sh cleanup line (0.1.13); flow-test-0.1.13 13.4 and 13.7. Wireframe: click.
5. works. brew uninstall --zap runs remove.sh, which puts the previous status line back, the same way through a link (readlink -f), before the data folder goes. Screens: term-zap. Do: Run it. Evidence: HookSet remove script (0.1.14 for the link); flow-test-0.1.13 13.5. brew itself is by hand. Wireframe: click.
6. works. Delete Application Support and the preferences file by hand; nothing else was created. Screens: finder-bin. Do: Delete two paths. Evidence: The cask's zap trash list. Wireframe: click.

## 14 VoiceOver and the keyboard

1. by hand. VoiceOver on the item says "tokenpanda, Weekly 28% used, ahead, resets Sunday 17:00". Screens: desk-ultra. Do: Listen. Evidence: ScreenBuilder.itemFigures; Controller.render. Wireframe: start.
2. works. The privacy sentence is one element, and each window, week and Mac figure is one sentence. Screens: pop-voiceover. Do: Read with VO keys. Evidence: AccessTests; flow-test-0.1.13 14.2. Wireframe: next.
3. by hand. Tabs are radio buttons, settings checkboxes with values, Install, Remove, Quit and the notifications link buttons with press. Screens: pop-voiceover. Do: Press Install. Evidence: LineView accessibility elements; AccessTests. Not heard in the flow tests. Wireframe: click.
4. works. The keyboard reaches every control: Down and Up, Left and Right, Space or Return; a thin accent ring shows where. Screens: pop-keyboard. Do: Press Down, then Space. Evidence: LineView.moveFocus; flow-test-0.1.13 14.4. Wireframe: click.
5. works. The key hints read clearly over white, at 4.5 to 1 or more. Screens: pop-keyboard. Do: Read them. Evidence: Tokens.quiet; AccessTests. Wireframe: click.
6. works. Reduce motion: the popover opens without animation. Screens: pop-live. Do: Nothing. Evidence: Controller.swift, popover.animates. Wireframe: click.
7. works. Down also stops on the key figures, and in a panel shorter than its lines the focused one is scrolled into view. Screens: pop-small-settings. Do: Press Down to the end. Evidence: LineView.focus scrollToVisible (0.1.14); flow-test-0.1.13 14.7. Wireframe: next.
8. friction. In a panel capped by a small screen VoiceOver reads every line, but before macOS 26 its outline is not shown on a line outside the visible part, since VoiceOver cannot ask the app to scroll there. Screens: pop-small. Do: Use the keyboard ring to scroll. Evidence: Known limit of 0.1.14 (spec 1, testing.html section 5). Wireframe: next.

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
