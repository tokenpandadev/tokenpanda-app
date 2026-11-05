# Changelog

## 0.1.16, unreleased

- Far less CPU while many Claude Code sessions run: a burst of status line writes is read at once and once more a second later, a session file is parsed again only when it changed, and Claude Code's own session files the same way. With 22 sessions each writing about every 0.3 s, the app used 76.6% of one core in 0.1.15 and uses 2.2% now, at most 47 MB of memory where 0.1.15 took up to 50 MB. Every figure still follows a write within a second.
- Reopen opens the sessions in Terminal, iTerm or Ghostty, picked under "Open sessions in" below the Reopen switch. An app that is not installed is shown but cannot be picked, and a pick whose app is gone opens in Terminal. Ghostty asks before it runs each session, and the row says so.
- The feed watch's handler was written as main thread code but ran on a background queue, so the Swift runtime's actor isolation check failed on every status line write and logged it, about 7,000 times a minute with 22 sessions open. The handler now runs as background code that only hands the event to the main thread, which does the work.
- Reopen cleans up after itself: the last session's script also deletes its folder, and a folder left over, for example after a cancelled Ghostty prompt, is deleted once it is ten minutes old, at the next Reopen or the next start of the app. A script that macOS could not open is noted in the macOS unified log.
- With iTerm picked and not running, Reopen starts iTerm first and opens the sessions once it has finished launching. An app Launch Services still finds in the Trash, or that is no longer on disk, counts as not installed.
- Deleting the app's sessions folder while it runs no longer slows the figures down until the next start of the app: the watch picks up the folder again once the status line makes it anew, and every write is followed within a second again instead of at the next 5 s scan.
- A Claude Code session file left behind by a session that ended no longer counts as a running session when macOS gives its process number to another program: the app checks the start time Claude Code wrote into the file against the process's own.
- The notice that a session ended names iTerm when the window is in iTerm. Before, it said only "Its window is still open" for iTerm, whose shells run under a session server of its own.

## 0.1.15, 2026-11-04

- Install and Remove find the file a linked settings.json names the way macOS does, also when ~/.claude is itself a link into a dotfiles folder and the file is not made yet. From 0.1.11 such a relative link could name another file, which Install then wrote over with only the status line entry while Claude Code kept reading the missing one. A file written at the wrong place by those versions is left as it is.
- When settings.json is a link into a folder that does not exist, Install stops and says so ("it is a link into ~/…, a folder that does not exist"). Before, it made that folder, and Remove left it behind.
- The 7 day and 30 day token rows drop a record as soon as it is older than the window. Since 0.1.0 they kept counting it on a quiet day, until the next transcript line or midnight.
- The window that says tokenpanda is running when its icon is not visible names the notch only on a Mac that has one, and also names an app that hides menu bar icons, such as Bartender or Ice.
- With VoiceOver, a capped panel scrolls each line into view as VoiceOver reaches it, text lines as well as controls. Before, only controls scrolled.
- A nudge that comes due while notifications are off is kept: once they are on again it comes at the next check, while the window still calls for it. Before, it was spent and never came for that window.
- The first minutes of a window no longer project a limit from one reply: until 5% of the window has passed the row reads "too early to project" unless the pace is over. A limit time is named only when the pace is over; on pace the row says what share the reset is likely to find, at most 100%.
- The testing page has a step for turning notifications off and on while the app runs, and the order in which the app reads that setting is now tested.

## 0.1.14, 2026-11-04

- The token rows keep their figures after midnight. Since 0.1.0 they read "nothing in the last 7 days" from midnight until the next transcript change.
- Turning notifications on in System Settings counts at once: the note goes away the next time you open the panel, and nudges are posted. Before, the app kept the old answer until it was restarted. The note "Notifications are off in System Settings" now looks like the link it is, and VoiceOver says it once.
- The window that says tokenpanda is running when its icon is not visible fits your macOS: from macOS 26 it names both causes, switched off in System Settings, Menu Bar, or behind the notch on a full menu bar, with a button to the Menu Bar settings; on macOS 14 and 15, where an app's icon cannot be switched off there, it names the full menu bar and has no button. It waits while the screen is locked, another user is on the Mac or the display sleeps.
- The panel is never taller than your screen: on a small or zoomed screen it stops at the screen's height and scrolls, starting at the top each time, and the keyboard focus scrolls into view. VoiceOver reads every line; the outline of a line outside the visible part shows only once it is scrolled into view.
- Remove keeps a settings.json that is a link into a dotfiles folder as a link, also when Install had created the file it points at. Before, Remove deleted the link and left the status line entry in that file.
- The free cells of the memory grid are a little lighter, so they stay visible over a white desktop.
- tokenpanda runs on Macs with Apple silicon. Homebrew now says so and no longer installs it on an Intel Mac, where it could not start.
- The privacy page says that the app reads Claude Code's own small session files to show each session's name, and lists every preference it keeps.

