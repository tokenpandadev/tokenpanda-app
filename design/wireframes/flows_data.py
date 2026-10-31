"""The user flows of tokenpanda as built, each step with its screens, what the user does, and what the
flow test found in the real app (works, friction, broken) with the evidence.

Walked on 31.10.2026 against main at 4ca4160 (0.1.7), debug build with the Command Line Tools.
Four kinds of evidence, named in each step:
  live-<name>: the real debug binary run with CFFIXED_USER_HOME on a throwaway home folder and a crafted
               status line feed, its own --live-snapshot flag rendering the three tabs and the item;
  fixtures/<name>: the binary's --snapshot flag over Sources/UI/Fixtures.swift;
  states/<name>: crafted inputs rendered by the app's own ScreenBuilder, Grammar and SnapshotWriter
               (a harness linked against the debug objects, no app code changed);
  hookrun: the real Hook code (install, the hook script run with a sample feed, uninstall) on throwaway folders;
plus the real data folder of the running 0.1.7 on this Mac, read only, and file:line in the repo.
Screenshots were taken in a scratch folder and are not kept in the repository.
"""
import json
import re


def S(text, screens, do, now, ev):
    return dict(text=text, screens=screens if isinstance(screens, list) else [screens], do=do, now=now, ev=ev)


FLOWS = [
 dict(id='01', name='Download and first open', steps=[
  S('The releases page offers tokenpanda-0.1.7.zip and tokenpanda-0.1.7.zip.sha256.', 'browser-release', 'Download both.', 'works', 'README.md, Install; build/release-notes-0.1.7.md.'),
  S('In Terminal, shasum -a 256 -c checks the zip and prints OK; unzip and move tokenpanda.app to Applications.', 'term-shasum', 'Run the two lines.', 'works', 'README.md, Install; build/tokenpanda-0.1.7.zip.sha256.'),
  S('With Homebrew instead: brew install tokenpandadev/tap/tokenpanda, and the caveats say Open Anyway and Remove before uninstalling.', 'term-brew', 'Read the caveats.', 'works', 'Casks/tokenpanda.rb:26-33.'),
  S('Double click in Applications: macOS refuses, "Apple could not verify tokenpanda is free of malware".', ['finder-apps', 'gk-blocked'], 'Click Done.', 'friction', 'codesign: Signature=adhoc, TeamIdentifier not set; spctl -a -t exec: rejected. By design for now (spec 17, path one).'),
  S('System Settings, Privacy and Security, scroll to the bottom, Open Anyway.', 'gk-settings', 'Find the button.', 'friction', 'README.md, Install; spec 17. Not walked on a clean account in this run (left out 1).'),
  S('The warning comes back once; Open Anyway starts the app.', 'gk-confirm', 'Click Open Anyway.', 'works', 'README.md, Install.'),
  S('The first thing the app shows is the notification permission prompt: nudges are on by default and the app asks at launch, before the user has seen it or knows what a nudge is.', 'notif-permission', 'Allow or not, without context.', 'friction', 'Controller.swift:124; Settings.swift:21 (nudges default true); Notifier.swift:40-51.'),
  S('The menu bar shows the panda alone at half strength: no figures yet. No window, no Dock icon.', 'desk-nofeed', 'Click the panda.', 'works', 'fixtures/item-nofeed; ScreenBuilder.swift:315-319; LSUIElement in scripts/build-app.sh.'),
  S('On macOS 26 and later the item stays hidden until it is allowed in System Settings, Menu Bar; a crowded menu bar behind the notch hides it too, and nothing else says the app runs.', ['desk-hidden', 'sys-menubar'], 'Allow it under Menu Bar.', 'friction', 'README.md, Install; spec 19, by hand.'),
 ]),
 dict(id='02', name='Set up the feed', steps=[
  S('The Claude tab says what is needed: "needs Claude Code\'s status line feed, one statusLine entry in ~/.claude/settings.json", and one button, Install the status line hook.', 'pop-nohook', 'Read, click Install.', 'works', 'live-nohook tab0; Grammar.swift:100-110.'),
  S('With a status line of your own it says "your current status line is kept and chained".', 'pop-nohook-chained', 'Click Install.', 'works', 'Grammar.swift:105; hookrun own-statusline: the hook printed MINE, the user\'s own output.'),
  S('Install writes one statusLine entry with refreshInterval 5 and keeps every other key; an existing entry keeps its padding and refreshInterval and is chained.', 'editor-after', 'Nothing to do.', 'works', 'hookrun no-settings, no-statusline, own-statusline; Hook.swift:108-136.'),
  S('The windows then read "no session yet  open Claude Code once".', 'pop-nosession', 'Start Claude Code.', 'works', 'fixtures/claude-nosession; Grammar.swift:111-113.'),
  S('During the first call the open sessions show "waiting for the first reply" while both windows still say "open Claude Code once".', ['term-claude', 'pop-firstcall'], 'Send a first prompt.', 'friction', 'states/claude-first-call; Grammar.swift:112; ScreenBuilder.swift:93-95.'),
  S('After the first reply: header Usage live, both windows with pace, the session with its context bar.', 'pop-live', 'Read the figures.', 'works', 'live-max tab0; fixtures/claude-overpace.'),
  S('If settings.json is not valid JSON, Install on the Claude tab changes nothing on screen; the error is drawn only on the Settings tab, cut at the width, without its reason.', ['editor-broken', 'pop-install-failed', 'pop-settings-error'], 'Click Install, wonder, open Settings.', 'broken', 'hookrun broken-json: "cannot read settings.json: settings.json is not a JSON object"; Grammar.swift:100-110 draws no error; ScreenBuilder.swift:284-285 passes hookError to Settings only; states/settings-errors.'),
  S('In Settings the row says "Install the status line entry" (the Claude tab says hook), and its second line runs past the popover edge: "...~/.claude/settings.js".', 'pop-settings-nohook', 'Click it.', 'friction', 'live-settings tab2 and states/settings-nohook-denied: the line is cut; Grammar.swift:318 (51 cells in a 47 cell popover).'),
 ]),
 dict(id='03', name='Read the panel', steps=[
  S('The item shows the panda and the weekly percentage; semibold when over pace.', 'desk', 'Glance.', 'works', 'fixtures/closed; ItemImage.swift:54-99.'),
  S('Weekly: bar with the tick at the elapsed share, "Resets Sun 18:00  in 3d 3h", "Over pace  limit Sun 01:20 at this rate", "0.5% an hour left". Coral past the tick only when over pace.', 'pop-live', 'Read the weekly.', 'works', 'fixtures/claude-overpace; spec 7 worked example; PaceTests.'),
  S('5h window, the same five lines, for plans that have it.', 'pop-live', 'Read the 5h window.', 'works', 'fixtures/claude-overpace; live-max tab0.'),
  S('Open sessions: project, model, context bar and "405.6k of 1M  41%"; hovering the figure shows list price, lines added and removed, effort.', 'pop-session-tip', 'Hover the figure.', 'friction', 'The tooltip text is 66 characters plus padding (68 cells) in a 50 cell view, drawn from the left edge and clipped by the view, so it ends at "9 remo" and the effort is never seen: LineView.swift:203-213, ScreenBuilder.swift:106-107. Computed from the code, hover not possible in this run.'),
  S('Tokens by model, project or session with the price chip and the subagent share; click the switch or press m, p, s.', ['pop-projects', 'pop-sessions'], 'Press p, then s.', 'works', 'fixtures/claude-projects, claude-sessions; Controller.swift:539.'),
  S('Week over week: four rows, the hit week marked with the time it hit.', 'pop-live', 'Read the rows.', 'works', 'fixtures/claude-overpace.'),
  S('With several sessions open the weekly figure jumps every few seconds between the values each session last saw: 28%, 12%, 28%, 18%, 11% within 30 s, in the bar, the item, the projection and the allowance.', ['desk-flicker-a', 'desk-flicker-b', 'pop-flicker-a', 'pop-flicker-b'], 'Watch the item.', 'broken', 'Real data folder, sampled 11:11:16 to 11:11:45: limits.json used 12, 28, 18, 11 as the newest session file changed; ten session files carried 9 to 28 for the same resets_at. FeedReader.swift:96-101 takes the newest file; idle sessions rewrite their cached figure every 5 s (refreshInterval, Hook.swift:68).'),
  S('Esc closes, Tab and Shift Tab switch tabs, Command Q quits.', 'pop-live', 'Press Tab.', 'works', 'Controller.swift:529-541.'),
 ]),
 dict(id='04', name='Nudges', steps=[
  S('Nudges are on by default; permission is asked at launch.', 'notif-permission', 'Allow.', 'friction', 'Controller.swift:124 (see 01.7).'),
  S('The weekly passes 80% while a session feeds: "Weekly at 80%" with the countdown and the landing time, once per weekly window.', 'notif-weekly', 'Read the banner.', 'works', 'Controller.swift:413-419; PaceModel.nudgeBody, PaceTests. Notifications need the app bundle, so not posted by the debug binary (left out 3).'),
  S('15 minutes before the 5h reset: "5h window ends in 15 min" with the percentage, once per window.', 'notif-five', 'Read the banner.', 'works', 'Controller.swift:420-424.'),
  S('Ultra: the frozen 5h record can still pass that test once, and announce the end of a window the plan no longer has.', 'notif-five-false', 'Ignore it.', 'broken', 'Controller.swift:420-424 reads l.windows["five_hour"], kept by FeedReader.swift:23-37; the real record resets_at is 31 Oct 00:10. Read from the code, not seen on screen.'),
  S('Notifications denied: the Nudge row says "Notifications are off for this app in System" and stops at the edge; it does not open System Settings.', 'pop-settings-denied', 'Find the setting yourself.', 'friction', 'states/settings-nohook-denied; Grammar.swift:279; Notifier.swift:30.'),
  S('No nudge comes from stale figures: an hour without a session and the nudges wait.', 'pop-stale', 'Nothing.', 'works', 'Controller.swift:412.'),
 ]),
 dict(id='05', name='The 5 hour window removed for Ultra (30 Oct 2026)', steps=[
  S('30 Oct, evening: the feed stops sending five_hour for verified Ultra accounts. The app keeps the last figure (63% in this example) and draws it as live: countdown running, tick moving, "Over pace  limit 22:50 at this rate".', 'pop-ultra-evening', 'Believe it.', 'broken', 'live-ultra-day1: after 50 s of feeds without five_hour, limits.json still held five_hour used 63 and the tab showed it with pace lines. FeedReader.swift:23-37 (apply only touches keys present); ScreenBuilder.swift:60-78 (asOf is shared, so it is never stale).'),
  S('Near the stored reset the same 63% reads "Ahead  66% by reset", "185% an hour left".', 'pop-ultra-late', 'Read nonsense.', 'broken', 'states/ultra-late.'),
  S('If the 5h window was at 100% when the feed stopped, the panda shows - - eyes and VoiceOver says "5h limit reached" until the old reset.', 'desk-five-limit', 'Think you are blocked.', 'broken', 'states/ultra-five-at-limit: label "... 5h limit reached"; ScreenBuilder.swift:292-299.'),
  S('Around the old reset a "5h window ends in 15 min" nudge can fire for it.', 'notif-five-false', 'Ignore it.', 'broken', 'Controller.swift:420-424 (see 04.4).'),
  S('Today, 31 Oct: the 5h window is an empty bar with "Reset 00:10  no session since", under "Usage live" and a listed open session, and it stays that way for good. The smallest fix drops the window when a fresh feed comes without it.', ['pop-ultra-today', 'pop-ultra-fixed'], 'Read a contradiction.', 'broken', 'Real limits.json: five_hour used 1, resetsAt 31 Oct 00:10, asOf 11:11 today; all ten live session files carry seven_day only. live-ultra-today tab0 shows exactly this. ScreenBuilder.swift:62 (.absent is never reached once a record exists), :65-66 (resetPassed).'),
  S('A new Ultra user, whose feed never had five_hour, sees an empty 5h bar with "not in the last feed" for good.', 'pop-ultra-new', 'Wonder what it means.', 'friction', 'states/ultra-new; ScreenBuilder.swift:62.'),
  S('Max and Pro feeds still carry five_hour; their panel is unchanged.', 'pop-live-max', 'Nothing.', 'works', 'live-max tab0; states/max-both.'),
 ]),
 dict(id='06', name='Weekly reset', steps=[
  S('Before the reset the countdown reads in hours and minutes.', 'pop-week-near', 'Plan the last hour.', 'works', 'PaceModel.countdown; PaceTests.'),
  S('The reset passes with no session open: the weekly reads "Reset Sun 17:00  no session since", the item dims, the week row says "last seen 91%".', 'pop-week-rolled', 'Open Claude Code.', 'works', 'fixtures/claude-resetpassed; ScreenBuilder.swift:176-178.'),
  S('The reset passes while idle sessions feed: Claude Code drops the passed window, the app keeps it, and the weekly reads "no session since" under "Usage live" with sessions listed, until the next reply.', 'pop-week-rolled-live', 'Send a prompt.', 'friction', 'states/weekly-rolled-live; Claude Code docs as quoted in spec 3 ("Claude Code drops a window once its resets_at time passes"); real weeks.json: the 25 Oct week was last updated 22 min after its reset, so the old record outlived it.'),
  S('The next reply brings the new week: "1% used", "On pace", a new row in week over week.', 'pop-week-new', 'Read the new week.', 'works', 'states/weekly-new; Feed/Weeks.swift:22-32.'),
  S('Week over week keeps the last value seen per week; with several sessions that is whichever session wrote last, often an idle one with a lower figure.', 'pop-flicker-b', 'Trust the history.', 'broken', 'Real weeks.json: current week lastUsed 12 while the account is at 28; Controller.swift:197-201 applies whatever limits holds.'),
  S('At 100% the panda shows x x until the reset.', 'desk-weekly-limit', 'Wait for the reset.', 'works', 'fixtures/item-weekly-limit; ItemImage.swift:32-48.'),
 ]),
 dict(id='07', name='Stale or missing feed', steps=[
  S('The last session closes: its row leaves after 60 s and the header says "Usage as of 13:05, last Claude Code session"; pace is still computed for an hour.', 'pop-asof', 'Read the time.', 'works', 'FeedTests openSessionsTiming; ScreenBuilder.swift:275-279.'),
  S('After an hour: the stale form, dim bars, "as of 13:05", the note that limits are shared, the item at half strength.', ['pop-stale', 'desk-stale'], 'Open Claude Code to refresh.', 'works', 'fixtures/claude-stale, item-stale.'),
  S('Use on the web or in the Claude app moves the limits, but the app sees it only when a Claude Code session feeds; the stale note says so.', 'pop-stale', 'Keep it in mind.', 'friction', 'README.md, By the rules; spec 3. By design: no network.'),
  S('An account without plan limits: "this account has no plan limits to show".', 'pop-nolimits', 'Nothing.', 'works', 'fixtures/claude-nolimits.'),
  S('No transcripts folder: "No transcripts in ~/.claude/projects" in the token section; a read error shows its own message.', 'pop-notranscripts', 'Nothing.', 'works', 'states/claude-no-transcripts, claude-transcripts-denied.'),
  S('The statusLine entry removed by hand: the app notices the settings.json change on the next tick and offers Install again.', 'pop-nohook', 'Install again or not.', 'works', 'Controller.swift:196; Hook.swift:75-81.'),
 ]),
 dict(id='08', name='The Mac tab', steps=[
  S('Click Mac or press Tab: CPU, GPU, the memory grid with pressure and swap, battery, the busiest processes.', 'pop-mac', 'Read.', 'works', 'fixtures/mac; live-max tab1.'),
  S('Under memory pressure or a process over 80% CPU for a minute, the Mac tab gets a dot and the item a warning sign.', ['desk-warning', 'pop-mac-warning'], 'Open the Mac tab.', 'works', 'fixtures/mac-warning, item-warning; live runs on this Mac showed the dot and the sign.'),
  S('Battery health unknown: "health n/a", never a dash.', 'pop-mac-health', 'Nothing.', 'works', 'fixtures/mac-health-na.'),
  S('Mac figures in the bar appends " CPU 9%" to the item.', 'desk-mac', 'Tick it in Settings.', 'works', 'ScreenBuilder.swift:314.'),
 ]),
 dict(id='09', name='Settings', steps=[
  S('Settings: Open at login, Mac figures in the bar, nudges, list price, keep awake, reopen sessions, the status line row, the privacy sentence, Quit.', 'pop-settings', 'Read the rows.', 'works', 'fixtures/settings; live-settings tab2.'),
  S('Open at login: the box shows what macOS says; while macOS waits for approval a dim line opens Login Items.', ['pop-settings-login', 'pop-settings-approval', 'sys-loginitems'], 'Tick it.', 'works', 'Controller.swift:283-304; spec 10, seen on the build Mac. Not clicked in this run (left out 2).'),
  S('List price equivalent off: the price chip goes.', 'pop-nochip', 'Untick it.', 'works', 'ScreenBuilder.swift:136-140.'),
  S('Quit and Command Q end the app; the item goes.', 'desk-quit', 'Click Quit.', 'works', 'Grammar.swift:291; Controller.swift:531.'),
  S('Nowhere in the app is the version: no About, no line in Settings.', 'pop-settings', 'Look for the version.', 'friction', 'No read of CFBundleShortVersionString in Sources/.'),
 ]),
 dict(id='10', name='Keep the Mac awake', steps=[
  S('Keep the Mac awake while Claude works: while a session\'s figures move, "awake  1 session working" and one power assertion.', 'pop-settings-awake', 'Tick it.', 'works', 'live-settings: pmset -g assertions listed "tokenpanda: a Claude Code session is open" for the throwaway run; Controller.swift:254-265.'),
  S('Also while a session waits for you: idle sessions count too, "awake  1 session open".', ['pop-settings-awake-open', 'term-pmset'], 'Tick the second row.', 'works', 'live-settings tab2 showed "awake  1 session open".'),
  S('A closed lid on battery still sleeps the Mac; the README says so, the row does not.', 'pop-settings-awake', 'Read the README.', 'friction', 'README.md, What it shows.'),
 ]),
 dict(id='11', name='Reopen sessions after a restart', steps=[
  S('Turn on Reopen sessions after a restart: the app keeps the open sessions in restore.json, readable only by you.', 'pop-settings-restore', 'Tick it.', 'works', 'live-settings: restore.json written with mode 0600, entries id, folder, lastSeen.'),
  S('After a restart, one notification: "3 Claude Code sessions were open before the restart", with Reopen.', 'notif-reopen', 'Click Reopen.', 'works', 'Controller.swift:318-337; RestoreTests.'),
  S('Reopen opens each session in Terminal with claude --resume, and --remote-control where it had it.', 'term-reopen', 'Work on.', 'works', 'pgrep on this Mac: nine tokenpanda-reopen .command scripts running under zsh -l; Restore.swift:82-88.'),
  S('With notifications off the offer never comes and the Reopen row does not say why.', 'desk-reopen-denied', 'Nothing happens.', 'friction', 'Notifier.swift:53-54; Grammar.swift:279-285 (the note sits under the Nudge row only).'),
  S('Turning it off deletes restore.json.', 'pop-settings', 'Untick it.', 'works', 'Controller.swift:468-471.'),
 ]),
 dict(id='12', name='Update', steps=[
  S('The app never checks for updates (no network); a new version is found on the releases page or with brew outdated.', 'browser-release', 'Look on GitHub.', 'friction', 'spec 16; privacy 5.'),
  S('brew upgrade --cask tokenpanda quits and replaces the app.', 'term-brew-upgrade', 'Run it.', 'works', 'Casks/tokenpanda.rb (uninstall quit).'),
  S('A new ad hoc build can bring back the Open Anyway steps, and the app has no version line to confirm what runs.', ['term-brew-upgrade', 'gk-blocked'], 'Open Anyway again.', 'friction', 'codesign adhoc; no version in Sources/. Not walked across two releases in this run (left out 1).'),
  S('Settings, the hook, limits.json and weeks.json survive the update; Open at login keeps working.', 'pop-live', 'Nothing.', 'works', 'Application Support and preferences are outside the bundle; SMAppService.mainApp.'),
 ]),
 dict(id='13', name='Uninstall', steps=[
  S('Settings, Remove the status line entry puts the previous statusLine back exactly, or removes the key.', 'editor-restored', 'Click it.', 'works', 'hookrun own-statusline: command, padding back as before; Hook.swift:141-161.'),
  S('If there was no settings.json before, an empty "{}" file stays.', 'editor-empty', 'Delete it by hand.', 'friction', 'hookrun no-settings: settings.json after uninstall is {}.'),
  S('Quit and move the app to the Bin.', 'finder-bin', 'Drag to the Bin.', 'works', 'privacy 9.'),
  S('Moved to the Bin without Remove first: the hook keeps running from Application Support and leaves one session file per session that nothing deletes.', 'term-leftover', 'Find the folder.', 'friction', 'Hook.swift:59-67; FeedReader.swift:92-95 is the only deleter.'),
  S('brew uninstall --zap deletes the folder that holds hook.sh while settings.json still points at it: the Claude Code status line goes blank, including the status line the user had before.', 'term-zap', 'Repair settings.json by hand.', 'broken', 'Casks/tokenpanda.rb:21-24 zap; HookScript chains PREV inside hook.sh (Hook.swift:25); the caveat asks to Remove first, nothing enforces it.'),
  S('Delete Application Support and the preferences file by hand; nothing else was created.', 'finder-bin', 'Delete two paths.', 'works', 'privacy 9.'),
 ]),
 dict(id='14', name='VoiceOver and the keyboard', steps=[
  S('VoiceOver on the item reads the state in words: "Weekly 28% used, ahead, resets sun 17:00".', 'desk-ultra', 'Listen.', 'works', 'live and states item labels; ScreenBuilder.swift:327-331. The weekday is lower case and abbreviated; the style guide says "Sunday".'),
  S('Inside the popover VoiceOver reads each line as text, so the figures are heard.', 'pop-live', 'Read with VO keys.', 'works', 'LineView.swift:90-97.'),
  S('The Install button, the tabs, the section switch and every checkbox are static text to VoiceOver: no role, no state, no press. A VoiceOver user cannot set up the feed or change a setting.', 'pop-voiceover', 'Try to press Install.', 'broken', 'LineView.swift:95 role staticText for every line; style guide 9 promises button, tab list and checkbox roles.'),
  S('From the keyboard only Tab, Esc, m, p, s and Command Q work; no row takes focus and Space does nothing, so settings need a pointer.', 'pop-keyboard', 'Try Space on a row.', 'broken', 'Controller.swift:529-541; style guide 9 promises focus and Space.'),
  S('The key hints are #505050 on the glass, about 2.1 to 1.', 'pop-keyboard', 'Squint.', 'friction', 'Tokens.swift:19; style guide 9 measures 2.0 to 2.3.'),
  S('Reduce motion: the popover opens without animation.', 'pop-live', 'Nothing.', 'works', 'Controller.swift:98.'),
 ]),
]


