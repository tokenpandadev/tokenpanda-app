<img src="docs/mark.png" width="64" alt="tokenpanda">

# tokenpanda

A macOS menu bar app that tells me if I am ahead of the clock on my Claude plan, or behind it.

[![Latest release](https://img.shields.io/github/v/release/tokenpandadev/tokenpanda-app?style=flat-square&color=b1b9f9)](https://github.com/tokenpandadev/tokenpanda-app/releases/latest) [![Licence MIT](https://img.shields.io/badge/licence-MIT-b1b9f9?style=flat-square)](LICENSE) [![Build](https://img.shields.io/github/actions/workflow/status/tokenpandadev/tokenpanda-app/build.yml?style=flat-square)](https://github.com/tokenpandadev/tokenpanda-app/actions/workflows/build.yml) [![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15513/badge)](https://www.bestpractices.dev/projects/15513) [![REUSE status](https://api.reuse.software/badge/github.com/tokenpandadev/tokenpanda-app)](https://api.reuse.software/info/github.com/tokenpandadev/tokenpanda-app) [![macOS 14 and later](https://img.shields.io/badge/macOS-14%2B-b1b9f9?style=flat-square)](#install)

![The menu bar with the tokenpanda item at the top right and its popover open on the Claude tab, sample figures for Thursday 14:20](docs/shots/hero.jpg)

Every time I looked at a usage percentage I did the same sum in my head. It is Thursday afternoon, 61 percent is gone, the week resets Sunday evening. Am I ahead of the clock or behind it? When does it run out if I keep going like this? So the popover says it in words and in clock time, not as a gauge.

## What it shows

- The pace in words: Ahead, On pace or Over pace, the clock time the limit lands if nothing changes, and what is left per hour.
- The 5h window and the week, each as a bar with a tick where the clock stands and the reset as a clock time.
- Open Claude Code sessions, each with its context window as a bar.
- Tokens by model, project and session, counted from the transcripts already on the Mac, with the list price equivalent, totals for today, 7 days and 30 days, and week over week.
- The Mac on a second tab: CPU, GPU, memory with pressure and swap, battery, the busiest processes.
- A switch in Settings, off by default, keeps the Mac from idle sleep while a Claude Code session is working, and says so while it does. A second switch under it keeps it awake while any session is open, idle ones too, so a session stays reachable through Remote Control from the phone. It prevents idle sleep only: a closed lid on battery still sleeps the Mac.
- Two nudges, one notification each, once per window: when the week reaches 80%, and in the 15 minutes before the 5h window ends. The Nudge switch in Settings turns them off, and Notifications must be allowed for tokenpanda in System Settings.
- Open at login, the first row in Settings, off by default. The box shows what macOS says, so if you remove the app in System Settings, General, Login Items, it shows that too.
- Reopen sessions after a restart, a switch in Settings, off by default. When the Mac comes back, one notification names the Claude Code sessions that were open before (by their name, or their folder when they have none). At login macOS can cover that notice with its Login Item Added banner, so it comes once more the first time you open the panel, if the sessions still wait. Reopen opens each one in Terminal, iTerm or Ghostty, as picked under "Open sessions in", as it was started: `claude --resume` with its name and its start options (extra folders, appended system prompt, model, permission mode and the rest; an option whose value is inline JSON is not kept), and with Remote Control again for sessions that had it. A start prompt typed after the options is not sent again. If that start fails within 20 seconds, the same without Remote Control follows, then a plain `claude --resume`. It waits for the network first, so Remote Control can connect. Only the Reopen button starts sessions; a click on the notification opens the panel. A session whose folder is gone is skipped, and one notification says how many did not reopen and why. With the switch on, a session that ends while its window stays open (it quit on its own, or you quit it there) gets one notification with its name and a Reopen button; a closed window or a shutdown gets none. One thing tokenpanda cannot stop: if "Reopen windows when logging back in" is ticked in the macOS restart dialog, macOS also brings back the old terminal windows, empty. Untick it once, and only the reopened sessions come back.

<img src="docs/shots/item-states.png" width="609" alt="The menu bar item in five states: ahead, stale, cpu warning, no feed yet, closed">

The menu bar item: the panda and the weekly percentage, dimmed when the figures are older than an hour.

<img src="docs/shots/item-limits.png" width="305" alt="The menu bar item at a limit: x x eyes for the weekly limit, - - eyes for the 5h limit">

When a window is used up, the panda's eyes say so until it resets: x x for the weekly limit, - - for the 5h window.

![The popover on its three tabs: Claude, Mac and Settings](docs/shots/tabs.png)

The three tabs: Claude, Mac and Settings.

## Install

It runs on a Mac with Apple silicon (M1 or later) on macOS 14 or later.

Download `tokenpanda-<version>.zip` and `tokenpanda-<version>.zip.sha256` from the [releases page](https://github.com/tokenpandadev/tokenpanda-app/releases), then check the zip in the folder you saved both to:

```sh
shasum -a 256 -c tokenpanda-<version>.zip.sha256
```

It should print `OK`. Unzip it and move `tokenpanda.app` to Applications.

The app is signed ad hoc, not notarised, so macOS blocks it the first time. Open System Settings, Privacy & Security, scroll down and click Open Anyway. The warning comes back once more: click Open Anyway again and enter your Mac password or use Touch ID. From then on it opens normally. On macOS 26 and later, if the item does not show in the menu bar, allow it in System Settings under Menu Bar.

With Homebrew, from my tap:

```sh
brew install --cask tokenpandadev/tap/tokenpanda
```

Homebrew trusts a cask installed by its full name, and only that one, so there is no trust step. The Open Anyway steps above apply after a Homebrew install too.

On first launch the Claude tab offers one button, Install the status line entry. Click it, start a Claude Code session, and the figures arrive after the first reply. If you already have a status line, it keeps working.

If you use more than one settings folder, Install writes the entry into ~/.claude, a `CLAUDE_CONFIG_DIR` folder the app can see, and `~/.config/claude` or any `~/.claude-something` folder that holds a settings.json; those sessions feed too. Install lists the folders before you click. A folder with only transcripts in it, such as a backup copy, is left out; to include one, put a settings.json in it. A folder made later shows up in Settings as Install again.

When a session does not show up:

- Workspace trust: Claude Code runs no status line in a folder until you accept its workspace trust dialog.
- A `statusLine` in a project's `.claude/settings.json` or `.claude/settings.local.json`, or in managed settings, wins over yours for that project, so those sessions do not feed. So does `disableAllHooks` set there.
- Sessions in the VS Code or JetBrains extension, in the desktop app, and `claude -p` runs most likely run no status line, so they do not feed the windows. Their tokens are still counted from the transcripts.
- Each Mac feeds only itself. Use on the web, in the Claude app or on another Mac moves the limits, and the app sees it with the next Claude Code reply on this Mac.

To uninstall with Homebrew, `brew uninstall --zap tokenpanda` puts your previous status line back before it deletes the app's data (once 0.1.9 or later has run; it runs the remove script the app keeps in its data folder). With a plain `brew uninstall`, click "Remove the status line entry" in Settings first.

## Update

tokenpanda never checks for updates itself. With Homebrew: `brew upgrade --cask tokenpandadev/tap/tokenpanda`. From a download: quit tokenpanda and replace tokenpanda.app in Applications with the new one. Your status line entry stays. macOS blocks a downloaded update once more, so click Open Anyway as on the first launch.

## Known issues

- Not notarised yet, so you click Open Anyway on the first launch and after each downloaded update.
- A new Ultra user sees a 5h row until the first reply.
- The "session ended" notice also comes when you quit a session on purpose.
- When Reopen uses Ghostty, it asks before each session. iTerm asks until you tick Suppress.

## By the rules

- It reads the status line, the one feed Claude Code documents for exactly this, and nothing else. The plan figures are four fields in it: `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and `resets_at`.
- The token figures come from the transcripts Claude Code keeps on the Mac in `~/.claude/projects`. Counts, model and time. Never what was written.
- No login. No token. No endpoint. No network at all.

The plan figures are as fresh as the last running session. Between sessions the popover shows the last figures with the time they were read. If Claude Code renames one of those fields, or sends a percentage as text, the Claude tab says "the feed format changed, update tokenpanda". When no transcripts folder is found, it says "No transcripts in" and names each folder it looked in.

## Privacy

Nothing leaves your Mac. In five rules:

1. The app makes no network calls and works offline: no analytics, no telemetry, no update check, no price fetch.
2. From a transcript line it keeps the line type, the time, the ids, the model, the working directory name and the token counts. Not what you wrote, not what Claude answered, not what the tools returned.
3. It never opens `memory/` or `tool-results/`, never reads the Keychain, a token or a cookie, and never asks you to sign in.
4. It writes files only in its own folder in Application Support and in its preferences. It touches `settings.json` in `~/.claude` (and in each other settings folder) only when you click, and only its `statusLine` key. "Remove the status line entry" in Settings puts your previous entry back exactly. The file docs/privacy.html in the repository lists every file.
5. Check it. The source is public; search it for URLSession. Run nettop on the app for an hour: zero connections.

With keep awake on, the app holds a power assertion only while a session is working, or with the second switch while a session is open, and `pmset -g assertions` shows it. With Open at login on, macOS lists the app in System Settings, General, Login Items; the app keeps no setting of its own for it. To show each open session by its name, the app reads Claude Code's own small session files (`~/.claude/sessions/<process id>.json`, and the same in each other settings folder: session id, folder, name). With Reopen sessions on, the app keeps a small list of the open sessions in Application Support: id, folder, settings folder, transcript path, name, start options and when it was last seen. A start option whose value is inline JSON is never kept, because such a value can carry a key or a token. The app starts Terminal, iTerm or Ghostty only when you click Reopen. The steps go to the macOS log: how many sessions were offered and opened, a code for each one skipped, and the names of any options left out; no ids or paths.

The file [docs/privacy.html](docs/privacy.html) in the repository names every file it reads and writes; it is HTML, so open it in a browser from a download of the repository. Anthropic documents the status line feed as input for any script you configure. It has written nothing either way about a local tool reading the transcripts on your own Mac. That is silence, not permission.

The [audit report](https://tokenpanda.dev/audit) is my own audit, run with AI agents against OWASP ASVS 5.0.0 Level 2, not an outside audit; it names the version it checked and every finding.

## Build from source

You need a Mac on macOS 14 or later with the Command Line Tools or Xcode. Swift 6 is required; nothing else is downloaded.

```sh
swift build
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
scripts/build-app.sh 0.1.19
open build/tokenpanda.app
```

The plugin flag is for the Command Line Tools, which ship swift-testing without telling the compiler where its macro plugin lives. With Xcode selected, plain `swift test` works. `scripts/build-app.sh` builds the release binary, assembles `build/tokenpanda.app`, signs it ad hoc, and writes `build/tokenpanda-<version>.zip` with its SHA-256. A debug build also takes `--snapshot <folder>`, which renders every tab and state of the sample data to PNG, and `--snapshot-stage white` with it, for checking contrast over a bright desktop.

The documentation is plain HTML in `docs/`: an overview, the style guide, the spec, the privacy page, and the manual VoiceOver and keyboard test in `docs/testing.html`. Changes per version are in [CHANGELOG.md](CHANGELOG.md).

## Tools that came first

I learned from the tools that came before this one. They are credited on [tokenpanda.dev/tools](https://tokenpanda.dev/tools).

## Licence and coffee

MIT, see [LICENSE](LICENSE). Issues and ideas welcome.

If it saved you a limit once, a coffee on [Ko-fi](https://ko-fi.com/tokenpanda) is welcome, never required. GitHub Sponsors follows once GitHub approves it.

Made by halftone