## 0.1.13, 2026-11-03

- The status line script cleans up after itself: it deletes the session files that stopped changing over a minute ago, the same rule the app uses. Before, if the app went to the Bin without Remove, the script kept adding one file per session that nothing deleted. An entry installed by an earlier version gets the new script at the next launch, with your chained status line kept.
- VoiceOver reads the privacy sentence ("This app makes no network calls. Usage comes from Claude Code's own status feed on this Mac.") as one, not as two halves.

## 0.1.12, 2026-11-03

- If the menu bar icon is hidden a few seconds after the first launch (switched off under System Settings, Menu Bar, or behind the notch on a full bar), one window says that tokenpanda is running, with a button that opens the Menu Bar settings. It shows once.
- "Notifications are off in System Settings" under Nudge and Reopen is now a link that opens the Notifications settings.
- The Install button has one name everywhere: "Install the status line entry", on the Claude tab as in Settings.
- After a weekly reset with no session since, the new week's row says "no reply yet" instead of repeating the old week's figure.
- A settings.json that is not valid JSON now says so ("is not valid JSON"); "is not a JSON object" is kept for valid JSON that is not an object.

## 0.1.11, 2026-11-03

- Light mode: the panel follows your Mac. With a light appearance it turns light, with the same layout and the same frosted glass, and it switches as soon as you change the setting. Every text colour stays readable over a white or a black desktop.
- The Mac tab names Claude Code "Claude Code" in the process list. Claude Code's native install runs a file named after its version, so the list showed "2.1.317".
- Install and Remove keep a settings.json that is a link (into a dotfiles folder, for one) as a link and write the file it points at, with its permissions. Before, the link was replaced by a plain copy that others on the Mac could read, and Remove wrote into that copy. A settings.json the app creates is readable by you only.
- Dim text (reset lines, pace lines, captions, the header line) is a little lighter, so it stays readable over a bright desktop: at least 4.5 to 1 even over white.
- A broken or oversized file can no longer crash the app: numbers out of range in the feed or a transcript are ignored, status line files and settings.json over 1 MB are skipped, a transcript line over 10 MB is skipped, and the transcript check for Remote Control opens only a regular file.
- The hook script quotes the app's data folder so that no character in the path can change what it does. It takes effect at the next Install.
- If the app cannot write remove.sh, which brew uninstall --zap uses to put your status line back, Settings says so under the status line row. This and failed writes of the app's own records go to the macOS log.
- The app carries a privacy manifest: no tracking, no data collected.
- The app no longer ships a copy of the hook script it never used.

## 0.1.10, 2026-11-03

- Reopen after a restart starts each session as it was started: with its name and the options it was started with (extra folders, appended system prompt, model, permission mode and the rest), not as a plain `claude --resume`. A start prompt typed after the options is not sent again. If that start fails within 20 seconds, the same without Remote Control follows, then a plain resume. The app reads the options from the session's process and its name from Claude Code's own session file; without that file, sessions still reopen, with a plain resume.
- The restart notification names the sessions ("Backend, Docs, Website, Infra and 7 more") instead of their folder. A session without a name shows its folder, counted when several share it.
- A session that ends while its Terminal window stays open gets one notification with its name, the time and a Reopen button for it. A closed window or a shutdown gets none. Behind the same switch, Reopen sessions after a restart.
- Open sessions shows each session by its name (set with -n or /rename), its folder only when it has none, so several sessions in one folder are told apart.
- A reopened session's window keeps a shell when the session ends, as a window where you typed claude does.

## 0.1.9, 2026-11-03