GAPS = [
 dict(t='The 5h window shows a dead figure for Ultra accounts', steps='05.1 to 05.5, 04.4',
      why='Since 30 Oct every verified Ultra user sees a 5h figure that is not real: first a frozen percentage with live pace and possibly - - eyes and a nudge, then for good "Reset 00:10  no session since" under "Usage live". The panel contradicts itself on its main screen.',
      fix='Limits.apply (FeedReader.swift:23-38) drops every stored window whose key is missing from the feed it applies; apply only runs for a snapshot that carries rate_limits, so the first call of a session still changes nothing. Then limitsView (ScreenBuilder.swift:83) draws the fixed keys only while their record exists, with the weekly placeholder kept. Max and Pro feeds carry five_hour and see no change. Two tests: a later feed without five_hour removes it; the first call without rate_limits keeps it.',
      size='about 6 lines and 2 tests'),
 dict(t='The weekly figure jumps between sessions', steps='03.7, 06.5',
      why='With several Claude Code sessions open, which is the normal case for this user, the item and the bar change every few seconds between 9% and 28%, and the week over week history records whichever value was last. The one number the app exists for is unreliable.',
      fix='In FeedReader.scan (FeedReader.swift:89-106) merge the rate_limits of every snapshot read in the scan instead of taking the newest file: per key, the latest resets_at, and for that reset the highest used_percentage (usage inside a window never goes down). Keep limits.asOf at the newest write. One test with two sessions writing 12 and 28.',
      size='about 12 lines and 1 test'),
 dict(t='VoiceOver and the keyboard cannot use any control', steps='14.3, 14.4',
      why='Install, the tabs, the section switch and every setting are drawn text with no role or action, and nothing takes keyboard focus. A VoiceOver or keyboard user cannot set up the feed at all. The style guide already specifies the roles.',
      fix='In LineView.rebuildHits give lines with an action an element of role button or checkbox (with its value) and an accessibilityPerformPress that calls onAction; make those elements the key view loop and draw the focus ring the style guide names; Space presses the focused one.',
      size='medium, LineView.swift and Controller.handleKey'),
 dict(t='Install from the Claude tab fails silently', steps='02.7',
      why='A settings.json the JSON reader refuses is common after a hand edit. The click does nothing visible where it was made, and the Settings error is cut before its reason.',
      fix='Pass hookError into LimitsView.noHook and draw it under the button, wrapped over two lines instead of cut (Grammar.swift:100-110, ScreenBuilder.swift:91).',
      size='small'),
 dict(t='Lines run past the popover edge', steps='02.8, 04.5',
      why='"one statusLine entry in ~/.claude/settings.json" and "Notifications are off for this app in System Settings" are cut mid word; the second is the only hint about why nudges never come.',
      fix='Shorten to fit 42 cells at the 5 cell indent ("one entry in ~/.claude/settings.json", "Notifications are off in System Settings") and make the notification note open System Settings, Notifications on a click.',
      size='two strings and one action'),
 dict(t='After a weekly reset the weekly reads "no session since" while sessions are open', steps='06.3',
      why='For the minutes between the reset and the next reply the main figure says no session ran, under "Usage live".',
      fix='The same drop as gap 1 covers it: when the feed comes without seven_day the stored one goes, and the weekly shows its placeholder until the new week arrives. Better copy for that placeholder: "new week starts with the next reply".',
      size='covered by gap 1, plus one string'),
 dict(t='brew uninstall --zap leaves Claude Code pointing at a deleted script', steps='13.5, 13.4',
      why='The user\'s own status line, chained inside the hook, disappears with the zap; without Remove first, session files pile up for ever.',
      fix='Make the cask zap safe: an uninstall script stanza that runs the app\'s own remove (a release build flag such as --remove-status-line that calls Hook.uninstall) before trashing. In the app, nothing else is needed.',
      size='small, a flag in main.swift and the cask'),
 dict(t='The first call reads "open Claude Code once" while sessions are open', steps='02.5',
      why='Right after setup, the user does what the screen says and the screen keeps saying it until the first reply.',
      fix='When sessions are open and none has replied yet, draw "waiting for the first reply" in both windows (ScreenBuilder.limitsView has the facts).',
      size='one condition, one string'),
 dict(t='The notification prompt comes at launch, out of context', steps='01.7, 04.1',
      why='It is the first thing a new user sees, before the popover explains anything.',
      fix='Ask when the user first opens the popover after the feed works, or on the first nudge that would fire; keep asking at once when the user ticks the row.',
      size='small, Controller.swift:124'),
 dict(t='No version anywhere in the app', steps='09.5, 12.3',
      why='A user cannot tell which build runs after an update or for a bug report.',
      fix='Add the version to the privacy line in Settings, "tokenpanda 0.1.7  no network calls", from CFBundleShortVersionString.',
      size='one line'),
 dict(t='Smaller ones', steps='03.4, 07.3, 10.3, 11.4, 13.2, 14.1, 14.5',
      why='The session tooltip is cut after "9 remo"; use elsewhere is invisible until a session runs; the keep awake row does not say a closed lid on battery still sleeps; the Reopen row does not say notifications are off; an empty settings.json stays after Remove; the spoken weekday is "sun"; the key hints fail contrast.',
      fix='Wrap the tooltip over two lines or drop the list price from it; keep the README line for use elsewhere; add "not with the lid closed on battery" under keep awake; show the notifications note under Reopen too; delete settings.json on Remove when the install created it; use the full weekday in labels; lift quiet to #8a8a8a or drop the hints.',
      size='small each'),
]

