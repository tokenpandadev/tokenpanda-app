window.FLOWS = [
 {
  "id": "01",
  "name": "Download and first open",
  "steps": [
   {
    "n": "1",
    "text": "The releases page offers tokenpanda-0.1.7.zip and tokenpanda-0.1.7.zip.sha256.",
    "screens": [
     "browser-release"
    ],
    "do": "Download both.",
    "now": "works",
    "ev": "README.md, Install; build/release-notes-0.1.7.md.",
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
    "ev": "README.md, Install; build/tokenpanda-0.1.7.zip.sha256.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "With Homebrew instead: brew install tokenpandadev/tap/tokenpanda, and the caveats say Open Anyway and Remove before uninstalling.",
    "screens": [
     "term-brew"
    ],
    "do": "Read the caveats.",
    "now": "works",
    "ev": "Casks/tokenpanda.rb:26-33.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Double click in Applications: macOS refuses, \"Apple could not verify tokenpanda is free of malware\".",
    "screens": [
     "finder-apps",
     "gk-blocked"
    ],
    "do": "Click Done.",
    "now": "friction",
    "ev": "codesign: Signature=adhoc, TeamIdentifier not set; spctl -a -t exec: rejected. By design for now (spec 17, path one).",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "System Settings, Privacy and Security, scroll to the bottom, Open Anyway.",
    "screens": [
     "gk-settings"
    ],
    "do": "Find the button.",
    "now": "friction",
    "ev": "README.md, Install; spec 17. Not walked on a clean account in this run (left out 1).",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "The warning comes back once; Open Anyway starts the app.",
    "screens": [
     "gk-confirm"
    ],
    "do": "Click Open Anyway.",
    "now": "works",
    "ev": "README.md, Install.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "The first thing the app shows is the notification permission prompt: nudges are on by default and the app asks at launch, before the user has seen it or knows what a nudge is.",
    "screens": [
     "notif-permission"
    ],
    "do": "Allow or not, without context.",
    "now": "friction",
    "ev": "Controller.swift:124; Settings.swift:21 (nudges default true); Notifier.swift:40-51.",
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
    "ev": "fixtures/item-nofeed; ScreenBuilder.swift:315-319; LSUIElement in scripts/build-app.sh.",
    "walk": "click"
   },
   {
    "n": "9",
    "text": "On macOS 26 and later the item stays hidden until it is allowed in System Settings, Menu Bar; a crowded menu bar behind the notch hides it too, and nothing else says the app runs.",
    "screens": [
     "desk-hidden",
     "sys-menubar"
    ],
    "do": "Allow it under Menu Bar.",
    "now": "friction",
    "ev": "README.md, Install; spec 19, by hand.",
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
    "text": "The Claude tab says what is needed: \"needs Claude Code's status line feed, one statusLine entry in ~/.claude/settings.json\", and one button, Install the status line hook.",
    "screens": [
     "pop-nohook"
    ],
    "do": "Read, click Install.",
    "now": "works",
    "ev": "live-nohook tab0; Grammar.swift:100-110.",
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
    "ev": "Grammar.swift:105; hookrun own-statusline: the hook printed MINE, the user's own output.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and refreshInterval and is chained.",
    "screens": [
     "editor-after"
    ],
    "do": "Nothing to do.",
    "now": "works",
    "ev": "hookrun no-settings, no-statusline, own-statusline; Hook.swift:108-136.",
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
    "ev": "fixtures/claude-nosession; Grammar.swift:111-113.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "During the first call the open sessions show \"waiting for the first reply\" while both windows still say \"open Claude Code once\".",
    "screens": [
     "term-claude",
     "pop-firstcall"
    ],
    "do": "Send a first prompt.",
    "now": "friction",
    "ev": "states/claude-first-call; Grammar.swift:112; ScreenBuilder.swift:93-95.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "After the first reply: header Usage live, both windows with pace, the session with its context bar.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the figures.",
    "now": "works",
    "ev": "live-max tab0; fixtures/claude-overpace.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "If settings.json is not valid JSON, Install on the Claude tab changes nothing on screen; the error is drawn only on the Settings tab, cut at the width, without its reason.",
    "screens": [
     "editor-broken",
     "pop-install-failed",
     "pop-settings-error"
    ],
    "do": "Click Install, wonder, open Settings.",
    "now": "broken",
    "ev": "hookrun broken-json: \"cannot read settings.json: settings.json is not a JSON object\"; Grammar.swift:100-110 draws no error; ScreenBuilder.swift:284-285 passes hookError to Settings only; states/settings-errors.",
    "walk": "click"
   },
   {
    "n": "8",
    "text": "In Settings the row says \"Install the status line entry\" (the Claude tab says hook), and its second line runs past the popover edge: \"...~/.claude/settings.js\".",
    "screens": [
     "pop-settings-nohook"
    ],
    "do": "Click it.",
    "now": "friction",
    "ev": "live-settings tab2 and states/settings-nohook-denied: the line is cut; Grammar.swift:318 (51 cells in a 47 cell popover).",
    "walk": "click"
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
    "ev": "fixtures/closed; ItemImage.swift:54-99.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Weekly: bar with the tick at the elapsed share, \"Resets Sun 18:00  in 3d 3h\", \"Over pace  limit Sun 01:20 at this rate\", \"0.5% an hour left\". Coral past the tick only when over pace.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the weekly.",
    "now": "works",
    "ev": "fixtures/claude-overpace; spec 7 worked example; PaceTests.",
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
    "ev": "fixtures/claude-overpace; live-max tab0.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Open sessions: project, model, context bar and \"405.6k of 1M  41%\"; hovering the figure shows list price, lines added and removed, effort.",
    "screens": [
     "pop-session-tip"
    ],
    "do": "Hover the figure.",
    "now": "friction",
    "ev": "The tooltip text is 66 characters plus padding (68 cells) in a 50 cell view, drawn from the left edge and clipped by the view, so it ends at \"9 remo\" and the effort is never seen: LineView.swift:203-213, ScreenBuilder.swift:106-107. Computed from the code, hover not possible in this run.",
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
    "ev": "fixtures/claude-projects, claude-sessions; Controller.swift:539.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "Week over week: four rows, the hit week marked with the time it hit.",
    "screens": [
     "pop-live"
    ],
    "do": "Read the rows.",
    "now": "works",
    "ev": "fixtures/claude-overpace.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "With several sessions open the weekly figure jumps every few seconds between the values each session last saw: 28%, 12%, 28%, 18%, 11% within 30 s, in the bar, the item, the projection and the allowance.",
    "screens": [
     "desk-flicker-a",
     "desk-flicker-b",
     "pop-flicker-a",
     "pop-flicker-b"
    ],
    "do": "Watch the item.",
    "now": "broken",
    "ev": "Real data folder, sampled 11:11:16 to 11:11:45: limits.json used 12, 28, 18, 11 as the newest session file changed; ten session files carried 9 to 28 for the same resets_at. FeedReader.swift:96-101 takes the newest file; idle sessions rewrite their cached figure every 5 s (refreshInterval, Hook.swift:68).",
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
    "ev": "Controller.swift:529-541.",
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
    "text": "Nudges are on by default; permission is asked at launch.",
    "screens": [
     "notif-permission"
    ],
    "do": "Allow.",
    "now": "friction",
    "ev": "Controller.swift:124 (see 01.7).",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "The weekly passes 80% while a session feeds: \"Weekly at 80%\" with the countdown and the landing time, once per weekly window.",
    "screens": [
     "notif-weekly"
    ],
    "do": "Read the banner.",
    "now": "works",
    "ev": "Controller.swift:413-419; PaceModel.nudgeBody, PaceTests. Notifications need the app bundle, so not posted by the debug binary (left out 3).",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "15 minutes before the 5h reset: \"5h window ends in 15 min\" with the percentage, once per window.",
    "screens": [
     "notif-five"
    ],
    "do": "Read the banner.",
    "now": "works",
    "ev": "Controller.swift:420-424.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Ultra: the frozen 5h record can still pass that test once, and announce the end of a window the plan no longer has.",
    "screens": [
     "notif-five-false"
    ],
    "do": "Ignore it.",
    "now": "broken",
    "ev": "Controller.swift:420-424 reads l.windows[\"five_hour\"], kept by FeedReader.swift:23-37; the real record resets_at is 31 Oct 00:10. Read from the code, not seen on screen.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Notifications denied: the Nudge row says \"Notifications are off for this app in System\" and stops at the edge; it does not open System Settings.",
    "screens": [
     "pop-settings-denied"
    ],
    "do": "Find the setting yourself.",
    "now": "friction",
    "ev": "states/settings-nohook-denied; Grammar.swift:279; Notifier.swift:30.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "No nudge comes from stale figures: an hour without a session and the nudges wait.",
    "screens": [
     "pop-stale"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Controller.swift:412.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "05",
  "name": "The 5 hour window removed for Ultra (30 Oct 2026)",
  "steps": [
   {
    "n": "1",
    "text": "30 Oct, evening: the feed stops sending five_hour for verified Ultra accounts. The app keeps the last figure (63% in this example) and draws it as live: countdown running, tick moving, \"Over pace  limit 22:50 at this rate\".",
    "screens": [
     "pop-ultra-evening"
    ],
    "do": "Believe it.",
    "now": "broken",
    "ev": "live-ultra-day1: after 50 s of feeds without five_hour, limits.json still held five_hour used 63 and the tab showed it with pace lines. FeedReader.swift:23-37 (apply only touches keys present); ScreenBuilder.swift:60-78 (asOf is shared, so it is never stale).",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Near the stored reset the same 63% reads \"Ahead  66% by reset\", \"185% an hour left\".",
    "screens": [
     "pop-ultra-late"
    ],
    "do": "Read nonsense.",
    "now": "broken",
    "ev": "states/ultra-late.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "If the 5h window was at 100% when the feed stopped, the panda shows - - eyes and VoiceOver says \"5h limit reached\" until the old reset.",
    "screens": [
     "desk-five-limit"
    ],
    "do": "Think you are blocked.",
    "now": "broken",
    "ev": "states/ultra-five-at-limit: label \"... 5h limit reached\"; ScreenBuilder.swift:292-299.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Around the old reset a \"5h window ends in 15 min\" nudge can fire for it.",
    "screens": [
     "notif-five-false"
    ],
    "do": "Ignore it.",
    "now": "broken",
    "ev": "Controller.swift:420-424 (see 04.4).",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Today, 31 Oct: the 5h window is an empty bar with \"Reset 00:10  no session since\", under \"Usage live\" and a listed open session, and it stays that way for good. The smallest fix drops the window when a fresh feed comes without it.",
    "screens": [
     "pop-ultra-today",
     "pop-ultra-fixed"
    ],
    "do": "Read a contradiction.",
    "now": "broken",
    "ev": "Real limits.json: five_hour used 1, resetsAt 31 Oct 00:10, asOf 11:11 today; all ten live session files carry seven_day only. live-ultra-today tab0 shows exactly this. ScreenBuilder.swift:62 (.absent is never reached once a record exists), :65-66 (resetPassed).",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "A new Ultra user, whose feed never had five_hour, sees an empty 5h bar with \"not in the last feed\" for good.",
    "screens": [
     "pop-ultra-new"
    ],
    "do": "Wonder what it means.",
    "now": "friction",
    "ev": "states/ultra-new; ScreenBuilder.swift:62.",
    "walk": "click"
   },
   {
    "n": "7",
    "text": "Max and Pro feeds still carry five_hour; their panel is unchanged.",
    "screens": [
     "pop-live-max"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "live-max tab0; states/max-both.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "06",
  "name": "Weekly reset",
  "steps": [
   {
    "n": "1",
    "text": "Before the reset the countdown reads in hours and minutes.",
    "screens": [
     "pop-week-near"
    ],
    "do": "Plan the last hour.",
    "now": "works",
    "ev": "PaceModel.countdown; PaceTests.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "The reset passes with no session open: the weekly reads \"Reset Sun 17:00  no session since\", the item dims, the week row says \"last seen 91%\".",
    "screens": [
     "pop-week-rolled"
    ],
    "do": "Open Claude Code.",
    "now": "works",
    "ev": "fixtures/claude-resetpassed; ScreenBuilder.swift:176-178.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "The reset passes while idle sessions feed: Claude Code drops the passed window, the app keeps it, and the weekly reads \"no session since\" under \"Usage live\" with sessions listed, until the next reply.",
    "screens": [
     "pop-week-rolled-live"
    ],
    "do": "Send a prompt.",
    "now": "friction",
    "ev": "states/weekly-rolled-live; Claude Code docs as quoted in spec 3 (\"Claude Code drops a window once its resets_at time passes\"); real weeks.json: the 25 Oct week was last updated 22 min after its reset, so the old record outlived it.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "The next reply brings the new week: \"1% used\", \"On pace\", a new row in week over week.",
    "screens": [
     "pop-week-new"
    ],
    "do": "Read the new week.",
    "now": "works",
    "ev": "states/weekly-new; Feed/Weeks.swift:22-32.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Week over week keeps the last value seen per week; with several sessions that is whichever session wrote last, often an idle one with a lower figure.",
    "screens": [
     "pop-flicker-b"
    ],
    "do": "Trust the history.",
    "now": "broken",
    "ev": "Real weeks.json: current week lastUsed 12 while the account is at 28; Controller.swift:197-201 applies whatever limits holds.",
    "walk": "click"
   },
   {
    "n": "6",
    "text": "At 100% the panda shows x x until the reset.",
    "screens": [
     "desk-weekly-limit"
    ],
    "do": "Wait for the reset.",
    "now": "works",
    "ev": "fixtures/item-weekly-limit; ItemImage.swift:32-48.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "07",
  "name": "Stale or missing feed",
  "steps": [
   {
    "n": "1",
    "text": "The last session closes: its row leaves after 60 s and the header says \"Usage as of 13:05, last Claude Code session\"; pace is still computed for an hour.",
    "screens": [
     "pop-asof"
    ],
    "do": "Read the time.",
    "now": "works",
    "ev": "FeedTests openSessionsTiming; ScreenBuilder.swift:275-279.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "After an hour: the stale form, dim bars, \"as of 13:05\", the note that limits are shared, the item at half strength.",
    "screens": [
     "pop-stale",
     "desk-stale"
    ],
    "do": "Open Claude Code to refresh.",
    "now": "works",
    "ev": "fixtures/claude-stale, item-stale.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Use on the web or in the Claude app moves the limits, but the app sees it only when a Claude Code session feeds; the stale note says so.",
    "screens": [
     "pop-stale"
    ],
    "do": "Keep it in mind.",
    "now": "friction",
    "ev": "README.md, By the rules; spec 3. By design: no network.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "An account without plan limits: \"this account has no plan limits to show\".",
    "screens": [
     "pop-nolimits"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "fixtures/claude-nolimits.",
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
    "ev": "states/claude-no-transcripts, claude-transcripts-denied.",
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
    "ev": "Controller.swift:196; Hook.swift:75-81.",
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
    "ev": "fixtures/mac; live-max tab1.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign.",
    "screens": [
     "desk-warning",
     "pop-mac-warning"
    ],
    "do": "Open the Mac tab.",
    "now": "works",
    "ev": "fixtures/mac-warning, item-warning; live runs on this Mac showed the dot and the sign.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Battery health unknown: \"health n/a\", never a dash.",
    "screens": [
     "pop-mac-health"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "fixtures/mac-health-na.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Mac figures in the bar appends \" CPU 9%\" to the item.",
    "screens": [
     "desk-mac"
    ],
    "do": "Tick it in Settings.",
    "now": "works",
    "ev": "ScreenBuilder.swift:314.",
    "walk": "click"
   }
  ]
 },
 {
  "id": "09",
  "name": "Settings",
  "steps": [
   {
    "n": "1",
    "text": "Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, Quit.",
    "screens": [
     "pop-settings"
    ],
    "do": "Read the rows.",
    "now": "works",
    "ev": "fixtures/settings; live-settings tab2.",
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
    "now": "works",
    "ev": "Controller.swift:283-304; spec 10, seen on the build Mac. Not clicked in this run (left out 2).",
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
    "ev": "ScreenBuilder.swift:136-140.",
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
    "ev": "Grammar.swift:291; Controller.swift:531.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Nowhere in the app is the version: no About, no line in Settings.",
    "screens": [
     "pop-settings"
    ],
    "do": "Look for the version.",
    "now": "friction",
    "ev": "No read of CFBundleShortVersionString in Sources/.",
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
    "ev": "live-settings: pmset -g assertions listed \"tokenpanda: a Claude Code session is open\" for the throwaway run; Controller.swift:254-265.",
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
    "ev": "live-settings tab2 showed \"awake  1 session open\".",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "A closed lid on battery still sleeps the Mac; the README says so, the row does not.",
    "screens": [
     "pop-settings-awake"
    ],
    "do": "Read the README.",
    "now": "friction",
    "ev": "README.md, What it shows.",
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
    "text": "Turn on Reopen sessions after a restart: the app keeps the open sessions in restore.json, readable only by you.",
    "screens": [
     "pop-settings-restore"
    ],
    "do": "Tick it.",
    "now": "works",
    "ev": "live-settings: restore.json written with mode 0600, entries id, folder, lastSeen.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "After a restart, one notification: \"3 Claude Code sessions were open before the restart\", with Reopen.",
    "screens": [
     "notif-reopen"
    ],
    "do": "Click Reopen.",
    "now": "works",
    "ev": "Controller.swift:318-337; RestoreTests.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "Reopen opens each session in Terminal with claude --resume, and --remote-control where it had it.",
    "screens": [
     "term-reopen"
    ],
    "do": "Work on.",
    "now": "works",
    "ev": "pgrep on this Mac: nine tokenpanda-reopen .command scripts running under zsh -l; Restore.swift:82-88.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "With notifications off the offer never comes and the Reopen row does not say why.",
    "screens": [
     "desk-reopen-denied"
    ],
    "do": "Nothing happens.",
    "now": "friction",
    "ev": "Notifier.swift:53-54; Grammar.swift:279-285 (the note sits under the Nudge row only).",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "Turning it off deletes restore.json.",
    "screens": [
     "pop-settings"
    ],
    "do": "Untick it.",
    "now": "works",
    "ev": "Controller.swift:468-471.",
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
    "ev": "spec 16; privacy 5.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "brew upgrade --cask tokenpanda quits and replaces the app.",
    "screens": [
     "term-brew-upgrade"
    ],
    "do": "Run it.",
    "now": "works",
    "ev": "Casks/tokenpanda.rb (uninstall quit).",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "A new ad hoc build can bring back the Open Anyway steps, and the app has no version line to confirm what runs.",
    "screens": [
     "term-brew-upgrade",
     "gk-blocked"
    ],
    "do": "Open Anyway again.",
    "now": "friction",
    "ev": "codesign adhoc; no version in Sources/. Not walked across two releases in this run (left out 1).",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "Settings, the hook, limits.json and weeks.json survive the update; Open at login keeps working.",
    "screens": [
     "pop-live"
    ],
    "do": "Nothing.",
    "now": "works",
    "ev": "Application Support and preferences are outside the bundle; SMAppService.mainApp.",
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
    "ev": "hookrun own-statusline: command, padding back as before; Hook.swift:141-161.",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "If there was no settings.json before, an empty \"{}\" file stays.",
    "screens": [
     "editor-empty"
    ],
    "do": "Delete it by hand.",
    "now": "friction",
    "ev": "hookrun no-settings: settings.json after uninstall is {}.",
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
    "text": "Moved to the Bin without Remove first: the hook keeps running from Application Support and leaves one session file per session that nothing deletes.",
    "screens": [
     "term-leftover"
    ],
    "do": "Find the folder.",
    "now": "friction",
    "ev": "Hook.swift:59-67; FeedReader.swift:92-95 is the only deleter.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "brew uninstall --zap deletes the folder that holds hook.sh while settings.json still points at it: the Claude Code status line goes blank, including the status line the user had before.",
    "screens": [
     "term-zap"
    ],
    "do": "Repair settings.json by hand.",
    "now": "broken",
    "ev": "Casks/tokenpanda.rb:21-24 zap; HookScript chains PREV inside hook.sh (Hook.swift:25); the caveat asks to Remove first, nothing enforces it.",
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
    "ev": "privacy 9.",
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
    "text": "VoiceOver on the item reads the state in words: \"Weekly 28% used, ahead, resets sun 17:00\".",
    "screens": [
     "desk-ultra"
    ],
    "do": "Listen.",
    "now": "works",
    "ev": "live and states item labels; ScreenBuilder.swift:327-331. The weekday is lower case and abbreviated; the style guide says \"Sunday\".",
    "walk": "start"
   },
   {
    "n": "2",
    "text": "Inside the popover VoiceOver reads each line as text, so the figures are heard.",
    "screens": [
     "pop-live"
    ],
    "do": "Read with VO keys.",
    "now": "works",
    "ev": "LineView.swift:90-97.",
    "walk": "click"
   },
   {
    "n": "3",
    "text": "The Install button, the tabs, the section switch and every checkbox are static text to VoiceOver: no role, no state, no press. A VoiceOver user cannot set up the feed or change a setting.",
    "screens": [
     "pop-voiceover"
    ],
    "do": "Try to press Install.",
    "now": "broken",
    "ev": "LineView.swift:95 role staticText for every line; style guide 9 promises button, tab list and checkbox roles.",
    "walk": "click"
   },
   {
    "n": "4",
    "text": "From the keyboard only Tab, Esc, m, p, s and Command Q work; no row takes focus and Space does nothing, so settings need a pointer.",
    "screens": [
     "pop-keyboard"
    ],
    "do": "Try Space on a row.",
    "now": "broken",
    "ev": "Controller.swift:529-541; style guide 9 promises focus and Space.",
    "walk": "click"
   },
   {
    "n": "5",
    "text": "The key hints are #505050 on the glass, about 2.1 to 1.",
    "screens": [
     "pop-keyboard"
    ],
    "do": "Squint.",
    "now": "friction",
    "ev": "Tokens.swift:19; style guide 9 measures 2.0 to 2.3.",
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
    "ev": "Controller.swift:98.",
    "walk": "click"
   }
  ]
 }
];
window.TITLES = {
 "desk": "Menu bar, the item: panda and the weekly percentage, over pace in semibold",
 "pop-live": "Claude tab, live: weekly over pace, 5h ahead (Max or Pro)",
 "pop-session-tip": "Claude tab, hover on a session figure: list price, lines, effort",
 "pop-projects": "Claude tab, tokens by project, 7 days (p)",
 "pop-sessions": "Claude tab, tokens by session, today (s)",
 "pop-nochip": "Claude tab with List price equivalent off: no price chip",
 "desk-flicker-a": "Menu bar with ten sessions open: 28% now",
 "desk-flicker-b": "Menu bar two seconds later: 12%",
 "pop-flicker-a": "Claude tab, the weekly at 28%",
 "pop-flicker-b": "Claude tab two seconds later: the weekly at 12%, Ahead 15% by reset",
 "desk-nofeed": "Menu bar, first launch: the panda alone, dimmed",
 "pop-nohook": "Claude tab, first open: Install the status line hook",
 "pop-nohook-chained": "Claude tab, first open with a status line of your own: kept and chained",
 "pop-install-failed": "Claude tab after Install with an unreadable settings.json: nothing changes here",
 "pop-nosession": "Claude tab, hook installed, no session yet",
 "pop-firstcall": "Claude tab during the first call: sessions open, windows still say open Claude Code once",
 "desk-ultra": "Menu bar today, Ultra: 28%, nothing about the 5h window",
 "pop-ultra-today": "Claude tab today, Ultra: the 5h window reads Reset 00:10 no session since, under Usage live",
 "pop-ultra-fixed": "Proposed fix, not built: no 5h window in the feed, so no 5h section",
 "pop-ultra-evening": "30 Oct, 21:30, Ultra: the 5h window frozen at 63% with a live countdown and pace",
 "pop-ultra-late": "30 Oct, 23:58: the frozen 5h window drifts to Ahead, 185% an hour left",
 "desk-five-limit": "Menu bar, Ultra, the 5h window was at 100% when the feed stopped: - - eyes",
 "pop-ultra-new": "Claude tab, a new Ultra user: 5h window, empty bar, not in the last feed, for good",
 "pop-live-max": "Claude tab, Max or Pro today: both windows, as before",
 "pop-week-near": "Claude tab, 40 minutes before the weekly reset",
 "pop-week-rolled": "Claude tab, weekly reset passed with no session since",
 "pop-week-rolled-live": "Claude tab, weekly reset passed while idle sessions feed: no session since, under Usage live",
 "pop-week-new": "Claude tab, the new week arrived: 1% used, last week kept",
 "desk-weekly-limit": "Menu bar, weekly limit reached: x x eyes until the reset",
 "pop-asof": "Claude tab, last session closed 20 minutes ago: Usage as of, pace still computed",
 "pop-stale": "Claude tab, stale: no session for over an hour",
 "desk-stale": "Menu bar, stale: the item at half strength",
 "pop-nolimits": "Claude tab, an account without plan limits (API key)",
 "pop-notranscripts": "Claude tab, no transcripts folder",
 "pop-mac": "Mac tab: CPU, GPU, memory, battery, processes",
 "pop-mac-ultra": "Mac tab (today)",
 "pop-mac-warning": "Mac tab with the warning: dot on the tab, pressure warn",
 "pop-live-warn": "Claude tab with the Mac warning dot",
 "pop-mac-health": "Mac tab, battery health unknown: health n/a",
 "desk-warning": "Menu bar with the Mac warning sign",
 "desk-mac": "Menu bar with Mac figures in the bar: CPU 9%",
 "desk-quit": "Menu bar after Quit: the item is gone",
 "pop-settings": "Settings tab",
 "pop-settings-login": "Settings, Open at login on: macOS lists it in Login Items",
 "pop-settings-approval": "Settings, Open at login waits for approval: click to allow it in Login Items",
 "pop-settings-awake": "Settings, Keep the Mac awake on, one session working",
 "pop-settings-awake-open": "Settings, also while a session waits: awake  1 session open",
 "pop-settings-restore": "Settings, Reopen sessions after a restart on",
 "pop-settings-nohook": "Settings, hook not installed: the second line runs past the edge",
 "pop-settings-denied": "Settings, notifications denied: the note is cut and does not open System Settings",
 "pop-settings-error": "Settings, the install error under the row",
 "pop-voiceover": "VoiceOver in the popover: every line is static text, the controls cannot be pressed",
 "pop-keyboard": "Keyboard in the popover: Tab switches tabs, nothing takes focus, Space does nothing",
 "browser-release": "Releases page: tokenpanda-0.1.7.zip and its .sha256",
 "term-shasum": "Terminal: shasum checks the zip, OK",
 "term-brew": "Terminal: brew install from the tap, the caveats",
 "finder-apps": "Finder, Applications: tokenpanda.app",
 "gk-blocked": "macOS blocks the first open: Apple could not verify tokenpanda",
 "gk-settings": "System Settings, Privacy & Security: Open Anyway, at the bottom",
 "gk-confirm": "The warning again: Open",
 "notif-permission": "First launch: the notification permission prompt, before anything is explained",
 "desk-hidden": "macOS 26 and later: the item is not shown until allowed under Menu Bar",
 "sys-menubar": "System Settings, Menu Bar: allow tokenpanda",
 "sys-loginitems": "System Settings, General, Login Items: tokenpanda listed",
 "editor-after": "~/.claude/settings.json after Install: one statusLine entry, the rest kept",
 "editor-broken": "~/.claude/settings.json that is not valid JSON (a trailing comma)",
 "editor-restored": "~/.claude/settings.json after Remove: your statusLine back exactly",
 "editor-empty": "~/.claude/settings.json after Remove when there was none: an empty object stays",
 "term-claude": "Terminal: a Claude Code session, the first reply",
 "notif-weekly": "Nudge: Weekly at 80%",
 "notif-five": "Nudge: 5h window ends in 15 min (Max or Pro)",
 "notif-five-false": "Nudge for a 5h window Ultra no longer has (30 Oct, 23:55)",
 "notif-reopen": "After a restart: n Claude Code sessions were open before the restart, Reopen",
 "desk-reopen-denied": "After a restart with notifications off: no offer, no word",
 "term-reopen": "Terminal: each session resumed, with Remote Control where it had it",
 "term-pmset": "Terminal: pmset lists the tokenpanda assertion",
 "term-brew-upgrade": "Terminal: brew upgrade, then Open Anyway again",
 "finder-bin": "Finder: tokenpanda.app moved to the Bin",
 "term-leftover": "After the app is gone: the hook keeps writing, files pile up",
 "term-zap": "brew uninstall --zap: the hook script is gone, so is your own status line"
};