- On a plan without a 5h window (Ultra), the nudge setting reads "Nudge at 80%" instead of "Nudge at 80% and before the 5h end".
- VoiceOver names the app on the menu bar item: "tokenpanda, Weekly 7% used, ahead, resets Sunday 17:00".
- VoiceOver can press every control. The tabs, the Models, Projects and Sessions switch, every setting, Install, Remove and Quit are buttons, tabs and checkboxes, each saying its state (selected, checked or not). A session figure's tooltip is read as its help, a setting's dim line too, once.
- VoiceOver reads figures in words instead of glyph names: each window section is one sentence ("Weekly, all models. 61% used. Resets Sunday 18:00, in 3 days 3 hours. Over pace, ..."), each week row one line ("Week of 28 September, 100%, hit the limit Thursday 16:10"), the memory grid one image with a description, and the CPU, GPU and battery bars their percent and detail. The rule under the header and the grid cells are skipped. Text that wraps over lines is read once, whole. VoiceOver's pointer lands on the element under it. Checked with VoiceOver speaking on 3 November, following docs/testing.html.
- The Down key also stops on the key figures, each said whole: Weekly, 5h and each week over week row on the Claude tab, CPU, GPU, memory and battery on the Mac tab.
- The keyboard reaches every control. Down and Up move through the tab, Left and Right along the tab strip and the section switch, Space or Return presses. A thin accent ring shows where you are. Tab still switches tabs and now puts the ring on the tab it opened.
- The key hints at the foot are readable: lifted from dark grey to light grey, at least 4.5 to 1 even over a white desktop.
- Several settings folders: Install and Remove now work on ~/.claude, a `CLAUDE_CONFIG_DIR` folder, and `~/.config/claude` or a `~/.claude-something` folder that holds a settings.json, each keeping its own previous status line, and those sessions feed the windows. A folder with transcripts only (a backup copy) is left alone; its transcripts are still counted. To include such a folder, put a settings.json in it.
- If Install fails, the Claude tab says why under the button, over as many lines as it needs. Errors in Settings are no longer cut at the edge either.
- `brew uninstall --zap` now puts your previous status line back before it deletes the app's data, on any Homebrew version: the zap runs a small remove script the app keeps in its data folder (sh and plutil), not the app itself, so it works also where Homebrew deletes the app first (before 7.0.10). The app writes that script whenever its entry is in place, at Install and at every launch, so an entry installed with an older version is covered once 0.1.9 has run once. `tokenpanda --remove-status-line` does the same from Terminal. And if the hook script is gone while settings.json still points at it, the app no longer says it is installed: it says the script is gone and offers Install again.
- Text no longer runs past the panel edge: the Settings line about settings.json, the notifications note and the session tooltip, which now breaks over two lines.
- After a Sunday evening reset, week over week labels the new week by its own Monday instead of showing the same date twice.
- During a session's first call both windows say "waiting for the first reply" instead of "open Claude Code once".
- The app no longer asks for notification permission at launch. It asks when the first nudge is due, or when you turn on Nudge or Reopen sessions.
- The line at the top of the panel says what it means: "Live from Claude Code" while a session feeds, "As of 13:05, last Claude Code session" between sessions, "Waiting for a Claude Code session" before the first one. "Usage live  Mac live" is gone; the Mac figures are always live.
- Settings shows the version, "tokenpanda 0.1.9", under the privacy lines.
- Files a cancelled hook run left behind in the sessions folder are cleaned up.
- Smaller: keep awake says a closed lid on battery still sleeps; the Reopen row says when notifications are off; VoiceOver says the weekday in full ("resets Sunday 18:00"); Remove deletes a settings.json that Install created instead of leaving an empty {}.
- README: what keeps a session from feeding (workspace trust, a project or managed statusLine, the IDE extensions, the desktop app, claude -p), several settings folders, and the zap.

Not changed: the popover stays SF Mono 12. macOS gives AppKit apps no text size to follow; Larger Text in Displays and Zoom enlarge it. The style guide says why.

## 0.1.8, 2026-10-31

