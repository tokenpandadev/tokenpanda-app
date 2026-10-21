# Changelog

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
