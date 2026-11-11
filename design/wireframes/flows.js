window.FLOWS = [
 {
  "id": "01",
  "name": "Download and first open",
  "steps": [
   {
    "n": "1",
    "text": "The releases page offers the zip of each version and its .sha256; the README says it runs on a Mac with Apple silicon (M1 or later) on macOS 14 or later.",
    "screens": [
     "browser-release"
    ],
    "do": "Download both.",
    "now": "works",
    "ev": "README.md, Install (0.1.15); flow-test-0.1.13 01.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "In Terminal, shasum -a 256 -c checks the zip and prints OK; unzip and move tokenpanda.app to Applications.",
    "screens": [
     "term-shasum"
    ],
    "do": "Run the two lines.",
    "now": "works",
    "ev": "README.md, Install; flow-test-0.1.13 01.2.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "With Homebrew instead: brew install --cask tokenpandadev/tap/tokenpanda, with no trust step; the cask declares Apple silicon only, so an Intel Mac is refused, and the caveats say Open Anyway and explain the zap.",
    "screens": [
     "term-brew"
    ],
    "do": "Read the caveats.",
    "now": "works",
    "ev": "Casks/tokenpanda.rb: depends_on arch: :arm64 (0.1.14), caveats; README.md, Install.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Double click in Applications: macOS refuses the ad hoc build, \"Apple could not verify tokenpanda is free of malware\".",
    "screens": [
     "finder-apps",
     "gk-blocked"
    ],
    "do": "Click Done.",
    "now": "friction",
    "ev": "codesign Signature=adhoc; spctl rejected (flow-test-0.1.13 01.4). By design until Developer ID signing (spec 17, path two).",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "System Settings, Privacy and Security, scroll to the bottom, Open Anyway.",
    "screens": [
     "gk-settings"
    ],
    "do": "Find the button.",
    "now": "by hand",
    "ev": "README.md, Install; flow-test-0.1.13 01.5.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "The warning comes back once; Open Anyway starts the app.",
    "screens": [
     "gk-confirm"
    ],
    "do": "Click Open Anyway.",
    "now": "by hand",
    "ev": "README.md, Install.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "No notification prompt at launch: the app asks when the first nudge is due, or when Nudge or Reopen sessions is ticked.",
    "screens": [
     "desk-nofeed"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Notifier.swift, refreshState and authorize; Controller.swift, applicationDidFinishLaunching.",
    "walk": "click"
   },
   {
    "n": "8",
    "text": "The menu bar shows the panda alone at half strength: no figures yet. No window, no Dock icon.",
    "screens": [
     "desk-nofeed"
    ],
    "do": "Click the panda.",
    "now": "works",
    "ev": "ScreenBuilder.itemFigures; LSUIElement in scripts/build-app.sh.",
    "walk": "click"
   },
   {
    "n": "9",
    "text": "If the icon is not on screen five seconds after the first launch, one window: \"tokenpanda is running\". From macOS 26 the icon \"may be switched off in System Settings, Menu Bar, hidden behind the notch when the menu bar is full, or kept out of view by an app that hides menu bar icons, such as Bartender or Ice\", with \"Open Menu Bar Settings\" and \"OK\"; before macOS 26 the menu bar is \"most likely\" full, quitting another menu bar app makes room, and a menu bar manager can also keep the icon out of view, with \"OK\" only. The notch is named only on a Mac with one: with no notch the text says \"left out when the menu bar is full\", and when it is not known (a connected screen has a notch, the item's screen is not known) both causes are named. While the screen is locked, the session is switched away or the display sleeps, it waits and asks again. It shows once.",
    "screens": [
     "desk-hidden",
     "dlg-hidden-26",
     "dlg-hidden-26-nonotch",
     "dlg-hidden-26-unknown",
     "dlg-hidden-15",
     "dlg-hidden-15-nonotch",
     "dlg-hidden-15-unknown"
    ],
    "do": "Click Open Menu Bar Settings.",
    "now": "works",
    "ev": "Grammar.hiddenIconHint and Grammar.notch (0.1.15: the notch named only on a Mac with one, a menu bar manager named in every text; texts approved 2026-11-04) and Controller.checkItemShows (0.1.14: the switch offered only from macOS 26, no verdict while locked, away or asleep); tests theHiddenIconHintOffersTheSwitchOnlyWhereThereIsOne, theNotchFollowsTheScreenThatHoldsTheItem. The real macOS 26 switch and the notch were not reproduced.",
    "walk": "click"
   },
   {
    "n": "10",
    "text": "Switching the item on in System Settings, Menu Bar, is the user's click.",
    "screens": [
     "sys-menubar"
    ],
    "do": "Switch tokenpanda on.",
    "now": "by hand",
    "ev": "testing.html, section 5.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "02",
  "name": "Set up the feed",
  "steps": [
   {
    "n": "1",
    "text": "The Claude tab says what is needed: \"needs Claude Code's status line feed\", \"one statusLine entry in ~/.claude/settings.json\", \"chained if one exists\", and one button, Install the status line entry.",
    "screens": [
     "pop-nohook"
    ],
    "do": "Read, click Install.",
    "now": "works",
    "ev": "Grammar.limits .noHook; flow-test-0.1.13 02.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "With a status line of your own it says \"your current status line is kept and chained\".",
    "screens": [
     "pop-nohook-chained"
    ],
    "do": "Click Install.",
    "now": "works",
    "ev": "flow-test-0.1.13 02.2: the hook printed the user's own output.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and a refreshInterval of 5 or less and is chained.",
    "screens": [
     "editor-after"
    ],
    "do": "Nothing to do.",
    "now": "works",
    "ev": "Hook.install; flow-test-0.1.13 02.3.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "The windows then read \"no session yet  open Claude Code once\".",
    "screens": [
     "pop-nosession"
    ],
    "do": "Start Claude Code.",
    "now": "works",
    "ev": "Grammar.limits .noSession; flow-test-0.1.13 02.4.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "During the first call both windows and the session say \"waiting for the first reply\".",
    "screens": [
     "term-claude",
     "pop-firstcall"
    ],
    "do": "Send a first prompt.",
    "now": "works",
    "ev": "ScreenBuilder.limitsView .firstReply; flow-test-0.1.13 02.5.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "After the first reply: \"Live from Claude Code\", the windows with pace, each session with its bar.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the figures.",
    "now": "works",
    "ev": "flow-test-0.1.13 02.6.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "A settings.json that is not valid JSON, or valid JSON that is not an object: Install says why under the button, wrapped, on the Claude tab and in Settings.",
    "screens": [
     "editor-broken",
     "pop-install-failed",
     "pop-settings-error"
    ],
    "do": "Fix the file, click Install again.",
    "now": "works",
    "ev": "Hook.unreadable; flow-test-0.1.13 02.7 and 02.12.",
    "walk": "click"
   },
   {
    "n": "8",
    "text": "A settings.json that is a link into a folder that does not exist: Install refuses, says why under the button (\"it is a link into ~/dotfiles/sub, a folder that does not exist\"), and writes nothing: no folder, no script, no backup.",
    "screens": [
     "pop-install-dangling",
     "pop-settings-dangling"
    ],
    "do": "Make the folder, or fix the link, and click Install again.",
    "now": "works",
    "ev": "Hook.writableTarget, SettingsFile.reason (0.1.15, audit F-6; text approved 2026-11-04); test in HardeningTests (a dangling ~/.claude link, the reason string).",
    "walk": "next"
   },
   {
    "n": "9",
    "text": "Both places name the button \"Install the status line entry\", and no line runs past the panel edge.",
    "screens": [
     "pop-settings-nohook"
    ],
    "do": "Click it.",
    "now": "works",
    "ev": "Grammar.hookRow and dimLines; flow-test-0.1.13 02.8.",
    "walk": "click"
   },
   {
    "n": "10",
    "text": "Several settings folders each get their own script and backup; a folder with only transcripts is left alone; a lost script offers Install again.",
    "screens": [
     "pop-settings-folders"
    ],
    "do": "Click Install.",
    "now": "works",
    "ev": "HookSet; flow-test-0.1.13 02.9.",
    "walk": "next"
   },
   {
    "n": "11",
    "text": "A settings.json that is a link stays a link, and the file it names keeps its mode; a created settings.json is 0600.",
    "screens": [
     "editor-after"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "SettingsFile; flow-test-0.1.13 02.10.",
    "walk": "click"
   },
   {
    "n": "12",
    "text": "disableAllHooks on: \"disableAllHooks is on in settings.json  so Claude Code runs no status line\".",
    "screens": [
     "pop-hooks-disabled"
    ],
    "do": "Turn it off, or not.",
    "now": "works",
    "ev": "Grammar.limits .hooksDisabled; flow-test-0.1.13 02.11.",
    "walk": "next"
   },
   {
    "n": "13",
    "text": "An entry installed by an earlier version gets the current script at the next launch, its chained command kept.",
    "screens": [
     "editor-after"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "HookSet.refreshScripts; flow-test-0.1.13 02.13.",
    "walk": "next"
   }
  ]
 },
 {
  "id": "03",
  "name": "Read the panel",
  "steps": [
   {
    "n": "1",
    "text": "The item shows the panda and the weekly percentage; semibold when over pace.",
    "screens": [
     "desk"
    ],
    "do": "Glance.",
    "now": "works",
    "ev": "ItemImage; flow-test-0.1.13 03.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Weekly: bar with the notch at the elapsed share, the reset and countdown, the status and projection, the allowance. Coral past the notch only when over pace.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the weekly.",
    "now": "works",
    "ev": "Grammar.windowSection; PaceTests; flow-test-0.1.13 03.2.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "5h window, the same five lines, for plans that have it.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the 5h window.",
    "now": "works",
    "ev": "flow-test-0.1.13 03.3.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Open sessions by name (set with -n or /rename), by folder when unnamed, each with its model, its 24 cell context bar and \"405.6k of 1M  41%\"; the figure's tooltip breaks over two lines inside the panel.",
    "screens": [
     "pop-session-tip"
    ],
    "do": "Hover the figure.",
    "now": "works",
    "ev": "ScreenBuilder.sessionViews, Grammar.sessionRows, LineView.tipLines; flow-test-0.1.13 03.4 and 03.12. Hover itself is by hand.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Tokens by model, project or session with the price chip and the subagent share; click the switch or press m, p, s.",
    "screens": [
     "pop-projects",
     "pop-sessions"
    ],
    "do": "Press p, then s.",
    "now": "works",
    "ev": "flow-test-0.1.13 03.5.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Week over week: up to four rows, the current week \"so far\", a hit week marked with the time it hit.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the rows.",
    "now": "works",
    "ev": "ScreenBuilder.weekViews; flow-test-0.1.13 03.6.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "With several sessions open the weekly figure holds still: the highest figure at the latest reset, across every session file.",
    "screens": [
     "pop-live"
    ],
    "do": "Watch the item.",
    "now": "works",
    "ev": "Limits.merge and apply (0.1.8); WindowsTests; flow-test-0.1.13 03.7: 28 in all 26 samples.",
    "walk": "click"
   },
   {
    "n": "8",
    "text": "Esc closes, Tab and Shift Tab switch tabs, Command Q quits.",
    "screens": [
     "pop-live"
    ],
    "do": "Press Tab.",
    "now": "works",
    "ev": "Controller.handleKey.",
    "walk": "click"
   },
   {
    "n": "9",
    "text": "The header says where the figures come from: \"Live from Claude Code\", \"As of 22:02, last Claude Code session\", or \"Waiting for a Claude Code session\".",
    "screens": [
     "pop-live",
     "pop-asof"
    ],
    "do": "Read the header.",
    "now": "works",
    "ev": "ScreenBuilder.headerLine; flow-test-0.1.13 03.9 to 03.11.",
    "walk": "click"
   },
   {
    "n": "10",
    "text": "After midnight the token rows stay: the first pass of a new day sums every record, not only new ones.",
    "screens": [
     "pop-live"
    ],
    "do": "Open the panel after midnight.",
    "now": "works",
    "ev": "TokenRefresh.needsAllRecords in Controller.refreshTranscripts (0.1.14); test theTokenRowsSurviveMidnightWithoutANewTranscriptLine. Until 0.1.13 the rows read \"nothing in the last 7 days\" until the next reply (flow-test-0.1.13 03.13).",
    "walk": "click"
   },
   {
    "n": "11",
    "text": "On a short or scaled screen the panel stops 60 points short of the screen's visible height and scrolls with an overlay scroller and no rubber band, from the top on every open and tab click; the keyboard focus scrolls into view, and a tooltip with no room above opens below its line.",
    "screens": [
     "pop-small"
    ],
    "do": "Scroll, or press Down.",
    "now": "works",
    "ev": "PanelSize and Controller.fitPanel (0.1.14); test thePanelIsNeverTallerThanTheScreen. The real scroll on a small screen is by hand (testing.html, section 5).",
    "walk": "click"
   }
  ]
 },
 {
  "id": "04",
  "name": "Nudges",
  "steps": [
   {
    "n": "1",
    "text": "Permission is asked when the first nudge is due or Nudge is ticked, not at launch.",
    "screens": [
     "pop-settings"
    ],
    "do": "Allow.",
    "now": "works",
    "ev": "Notifier.postAsking and requestIfNeeded.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "The weekly passes 80% while a session feeds: \"Weekly at 80%\" (the percentage when it fires) with the countdown and the landing time, once per weekly window.",
    "screens": [
     "notif-weekly"
    ],
    "do": "Read the banner.",
    "now": "by hand",
    "ev": "Controller.checkNudges; PaceModel.nudgeBody. Not posted by the debug binary (flow-test-0.1.13 04.2).",
    "walk": "next"
   },
   {
    "n": "3",
    "text": "15 minutes before the 5h reset: \"5h window ends in 15 min\" with the percentage, once per window.",
    "screens": [
     "notif-five"
    ],
    "do": "Read the banner.",
    "now": "by hand",
    "ev": "Controller.checkNudges.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "No 5h nudge from a window the plan no longer has.",
    "screens": [
     "pop-ultra-today"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Limits.active; flow-test-0.1.13 04.4.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Notifications denied: \"Notifications are off in System Settings\" under Nudge, and under Reopen while it is on, in the accent, a link the keyboard and VoiceOver reach, said once.",
    "screens": [
     "pop-settings-denied"
    ],
    "do": "Click it.",
    "now": "works",
    "ev": "Grammar.cbRow (0.1.14: accent, not also the checkbox's help); AccessTests; flow-test-0.1.13 04.5 and 04.7.",
    "walk": "next"
   },
   {
    "n": "6",
    "text": "The click opens System Settings, Notifications, at tokenpanda.",
    "screens": [
     "sys-notifications"
    ],
    "do": "Turn notifications on.",
    "now": "by hand",
    "ev": "Controller.perform .openNotificationSettings.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "Notifications turned on in System Settings count at once: the note goes at the next open of the popover, and the next nudge is posted, no restart.",
    "screens": [
     "pop-settings"
    ],
    "do": "Open the popover.",
    "now": "works",
    "ev": "Notifier.refreshState on every popover open and authorize before each post, from any state (0.1.14). Until 0.1.13 a denial held until a restart. No test covers the Notifier; a banner on screen is by hand.",
    "walk": "click"
   },
   {
    "n": "8",
    "text": "No nudge comes from stale figures: an hour without a session and the nudges wait.",
    "screens": [
     "pop-stale"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Controller.checkNudges.",
    "walk": "next"
   }
  ]
 },
 {
  "id": "05",
  "name": "The 5 hour window removed for Ultra (30 Oct 2026)",
  "steps": [
   {
    "n": "1",
    "text": "The feed stops carrying five_hour while the stored 5h window still runs: the last percent dim, \"not in the last feed\", no countdown or pace.",
    "screens": [
     "pop-ultra-evening"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Limits.apply retired; ScreenBuilder .quiet; flow-test-0.1.13 05.1 and 05.2.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "A retired 5h window at 100% gives normal eyes and no \"5h limit reached\".",
    "screens": [
     "desk-ultra"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "ScreenBuilder.eyes uses Limits.active; flow-test-0.1.13 05.3.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "No false \"5h window ends in 15 min\".",
    "screens": [
     "pop-ultra-evening"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "See 04.4.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "After the old reset the 5h row goes for good: a reply without five_hour hides it.",
    "screens": [
     "pop-ultra-today"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Limits.apply hidden; flow-test-0.1.13 05.5.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "A new Ultra user sees the weekly alone after the first reply.",
    "screens": [
     "pop-ultra-today"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "flow-test-0.1.13 05.6.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Max and Pro keep both windows.",
    "screens": [
     "pop-live-max"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "flow-test-0.1.13 05.7.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "Before the first reply a new Ultra user still sees a \"5h window\" row, and the Install text is titled \"Weekly and 5h window\".",
    "screens": [
     "pop-nosession",
     "pop-firstcall"
    ],
    "do": "Wait for the first reply.",
    "now": "friction",
    "ev": "Grammar.limits .noSession, .firstReply, .noHook; still open in 0.1.14 (flow-test-0.1.13 05.8).",
    "walk": "next"
   },
   {
    "n": "8",
    "text": "On Ultra the nudge row reads \"Nudge at 80%\".",
    "screens": [
     "pop-settings-ultra"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "ScreenBuilder.screen, fiveHour.",
    "walk": "next"
   }
  ]
 },
 {
  "id": "06",
  "name": "Weekly reset",
  "steps": [
   {
    "n": "1",
    "text": "Before the reset the countdown reads in days and hours, then hours and minutes.",
    "screens": [
     "pop-week-near"
    ],
    "do": "Plan the last hour.",
    "now": "works",
    "ev": "PaceModel.countdown.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "The reset passes with no session: \"Reset Sun 17:00  no session since\", the item dims; the old week keeps its figure and the new week says \"no reply yet\".",
    "screens": [
     "pop-week-rolled"
    ],
    "do": "Open Claude Code.",
    "now": "works",
    "ev": "ScreenBuilder.windowView .resetPassed, weekViews; flow-test-0.1.13 06.2 and 06.7.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "The reset passes while idle sessions feed: \"new window on the next reply\".",
    "screens": [
     "pop-week-rolled-live"
    ],
    "do": "Send a prompt.",
    "now": "works",
    "ev": "ScreenBuilder.windowView .nextReply; flow-test-0.1.13 06.3.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "The next reply brings the new week: a low figure, \"On pace\" or \"Ahead\", a new row in week over week.",
    "screens": [
     "pop-week-new"
    ],
    "do": "Read the new week.",
    "now": "works",
    "ev": "FeedTests; Weeks.swift.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Early in a window the pace row does not guess: \"On pace  too early to project\" until 5% of the window has passed (8 h 24 min of a week, 15 min of a 5h window). The new week above shows it.",
    "screens": [
     "pop-pace-early",
     "pop-week-new"
    ],
    "do": "Read the pace row in the first hours.",
    "now": "works",
    "ev": "PaceModel.reading, earliestProjection (0.1.15, flow test 06.8; texts approved 2026-11-04); test theFirstMinutesOfAWindowProjectOnlyOverPace.",
    "walk": "next"
   },
   {
    "n": "6",
    "text": "On pace or Ahead the projection reads \"N% by reset at this rate\", N at most 100; Over pace keeps \"limit ... at this rate\" in every phase, also ten minutes in.",
    "screens": [
     "pop-pace-reset",
     "pop-pace-over-early"
    ],
    "do": "Read the pace row.",
    "now": "works",
    "ev": "PaceModel.reading (0.1.15; texts approved 2026-11-04); test aLimitIsNamedOnlyOverPace.",
    "walk": "next"
   },
   {
    "n": "7",
    "text": "Week over week keeps the highest value seen per week.",
    "screens": [
     "pop-live"
    ],
    "do": "Trust the history.",
    "now": "works",
    "ev": "WindowsTests weekOverWeekKeepsTheHighestValuePerWeek; flow-test-0.1.13 06.5.",
    "walk": "click"
   },
   {
    "n": "8",
    "text": "At 100% the panda shows x x until the reset, and the weekly window reads \"limit reached, resets Sun 18:00\" in place of the pace lines.",
    "screens": [
     "desk-weekly-limit",
     "pop-live-limit"
    ],
    "do": "Wait for the reset.",
    "now": "works",
    "ev": "ItemImage; Grammar.windowSection (spec 24.33); flow-test-0.1.13 06.6.",
    "walk": "next"
   }
  ]
 },
 {
  "id": "07",
  "name": "Stale or missing feed",
  "steps": [
   {
    "n": "1",
    "text": "The last session closes: its row leaves after 60 s and the header says \"As of 13:05, last Claude Code session\"; pace is still computed for an hour.",
    "screens": [
     "pop-asof"
    ],
    "do": "Read the time.",
    "now": "works",
    "ev": "FeedTests openSessionsTiming; flow-test-0.1.13 07.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "After an hour: the stale form, dim bars, \"as of 13:05\", the note that limits are shared with the Claude app and other Macs, the item at half strength.",
    "screens": [
     "pop-stale",
     "desk-stale"
    ],
    "do": "Open Claude Code to refresh.",
    "now": "works",
    "ev": "flow-test-0.1.13 07.2.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Use on the web, in the Claude app or on another Mac shows only with the next Claude Code reply on this Mac; the stale note says so.",
    "screens": [
     "pop-stale"
    ],
    "do": "Keep it in mind.",
    "now": "friction",
    "ev": "By design: no network (README.md; flow-test-0.1.13 07.3).",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Sessions on an API key, Bedrock or Vertex: \"these sessions carry no plan limits\".",
    "screens": [
     "pop-nolimits"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Limits.planless; flow-test-0.1.13 07.4.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "No transcripts folder: \"No transcripts in ~/.claude/projects\" in the token section; a read error shows its own message.",
    "screens": [
     "pop-notranscripts"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "ScreenBuilder.tokensView.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "The statusLine entry removed by hand: the app notices the settings.json change on the next tick and offers Install again.",
    "screens": [
     "pop-nohook"
    ],
    "do": "Install again or not.",
    "now": "works",
    "ev": "Controller.refreshFeed, settingsModified.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "08",
  "name": "The Mac tab",
  "steps": [
   {
    "n": "1",
    "text": "Click Mac or press Tab: CPU, GPU, the memory grid with pressure and swap, battery, the busiest processes.",
    "screens": [
     "pop-mac"
    ],
    "do": "Read.",
    "now": "works",
    "ev": "flow-test-0.1.13 08.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "The free cells of the memory grid are #949494, 3 to 1 even over a white desktop.",
    "screens": [
     "pop-mac"
    ],
    "do": "Read the grid over a bright wallpaper.",
    "now": "works",
    "ev": "Tokens.dimmer (0.1.14, was #888888, 2.7 to 1); AccessTests.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign.",
    "screens": [
     "desk-warning",
     "pop-mac-warning"
    ],
    "do": "Open the Mac tab.",
    "now": "works",
    "ev": "flow-test-0.1.13 08.2.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Battery health unknown: \"health n/a\", never a dash.",
    "screens": [
     "pop-mac-health"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "flow-test-0.1.13 08.3.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Mac figures in the bar appends \" CPU 9%\" to the item.",
    "screens": [
     "desk-mac"
    ],
    "do": "Tick it in Settings.",
    "now": "works",
    "ev": "flow-test-0.1.13 08.4.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Claude Code's processes show as \"Claude Code\".",
    "screens": [
     "pop-mac"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "flow-test-0.1.13 08.5.",
    "walk": "next"
   }
  ]
 },
 {
  "id": "09",
  "name": "Settings",
  "steps": [
   {
    "n": "1",
    "text": "Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, the version line, Quit.",
    "screens": [
     "pop-settings"
    ],
    "do": "Read the rows.",
    "now": "works",
    "ev": "Grammar.settingsTab; flow-test-0.1.13 09.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Open at login: the box shows what macOS says; while macOS waits for approval a dim line opens Login Items.",
    "screens": [
     "pop-settings-login",
     "pop-settings-approval",
     "sys-loginitems"
    ],
    "do": "Tick it.",
    "now": "by hand",
    "ev": "Controller.clickLogin; not clicked in the flow tests.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "List price equivalent off: the price chip goes.",
    "screens": [
     "pop-nochip"
    ],
    "do": "Untick it.",
    "now": "works",
    "ev": "ScreenBuilder.tokensView.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Quit and Command Q end the app; the item goes.",
    "screens": [
     "desk-quit"
    ],
    "do": "Click Quit.",
    "now": "works",
    "ev": "Controller.handleKey; flow-test-0.1.13 09.4.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "The version line says what runs: \"tokenpanda 0.1.15\".",
    "screens": [
     "pop-settings"
    ],
    "do": "Read it.",
    "now": "works",
    "ev": "ScreenBuilder.screen, CFBundleShortVersionString.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Light mode: the same layout on a light glass, switching with the Mac's appearance.",
    "screens": [
     "pop-settings"
    ],
    "do": "Change the appearance.",
    "now": "works",
    "ev": "Ground in Controller.swift; Tokens.light; flow-test-0.1.13 09.6. The live switch is by hand.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "A tall Settings tab on a short screen scrolls inside the panel, so Quit stays reachable.",
    "screens": [
     "pop-small-settings"
    ],
    "do": "Scroll to Quit.",
    "now": "works",
    "ev": "PanelSize (0.1.14); see 03.11.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "10",
  "name": "Keep the Mac awake",
  "steps": [
   {
    "n": "1",
    "text": "Keep the Mac awake while Claude works: while a session's figures move, \"awake  1 session working\" and one power assertion.",
    "screens": [
     "pop-settings-awake"
    ],
    "do": "Tick it.",
    "now": "works",
    "ev": "Controller.updateAwake; FeedTests keep awake.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Also while a session waits for you: idle sessions count too, \"awake  1 session open\".",
    "screens": [
     "pop-settings-awake-open",
     "term-pmset"
    ],
    "do": "Tick the second row.",
    "now": "works",
    "ev": "flow-test-0.1.13 10.2.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "The row says \"a closed lid on battery still sleeps\".",
    "screens": [
     "pop-settings-awake"
    ],
    "do": "Read it.",
    "now": "works",
    "ev": "Grammar.settingsTab; flow-test-0.1.13 10.3.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "11",
  "name": "Reopen sessions after a restart",
  "steps": [
   {
    "n": "1",
    "text": "Turn on Reopen sessions after a restart: the app keeps the open sessions with their names and start options in restore.json, readable only by you.",
    "screens": [
     "pop-settings-restore"
    ],
    "do": "Tick it.",
    "now": "works",
    "ev": "flow-test-0.1.13 11.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "After a restart, one notification names the sessions that were open, with Reopen.",
    "screens": [
     "notif-reopen"
    ],
    "do": "Click Reopen.",
    "now": "by hand",
    "ev": "Controller.offerRestore; flow-test-0.1.13 11.2 and 11.7.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Reopen opens each session in Terminal as it was started, with --remote-control where it had it, and the fallbacks.",
    "screens": [
     "term-reopen"
    ],
    "do": "Work on.",
    "now": "by hand",
    "ev": "Reopen.script; flow-test-0.1.13 11.3.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "With notifications off the Reopen row says so, as the same link as under Nudge; turned on again, the offer and the end notices come without a restart.",
    "screens": [
     "pop-settings-denied"
    ],
    "do": "Click the link.",
    "now": "works",
    "ev": "Grammar.settingsTab; Notifier.refreshState and authorize (0.1.14).",
    "walk": "next"
   },
   {
    "n": "5",
    "text": "Turning it off deletes restore.json.",
    "screens": [
     "pop-settings"
    ],
    "do": "Untick it.",
    "now": "works",
    "ev": "Controller.perform .toggle.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "A print run is never reopened; a start prompt is not sent again.",
    "screens": [
     "term-reopen"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "LaunchOptions; flow-test-0.1.13 11.6.",
    "walk": "next"
   },
   {
    "n": "7",
    "text": "The end notice also comes after a deliberate /exit in a window you keep.",
    "screens": [
     "notif-ended"
    ],
    "do": "Dismiss it.",
    "now": "friction",
    "ev": "Controller.watchEnds has no working check; still open in 0.1.14 (flow-test-0.1.13 11.8).",
    "walk": "click"
   }
  ]
 },
 {
  "id": "12",
  "name": "Update",
  "steps": [
   {
    "n": "1",
    "text": "The app never checks for updates (no network); a new version is found on the releases page or with brew outdated.",
    "screens": [
     "browser-release"
    ],
    "do": "Look on GitHub.",
    "now": "friction",
    "ev": "By design (spec 16).",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "brew upgrade --cask tokenpandadev/tap/tokenpanda quits and replaces the app.",
    "screens": [
     "term-brew-upgrade"
    ],
    "do": "Run it.",
    "now": "by hand",
    "ev": "Casks/tokenpanda.rb, uninstall quit.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "A new ad hoc build can bring back the Open Anyway steps; the version line in Settings confirms what runs.",
    "screens": [
     "term-brew-upgrade",
     "gk-blocked"
    ],
    "do": "Open Anyway again.",
    "now": "by hand",
    "ev": "codesign adhoc; flow-test-0.1.13 12.3.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Settings, the entry and the records survive the update, and the installed script is brought up to date at launch.",
    "screens": [
     "pop-live"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "flow-test-0.1.13 12.4.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "13",
  "name": "Uninstall",
  "steps": [
   {
    "n": "1",
    "text": "Settings, Remove the status line entry puts the previous statusLine back exactly, or removes the key.",
    "screens": [
     "editor-restored"
    ],
    "do": "Click it.",
    "now": "works",
    "ev": "Hook.uninstall; flow-test-0.1.13 13.1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "A settings.json Install created is deleted on Remove; when it is a link whose file Install created, the file goes and the link stays.",
    "screens": [
     "term-settings-gone"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Hook.uninstall resolves the link (0.1.14); test aDanglingLinkStaysALinkAfterRemoveInTheAppAndInTheScript. Until 0.1.13 the link went and the entry stayed in the file.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Quit and move the app to the Bin.",
    "screens": [
     "finder-bin"
    ],
    "do": "Drag to the Bin.",
    "now": "works",
    "ev": "privacy 9.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Moved to the Bin without Remove: the script deletes its folder's session files that stopped changing over a minute ago, so the leftover stays small.",
    "screens": [
     "term-leftover"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "hook/statusline.sh cleanup line (0.1.13); flow-test-0.1.13 13.4 and 13.7.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "brew uninstall --zap runs remove.sh, which puts the previous status line back, the same way through a link (readlink -f), before the data folder goes.",
    "screens": [
     "term-zap"
    ],
    "do": "Run it.",
    "now": "works",
    "ev": "HookSet remove script (0.1.14 for the link); flow-test-0.1.13 13.5. brew itself is by hand.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Delete Application Support and the preferences file by hand; nothing else was created.",
    "screens": [
     "finder-bin"
    ],
    "do": "Delete two paths.",
    "now": "works",
    "ev": "The cask's zap trash list.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "14",
  "name": "VoiceOver and the keyboard",
  "steps": [
   {
    "n": "1",
    "text": "VoiceOver on the item says \"tokenpanda, Weekly 28% used, ahead, resets Sunday 17:00\".",
    "screens": [
     "desk-ultra"
    ],
    "do": "Listen.",
    "now": "by hand",
    "ev": "ScreenBuilder.itemFigures; Controller.render.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "The privacy sentence is one element, and each window, week and Mac figure is one sentence.",
    "screens": [
     "pop-voiceover"
    ],
    "do": "Read with VO keys.",
    "now": "works",
    "ev": "AccessTests; flow-test-0.1.13 14.2.",
    "walk": "next"
   },
   {
    "n": "3",
    "text": "Tabs are radio buttons, settings checkboxes with values, Install, Remove, Quit and the notifications link buttons with press.",
    "screens": [
     "pop-voiceover"
    ],
    "do": "Press Install.",
    "now": "by hand",
    "ev": "LineView accessibility elements; AccessTests. Not heard in the flow tests.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "The keyboard reaches every control: Down and Up, Left and Right, Space or Return; a thin accent ring shows where.",
    "screens": [
     "pop-keyboard"
    ],
    "do": "Press Down, then Space.",
    "now": "works",
    "ev": "LineView.moveFocus; flow-test-0.1.13 14.4.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "The key hints read clearly over white, at 4.5 to 1 or more.",
    "screens": [
     "pop-keyboard"
    ],
    "do": "Read them.",
    "now": "works",
    "ev": "Tokens.quiet; AccessTests.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Reduce motion: the popover opens without animation.",
    "screens": [
     "pop-live"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Controller.swift, popover.animates.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "Down also stops on the key figures, and in a panel shorter than its lines the focused one is scrolled into view.",
    "screens": [
     "pop-small-settings"
    ],
    "do": "Press Down to the end.",
    "now": "works",
    "ev": "LineView.focus scrollToVisible (0.1.14); flow-test-0.1.13 14.7.",
    "walk": "next"
   },
   {
    "n": "8",
    "text": "In a panel capped by a small screen VoiceOver reads every line, but before macOS 26 its outline is not shown on a line outside the visible part, since VoiceOver cannot ask the app to scroll there.",
    "screens": [
     "pop-small"
    ],
    "do": "Use the keyboard ring to scroll.",
    "now": "friction",
    "ev": "Known limit of 0.1.14 (spec 1, testing.html section 5).",
    "walk": "next"
   }
  ]
 }
];
window.TITLES = {
 "desk": "Menu bar, the item: panda and the weekly percentage, over pace in semibold",
 "pop-live": "Claude tab, live: weekly over pace, 5h ahead (Max or Pro)",
 "pop-session-tip": "Claude tab, hover on a session figure: list price, lines, effort, over two lines",
 "pop-projects": "Claude tab, tokens by project, 7 days (p)",
 "pop-sessions": "Claude tab, tokens by session, today (s)",
 "pop-nochip": "Claude tab with List price equivalent off: no price chip",
 "desk-nofeed": "Menu bar, first launch: the panda alone, dimmed",
 "pop-nohook": "Claude tab, first open: Install the status line entry",
 "pop-nohook-chained": "Claude tab, first open with a status line of your own: kept and chained",
 "pop-install-failed": "Claude tab after Install with a settings.json that is not valid JSON: the reason under the button",
 "pop-install-dangling": "Claude tab after Install with a settings.json that is a link into a folder that does not exist: refused, nothing written",
 "pop-hooks-disabled": "Claude tab with disableAllHooks on: Claude Code runs no status line",
 "pop-nosession": "Claude tab, entry installed, no session yet",
 "pop-firstcall": "Claude tab during the first call: sessions open, both windows wait for the first reply",
 "desk-ultra": "Menu bar today, Ultra: the weekly, nothing about a 5h window",
 "pop-ultra-today": "Claude tab today, Ultra: the weekly alone, no 5h section",
 "pop-ultra-evening": "30 Oct, 21:30, Ultra: the 5h window keeps its last figure dim, not in the last feed",
 "pop-live-max": "Claude tab, Max or Pro today: both windows, as before",
 "desk-five-limit": "Menu bar, Max or Pro, the 5h window at 100%: - - eyes until its reset",
 "pop-week-near": "Claude tab, 40 minutes before the weekly reset",
 "pop-week-rolled": "Claude tab, weekly reset passed with no session since: the new week says no reply yet",
 "pop-week-rolled-live": "Claude tab, weekly reset passed while idle sessions feed: new window on the next reply",
 "pop-week-new": "Claude tab, the new week arrived: 1% used, last week kept",
 "pop-pace-early": "Claude tab, 100 minutes into a new week and 11 minutes into a 5h window: On pace, too early to project",
 "pop-pace-reset": "Claude tab, On pace and Ahead read the share at the reset: 100% by reset at this rate",
 "pop-pace-over-early": "Claude tab, ten minutes into a 5h window: Over pace keeps its limit time even this early",
 "desk-weekly-limit": "Menu bar, weekly limit reached: x x eyes until the reset",
 "pop-live-limit": "Claude tab, the weekly window at 100%: limit reached, resets Sun 18:00",
 "pop-asof": "Claude tab, last session closed 20 minutes ago: As of 14:00, pace still computed",
 "pop-stale": "Claude tab, stale: no session for over an hour",
 "desk-stale": "Menu bar, stale: the item at half strength",
 "pop-nolimits": "Claude tab, sessions on an API key, Bedrock or Vertex: no plan limits",
 "pop-notranscripts": "Claude tab, no transcripts folder: the folders looked in, no Week over week",
 "pop-mac": "Mac tab: CPU, GPU, memory, battery, processes",
 "pop-mac-ultra": "Mac tab (Ultra, today)",
 "pop-mac-warning": "Mac tab with the warning: dot on the tab, pressure warn",
 "pop-live-warn": "Claude tab with the Mac warning dot",
 "pop-mac-health": "Mac tab, no battery health from macOS: left out",
 "desk-warning": "Menu bar with the Mac warning sign",
 "desk-mac": "Menu bar with Mac figures in the bar: CPU 9%",
 "desk-quit": "Menu bar after Quit: the item is gone",
 "pop-settings": "Settings tab",
 "pop-settings-ultra": "Settings tab on a plan without a 5h window: Nudge at 80%",
 "pop-settings-login": "Settings, Open at login on: macOS lists it in Login Items",
 "pop-settings-approval": "Settings, Open at login waits for approval: click to allow it in Login Items",
 "pop-settings-awake": "Settings, Keep the Mac awake on, one session working",
 "pop-settings-awake-open": "Settings, also while a session waits: awake  1 session open",
 "pop-settings-restore": "Settings, Reopen sessions after a restart on",
 "pop-settings-nohook": "Settings, entry not installed: Install the status line entry",
 "pop-settings-folders": "Settings, two settings folders: Install for the one missing, Remove, the errors whole",
 "pop-settings-denied": "Settings, notifications denied: the note in the accent, a link, under Reopen too",
 "pop-settings-dangling": "Settings, the install error for a link into a folder that does not exist, under the row, whole",
 "pop-settings-error": "Settings, the install error under the row, whole",
 "pop-voiceover": "VoiceOver in the popover: buttons, tabs and checkboxes with their state, pressable",
 "pop-keyboard": "Keyboard in the popover: the focus ring on a setting, Space ticks it",
 "pop-small": "Claude tab on a small or scaled screen: the panel stops short of the screen and scrolls, from the top",
 "pop-small-settings": "Settings on a small screen: the keyboard ring scrolls Quit into view",
 "browser-release": "Releases page: tokenpanda-0.1.15.zip and its .sha256",
 "term-shasum": "Terminal: shasum checks the zip, OK",
 "term-brew": "Terminal: brew install from the tap, the caveats",
 "finder-apps": "Finder, Applications: tokenpanda.app",
 "gk-blocked": "macOS blocks the first open: Apple could not verify tokenpanda",
 "gk-settings": "System Settings, Privacy & Security: Open Anyway, at the bottom",
 "gk-confirm": "The warning again: Open Anyway",
 "notif-permission": "The notification permission prompt: when Nudge or Reopen is ticked on, or the first nudge is due",
 "desk-hidden": "First launch, the icon not visible: switched off in Menu Bar settings, behind the notch, or kept out of view by a menu bar manager",
 "dlg-hidden-26": "macOS 26 and later, with a notch: tokenpanda is running, with Open Menu Bar Settings",
 "dlg-hidden-26-nonotch": "macOS 26 and later, no notch: tokenpanda is running, with Open Menu Bar Settings",
 "dlg-hidden-26-unknown": "macOS 26 and later, notch not known: tokenpanda is running, with Open Menu Bar Settings",
 "dlg-hidden-15": "macOS 14 and 15, with a notch: tokenpanda is running, the full menu bar, OK only",
 "dlg-hidden-15-nonotch": "macOS 14 and 15, no notch: tokenpanda is running, the full menu bar, OK only",
 "dlg-hidden-15-unknown": "macOS 14 and 15, notch not known: tokenpanda is running, the full menu bar, OK only",
 "sys-menubar": "System Settings, Menu Bar: allow tokenpanda (macOS 26)",
 "sys-loginitems": "System Settings, General, Login Items: tokenpanda listed",
 "sys-notifications": "System Settings, Notifications, tokenpanda: the link from Settings lands here",
 "editor-after": "~/.claude/settings.json after Install: one statusLine entry, the rest kept",
 "editor-broken": "~/.claude/settings.json that is not valid JSON (a trailing comma)",
 "editor-restored": "~/.claude/settings.json after Remove: your statusLine back exactly",
 "term-settings-gone": "After Remove, when Install had created settings.json: the file is gone",
 "term-claude": "Terminal: a Claude Code session, the first reply",
 "notif-weekly": "Nudge: Weekly at 80%",
 "notif-five": "Nudge: 5h window ends in 15 min (Max or Pro)",
 "notif-reopen": "After a restart: the sessions that were open, by name, with Reopen",
 "notif-ended": "A session ended while its Terminal window stays open: its name, the time, Reopen",
 "desk-reopen-denied": "After a restart with notifications off: no offer; the Reopen row says so",
 "term-reopen": "Terminal: each session started again as it was started, with Remote Control where it had it",
 "term-pmset": "Terminal: pmset lists the tokenpanda assertion",
 "term-brew-upgrade": "Terminal: brew upgrade --cask, then Open Anyway again",
 "finder-bin": "Finder: tokenpanda.app moved to the Bin",
 "term-leftover": "Moved to the Bin without Remove: the script cleans up after itself, the folder stays small",
 "term-zap": "brew uninstall --zap: remove.sh takes the entry out first, your own status line comes back"
};