- The weekly figure no longer jumps between the values each open session last saw. With several sessions open the app takes the highest figure for the current week, and keeps it when the busiest session closes. Week over week keeps the highest value of each week too.
- A window your plan no longer has goes away. When Claude Code stops sending the 5h window for an account, the row keeps its last figure without countdown or pace until that window's reset, then goes after the next reply that comes without it. Before, the old figure showed as live, or "no session since" stayed for good. The panda's eyes, the spoken label and the nudges stop using it at once. Max and Pro see no change.
- After switching accounts with /login, or with two accounts open at once, the windows show the newer account's figures at once instead of "unknown window".
- When your sessions run on an API key, Bedrock or Vertex after using a subscription, the old plan figures are no longer drawn as live: the panel says these sessions carry no plan limits.
- If your own status line refreshes less often than every 5 seconds, Install sets it to 5 so open sessions stay listed, and the Install text says so; Remove puts your own value back, also when the app's backup file is gone.
- With disableAllHooks on in settings.json, the panel says Claude Code runs no status line, instead of waiting for a feed that never comes.
- After /compact or a resume, a session reads "compacted or resumed  next reply updates it" instead of "waiting for the first reply", and the line fits the panel.
- If a Claude Code update renames the limit fields, the panel says the feed format changed instead of "no plan limits".
- After a window resets while sessions are open but waiting, the row says "new window on the next reply" instead of "no session since".

Known in 0.1.8: with CLAUDE_CONFIG_DIR or a settings folder other than ~/.claude, Install still writes ~/.claude/settings.json, so those sessions never feed the windows. Planned for the next version.

## 0.1.7, 2026-10-22

- Settings: Reopen sessions after a restart, off by default. After the Mac starts again, one notification says how many Claude Code sessions were open before. Reopen opens each in Terminal with `claude --resume`, and with Remote Control again for sessions that had it. It waits until the Mac has a network address, so Remote Control can connect, and skips sessions that are open already. Nothing starts without the click. The app keeps a small list of the open sessions while the switch is on and deletes it when you turn it off.

## 0.1.6, 2026-10-22

- Settings: Open at login, the first row, off by default. It uses the macOS login item service and stores nothing of its own, so the box always shows what macOS says, also after you remove the app in System Settings, General, Login Items. If macOS waits for your OK, the row says so and a click opens Login Items; if it refuses, the row says why.

## 0.1.5, 2026-10-21

- The panda's eyes show a used up window until it resets: x x for the weekly limit, - - for the 5h window, the weekly one when both are. The item's spoken label says which limit was reached.

## 0.1.4, 2026-10-21

- Settings: under Keep the Mac awake, a second switch, also while a session waits for you, off by default. With both on, any open Claude Code session holds the Mac awake, idle ones too, so it stays reachable through Remote Control from the phone. The row then says "awake" with the number of sessions open.

## 0.1.3, 2026-10-21

- Settings: Keep the Mac awake while Claude works, off by default. While a session's figures moved in the last ten minutes, the app holds one power assertion against idle sleep and the row says "awake" with the number of sessions working. The display may still sleep, and a closed lid on battery still sleeps the Mac.

## 0.1.2, 2026-10-15

- The menu bar item is the panda and the weekly percentage. The five cell bar is gone; the percentage still goes semibold over pace and the item still dims when the figures are older than an hour.

## 0.1.1, 2026-10-14

- App icon: the panda drawn in 44 terminal cells, also used for the documentation favicon.

## 0.1.0, 2026-10-14

The first version.

- The menu bar item: the weekly percentage and a five cell bar, dimmed when the figures are older than an hour.
- The Claude tab: the weekly and the 5h window with pace in words and clock time, the open sessions and their context, tokens by model, project and session from the local transcripts, the list price equivalent, week over week.
- The Mac tab: CPU, GPU, memory with pressure and swap, battery, the busiest processes.
- Settings: Mac figures in the bar, the two nudges, the list price equivalent, and one row to install or remove the status line entry.
- The status line hook: installed only on a click, chains a status line you already have, keeps the other keys of your entry, and puts the entry back exactly when you remove it.
- The transcript reader works on read(2) and memchr, so a full pass over several gigabytes of transcripts stays near 50 MB of memory.
- The process figures use the Mach timebase, so CPU percentages are right on every Mac.
- The popover renders only when something changed, and the token totals are rebuilt only when a transcript moved or the day turned.
- No network code, no account, no analytics.