PAPPLE = [
 'Lint: python3 -I ~/Developer/apple-native/skills/apple-native/scripts/lint.py on the repository: 33 files, 0 errors, 0 warnings. It checks SwiftUI and Apple API usage; this app is AppKit drawn by hand, so most of what follows is outside its reach.',
 'HIG by eye on the screenshots: a menu bar extra with a template image that follows the light and dark menu bar, a transient popover anchored to it, Esc and Command Q, no Dock icon. The popover is a terminal grammar on purpose (SF Mono 12, block bars), consistent and calm; it does not use system controls, which is where the accessibility gaps come from. Text is cut at the edge in two places (gap 5).',
 'Accessibility: the item has a full spoken label. Inside the popover every line is static text: no button, tab or checkbox roles, no press action, no keyboard focus (gap 3). The style guide section 9 already specifies the right roles, so the code is behind its own spec. Contrast: text 13 to 1, dim 6 to 1, coral 5.5 to 1, key hints 2.1 to 1 (fails).',
 'Reduce motion: honoured (no popover animation). Reduce transparency and Increase contrast: the glass is an NSVisualEffectView, which the system adapts; the tint on top stays at 82 percent.',
 'Dynamic Type: macOS apps have no Dynamic Type; the popover is fixed at SF Mono 12 and ignores the macOS text size setting, while the style guide says text size follows the system monospace font. Friction, not a HIG violation.',
 'Notifications: asked at launch, not in context (gap 9). Permission denial is handled with a note, cut at the edge.',
]

