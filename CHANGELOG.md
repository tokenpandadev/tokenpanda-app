# Changelog

## 0.1.9, unreleased

- VoiceOver reads the Mac tab in order again: CPU, GPU, memory and battery were skipped because their figures change every 2 s, and each change made VoiceOver lose its place and jump to the processes.
- On a plan without a 5h window (Ultra), the nudge setting reads "Nudge at 80%" instead of "Nudge at 80% and before the 5h end".
- VoiceOver says "Memory" once, in the memory description, and the stale note "limits are shared with the Claude app and other Macs" as one sentence.
- VoiceOver names the app on the menu bar item: "tokenpanda, Weekly 7% used, ahead, resets Sunday 17:00".
- VoiceOver can press every control. The tabs, the Models, Projects and Sessions switch, every setting, Install, Remove and Quit are buttons, tabs and checkboxes, each saying its state (selected, checked or not). A session figure's tooltip is read as its help, a setting's dim line too, once.
- VoiceOver reads figures in words instead of glyph names: each window section is one sentence ("Weekly, all models. 61% used. Resets Sunday 18:00, in 3 days 3 hours. Over pace, ..."), each week row one line ("Week of 28 September, 100%, hit the limit Thursday 16:10"), the memory grid one image with a description, and the CPU, GPU and battery bars their percent and detail. The rule under the header and the grid cells are skipped. Text that wraps over lines is read once, whole. VoiceOver's pointer lands on the element under it. Not yet checked with VoiceOver speaking; docs/testing.html is the script for that.
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

## 0.1.6, 2026-10-21

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