LEFT_OUT = [
 'Gatekeeper on a clean account and across two releases: not walked; this Mac runs the local build. The steps follow the README and spec 17; spctl confirms the ad hoc build is rejected.',
 'Clicks in the running app: this session has no Accessibility or Screen Recording permission, so the popover could not be clicked or captured from the screen. Every screen state was rendered by the app itself (--snapshot, --live-snapshot and the ScreenBuilder harness), and the click paths were read from LineView and Controller. Open at login was not clicked.',
 'Notifications: the debug binary is not an app bundle, so the notifier is unavailable (it says so in Settings); the banner texts come from Controller.swift. The running 0.1.7 bundle was left alone.',
 'The user\'s real ~/.claude was never written. Hook install and remove ran on throwaway folders; the live runs used CFFIXED_USER_HOME on throwaway homes. The real data folder of the running app was only read.',
 'Light menu bar, a desktop Mac without a battery, an Intel Mac: not available in this run.',
]


def reach(SC, a, b):
    return f'href="{b}.html"' in SC[a]['body'] or f'"{b}.html"' in json.dumps(SC[a]['keys'])


def write_all(here, SC, flows):
    titles = {k: re.sub('<[^>]+>', '', v['title']).replace('&amp;', '&') for k, v in SC.items()}
    nsteps = sum(len(f['steps']) for f in flows)
    cnt = {'works': 0, 'friction': 0, 'broken': 0}
    for f in flows:
        for i, st in enumerate(f['steps']):
            st['n'] = str(i + 1)
            cnt[st['now']] += 1
            prev = f['steps'][i - 1]['screens'] if i else None
            st['walk'] = 'start' if not prev else ('click' if any(reach(SC, p, st['screens'][0]) for p in prev) or st['screens'][0] in prev else 'next')
    fl = [{'id': f['id'], 'name': f['name'], 'steps': [{k: s[k] for k in ('n', 'text', 'screens', 'do', 'now', 'ev', 'walk')} for s in f['steps']]} for f in flows]
    (here / 'flows.js').write_text('window.FLOWS = ' + json.dumps(fl, indent=1) + ';\nwindow.TITLES = ' + json.dumps(titles, indent=1) + ';\n')

    # index
    areas = {}
    for k, v in SC.items():
        areas.setdefault(v['area'], []).append(k)
    cards = ''.join(
        f'<li><a class="fl" href="walk.html?f={f["id"]}"><b>{f["id"]} {f["name"]}</b><span>{len(f["steps"])} steps: '
        f'{sum(s["now"] == "works" for s in f["steps"])} work, {sum(s["now"] == "friction" for s in f["steps"])} friction, {sum(s["now"] == "broken" for s in f["steps"])} broken</span>'
        f'<span class="go">Walk this flow</span></a></li>' for f in flows)
    secs = ''.join(f'<section><h3>{a} <span>{len(ids)}</span></h3><ul>' + ''.join(f'<li><a href="screens/{i}.html">{SC[i]["title"]}</a><span>{i}</span></li>' for i in ids) + '</ul></section>' for a, ids in areas.items())
    (here / 'index.html').write_text(f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>tokenpanda wireframes</title><link rel="stylesheet" href="wire.css"><style>
body{{padding:32px 16px 64px}} main{{max-width:1080px}} h1{{color:var(--ink);font-size:22px;margin:0 0 6px}} h2{{color:var(--ink);font-size:15px;margin:32px 0 10px}}
h3{{color:var(--ink);font-size:13px;margin:18px 0 6px}} h3 span{{color:var(--marker);font-weight:400}} p{{max-width:720px}}
ul{{list-style:none;padding:0;margin:0}} .flows{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:10px}}
.fl{{display:flex;flex-direction:column;gap:4px;background:var(--card);border-radius:12px;padding:14px 16px;box-shadow:var(--card-sh)}} .fl b{{color:var(--ink)}}
.fl .go{{color:var(--accent);font-weight:600;font-size:11.5px;margin-top:4px}} section li{{display:flex;gap:10px;padding:3px 0;border-bottom:1px solid var(--line)}}
section li a{{color:var(--ink)}} section li span{{color:var(--marker);font-size:11px;margin-left:auto}}
.cols{{columns:2 360px;column-gap:28px}} section{{break-inside:avoid}}
</style></head><body><main>
<h1>tokenpanda wireframes</h1>
<p>tokenpanda as it is built (main at 4ca4160, release 0.1.7), every screen and state the user flows touch, on a 1280 by 800 desktop with the menu bar and the popover. {len(SC)} screens, {len(flows)} flows, {nsteps} steps tested against the real app: {cnt["works"]} work, {cnt["friction"]} with friction, {cnt["broken"]} broken.
Controls that lead somewhere are links; the popover keys work too (Esc, Tab, Shift Tab, m, p, s). Other outcomes and other starts are dashed targets: press h on any screen to show them and outline every link. Coral notes name what is wrong on a screen. The findings, the gap list and the fixes are in flow-test.md; the flows as text and diagrams in flows/.</p>
<h2>Flows</h2><ul class="flows">{cards}</ul>
<h2>Every screen</h2><div class="cols">{secs}</div>
</main></body></html>
''')

    # walk
    (here / 'walk.html').write_text('''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Walk a flow</title><link rel="stylesheet" href="wire.css"><style>
body{padding:16px}.wrap{display:flex;gap:16px;align-items:flex-start}
.stage{width:960px;height:600px;flex:none;border-radius:12px;overflow:hidden;box-shadow:var(--card-sh);background:var(--desk)}
.stage iframe{width:1280px;height:800px;border:0;transform:scale(.75);transform-origin:0 0}
.side2{flex:1;min-width:280px;max-width:440px;background:var(--card);border-radius:12px;box-shadow:var(--card-sh);padding:16px;display:flex;flex-direction:column;gap:10px;max-height:calc(100vh - 32px);overflow:auto}
.side2 h1{font-size:15px;color:var(--ink);margin:0}.cur{border:1.5px solid var(--bar2);border-radius:8px;padding:10px 12px;display:flex;flex-direction:column;gap:6px}
.cur b{color:var(--ink)}.steps{list-style:none;padding:0;margin:0}.steps li{padding:4px 6px;border-radius:4px;font-size:11.5px;cursor:pointer;display:flex;gap:8px}
.steps li.on{background:var(--soft);color:var(--ink)}.steps li span:first-child{width:22px;flex:none;color:var(--marker)}
.steps li span.st{width:56px;flex:none;color:var(--marker)}.steps li span.st.friction{color:var(--ink);font-weight:600}.steps li span.st.broken{color:var(--accent);font-weight:600}
.nav2{display:flex;gap:8px;align-items:center}.where{font-size:11px;color:var(--marker)}
.now{font-weight:600}.now.friction{color:var(--ink)}.now.broken{color:var(--accent)}
@media (max-width:1300px){.wrap{flex-direction:column}.stage{width:100%;max-width:960px;height:auto;aspect-ratio:1280/800}}
</style></head><body>
<div class="wrap"><div class="stage" id="stage"><iframe id="fr" title="Wireframe"></iframe></div>
<div class="side2"><div class="nav2"><a class="btn" href="index.html">All flows</a><span class="sp"></span><a class="btn" id="prev">Back</a><a class="btn pri" id="next">Next</a></div>
<h1 id="ft"></h1><div class="cur" id="cur"></div><div class="where" id="where"></div><ul class="steps" id="steps"></ul></div></div>
<script src="flows.js"></script><script>
(function(){
  var q=new URLSearchParams(location.search),fid=q.get('f')?q.get('f'):'01',fl=FLOWS.filter(function(f){return f.id===fid}),flow=fl.length?fl[0]:FLOWS[0];
  var seq=[];flow.steps.forEach(function(s,si){s.screens.forEach(function(sc,k){seq.push({si:si,sc:sc,k:k,of:s.screens.length})})});
  var si0=parseInt(q.get('s')?q.get('s'):'0',10);var i=Math.min(isNaN(si0)?0:si0,seq.length-1);
  document.getElementById('ft').textContent=flow.id+' '+flow.name;
  var fr=document.getElementById('fr'),stage=document.getElementById('stage');
  function fit(){var w=stage.clientWidth;fr.style.transform='scale('+(w/1280)+')';stage.style.height=(w*800/1280)+'px'}
  window.addEventListener('resize',fit);
  function esc(t){var d=document.createElement('div');d.textContent=t;return d.innerHTML}
  function show(){
    var it=seq[i],s=flow.steps[it.si];
    fr.src='screens/'+it.sc+'.html?hot=1';
    document.getElementById('cur').innerHTML='<b>Step '+s.n+(it.of>1?', screen '+(it.k+1)+' of '+it.of:'')+'</b><span>'+esc(s.text)+'</span>'+
      '<span class="note">Do: '+esc(s.do)+'</span><span class="note">In the real app: <span class="now '+s.now+'">'+s.now+'</span>. '+esc(s.ev)+'</span>'+
      '<span class="note">Screen: '+esc(TITLES[it.sc]?TITLES[it.sc]:it.sc)+' ('+it.sc+')</span>';
    var ul=document.getElementById('steps');ul.innerHTML='';
    flow.steps.forEach(function(st,si){var li=document.createElement('li');li.className=si===it.si?'on':'';
      li.innerHTML='<span>'+st.n+'</span><span class="st '+st.now+'">'+st.now+'</span><span>'+esc(st.text)+'</span>';
      li.onclick=function(){for(var j=0;j<seq.length;j++){if(seq[j].si===si){i=j;show();break}}};ul.appendChild(li)});
    history.replaceState(null,'','?f='+flow.id+'&s='+i);
    document.getElementById('prev').style.visibility=i>0?'visible':'hidden';
    document.getElementById('next').textContent=i<seq.length-1?'Next':'Done';
    document.getElementById('where').textContent='';
    fit();
  }
  document.getElementById('prev').onclick=function(){if(i>0){i--;show()}};
  document.getElementById('next').onclick=function(){if(i<seq.length-1){i++;show()}else location.href='index.html'};
  document.addEventListener('keydown',function(e){if(e.key==='ArrowRight'){document.getElementById('next').click()}if(e.key==='ArrowLeft'){document.getElementById('prev').click()}});
  window.addEventListener('message',function(e){if(e.data&&e.data.wireScreen&&e.data.wireScreen!==seq[i].sc){document.getElementById('where').textContent='You clicked through to: '+(TITLES[e.data.wireScreen]?TITLES[e.data.wireScreen]:e.data.wireScreen)+'. Next goes on with the flow.'}});
  show();
})();
</script></body></html>
''')

    # flows/flows.md and one Mermaid file per flow
    fd = here / 'flows'
    fd.mkdir(exist_ok=True)
    for old in fd.glob('*.mmd'):
        old.unlink()
    md = ['# tokenpanda user flows, as built', '',
          'Main at 4ca4160 (release 0.1.7). Each flow as numbered steps; the screens are in ../screens, the walk in ../walk.html, the results in ../flow-test.md. One Mermaid diagram per flow sits next to this file.', '']
    for f in flows:
        slug = re.sub(r'[^a-z0-9]+', '-', f['name'].lower()).strip('-')
        name = f'{f["id"]}-{slug}.mmd'
        md += [f'## {f["id"]} {f["name"]}', '', f'Diagram: {name}', '']
        md += [f'{s["n"]}. {s["text"]}' for s in f['steps']] + ['']
        lines = ['flowchart TD', '  classDef works fill:#1d2029,stroke:#555b68,color:#eceef1;',
                 '  classDef friction fill:#262a34,stroke:#eceef1,stroke-width:2px,color:#eceef1;',
                 '  classDef broken fill:#1d2029,stroke:#d77757,stroke-width:2px,color:#d77757;']
        for s in f['steps']:
            words, out, cur = s['text'].replace('"', "'").split(), [], ''
            for w in words:
                if len(cur) + len(w) > 46:
                    out.append(cur)
                    cur = w
                else:
                    cur = (cur + ' ' + w).strip()
            out.append(cur)
            lines.append(f'  S{s["n"]}["{s["n"]}. ' + '<br/>'.join(out) + f'<br/><i>{s["now"]}</i>"]:::{s["now"]}')
        for a, b2 in zip(f['steps'], f['steps'][1:]):
            lines.append(f'  S{a["n"]} --> S{b2["n"]}')
        (fd / name).write_text('\n'.join(lines) + '\n')
    (fd / 'flows.md').write_text('\n'.join(md))

    # flow-test.md
    t = ['# Flow test of tokenpanda as built (31.10.2026)', '',
         'Product: main at 4ca4160, release 0.1.7, the running app on this Mac is the same build. No app code was changed for this test.', '',
         'Method: the product read first (README, CHANGELOG, docs/spec.html, styleguide.html, privacy.html, every file in Sources/ and Tests/, the scripts, the cask), then the flows written as numbered steps (flows/), then every step checked twice:', '',
         '1. In the real app. swift build and the 97 tests pass with the Command Line Tools (DEVELOPER_DIR, the Xcode licence is not accepted on this Mac). The debug binary ran against throwaway homes (CFFIXED_USER_HOME) with crafted status line feeds, rendering its own tabs with --live-snapshot (live-<name>); --snapshot rendered the fixtures (fixtures/<name>); a harness linked against the debug objects rendered crafted inputs through ScreenBuilder, Grammar and SnapshotWriter (states/<name>) and ran the real Hook install, hook script and uninstall on throwaway folders (hookrun). The real data folder of the running 0.1.7 was read, never written. Screenshots were looked at one by one and are not kept in the repository.',
         '2. In the wireframes: every screen of the step exists, and the step can be reached from the step before by a click or a key, or by a dashed target for another outcome or another start (press h, or walk mode, shows them). "click" below means reachable that way, "next" means the walk moves on with Next, "start" is the first step of a flow.',
         '', '## Counts', '',
         f'1. Flows: {len(flows)}. Steps: {nsteps}.',
         f'2. In the real app: {cnt["works"]} work, {cnt["friction"]} friction, {cnt["broken"]} broken.',
         f'3. In the wireframes: {nsteps} of {nsteps} steps drawn; {sum(s["walk"] == "click" for f in flows for s in f["steps"])} reached by a click or key from the step before, {sum(s["walk"] == "start" for f in flows for s in f["steps"])} flow starts, {sum(s["walk"] == "next" for f in flows for s in f["steps"])} reached with Next.',
         f'4. Screens: {len(SC)}, a 1280 by 800 desktop with the menu bar, the popover at its real 380 point width and 16 point lines.', '',
         '## The 5 hour window for Ultra, exactly', '',
         'What happened: on 30 Oct 2026 Anthropic removed the 5 hour window for verified Ultra accounts; Max and Pro keep it. The status line feed stopped carrying rate_limits.five_hour for those accounts. On this Mac the ten live session files carry seven_day only, and limits.json still holds five_hour used 1, resetsAt 31 Oct 00:10, previousResetsAt 30 Oct 19:10, next to a fresh seven_day (asOf 11:11 today).',
         '',
         'Why it sticks: Limits.apply (Sources/Feed/FeedReader.swift:23-38) loops over the keys the feed carries and never removes one it does not carry, and the result is persisted to limits.json. ScreenBuilder.windowView (Sources/UI/ScreenBuilder.swift:60-79) only reaches mode .absent (line 62) when no record exists, so once a five_hour record was ever stored it is drawn for good. Staleness is judged by limits.asOf (line 69), which the weekly keeps fresh, so the old 5h record is never shown as stale.',
         '',
         'What an Ultra user saw and sees:',
         '1. 30 Oct, from the last five_hour feed until its reset at 00:10: the last 5h percentage as if live, with a running countdown, a moving tick, a status word and a projection computed from a figure that no longer changes (an example figure, the last one on this Mac was 1%; states/ultra-evening: "63% used, Resets 00:10 in 2h 40m, Over pace  limit 22:50 at this rate"; states/ultra-late at 23:58: "Ahead  66% by reset at this rate, 185% an hour left"). The real binary does the same: live-ultra-day1 kept five_hour 63 through 50 s of feeds without it.',
         '2. If that last figure was 100: the panda\'s - - eyes and "5h limit reached" in the spoken label until 00:10 (ScreenBuilder.swift:292-299), and a "5h window ends in 15 min" nudge can fire at 23:55 (Controller.swift:420-424).',
         '3. From 00:10 on, today and every day after: "5h window", an empty bar, "Reset 00:10  no session since", under the header "Usage live  Mac live" with open sessions listed below (live-ultra-today, the exact state of this Mac). The clock has no day, so it reads as today.',
         '4. A new Ultra user, whose feed never carried five_hour, sees "5h window", an empty bar, "not in the last feed", for good.',
         '',
         'The smallest correct fix, in two parts:',
         '1. Sources/Feed/FeedReader.swift, Limits.apply, at the start of the function: `for key in windows.keys where rateLimits[key] == nil { windows.removeValue(forKey: key) }`. apply runs only for a snapshot that carries rate_limits (FeedReader.swift:98 and :101), so the first call of a session, which has none, still changes nothing, as the spec requires. The Anthropic doc quoted in spec 3 already says "Each window may be independently absent, and Claude Code drops a window once its resets_at time passes". The next scan writes limits.json without five_hour; the nudge, the eyes and the label stop at once because they read the same record.',
         '2. Sources/UI/ScreenBuilder.swift line 83: draw a fixed key only while its record exists: `var views = keys.filter { limits.windows[$0] != nil }.map { ... }`, and when that leaves nothing, the weekly as .absent. Ultra users then see the weekly alone; without part 2 they see the existing honest mark, an empty bar with "not in the last feed".',
         'Kept for plans that still send it: a Max or Pro feed carries five_hour on every call after the first, so apply keeps setting it and the section stays exactly as today (live-max). Tests to add in FeedTests: a feed with seven_day only after one with both removes five_hour; a first call without rate_limits after that keeps seven_day; the stored record of a Max feed survives. The same change also ends gap 6, the weekly "no session since" after a reset.',
         '']
    for f in flows:
        t += [f'## {f["id"]} {f["name"]}', '']
        for s in f['steps']:
            t.append(f'{s["n"]}. {s["now"]}. {s["text"]} Screens: {", ".join(s["screens"])}. Do: {s["do"]} Evidence: {s["ev"]} Wireframe: {s["walk"]}.')
        t.append('')
    t += ['## Gaps, by user impact', '', 'Each with the smallest fix found and its size.', '']
    for i, g in enumerate(GAPS, 1):
        t += [f'{i}. {g["t"]} (steps {g["steps"]})', f'   Why it matters: {g["why"]}', f'   Fix: {g["fix"]}', f'   Size: {g["size"]}.', '']
    t += ['## Apple standards (P-APPLE)', ''] + [f'{i}. {x}' for i, x in enumerate(PAPPLE, 1)] + ['']
    t += ['## Left out or read from the code', ''] + [f'{i}. {x}' for i, x in enumerate(LEFT_OUT, 1)] + ['']
    text = '\n'.join(t)
    for ch in ['—', '–', '·', '|']:
        assert ch not in text, f'forbidden character {ch!r} in flow-test.md'
        assert ch not in '\n'.join(md), f'forbidden character {ch!r} in flows.md'
    (here / 'flow-test.md').write_text(text)
