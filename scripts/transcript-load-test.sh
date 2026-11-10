#!/bin/zsh
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# Transcript load test (0.1.18): the open panel's transcript pass every 2 s (five times the app's 10 s, so the share of a
# core it prints is five times the app's) over a heavy month (863 files, about 150,000
# assistant lines, as measured on 10.11.2026) while 12 sessions each add a line a second, in a throwaway home.
# The 22-session load test has no transcript history, so it never saw the pass that cost 11% of a core at that size.
#   scripts/transcript-load-test.sh [passes] [max cpu percent]
# Needs a debug build (the measuring mode exists only there); never runs the app's window, never reads the real ~/.claude.
set -u
PASSES=${1:-30}; MAX=${2:-6}
cd "${0:h}/.." || exit 2
H=$(mktemp -d "${TMPDIR:-/tmp}/tokenpanda-tload.XXXXXX")
AP=
trap 'kill ${AP:-} 2>/dev/null; wait 2>/dev/null; rm -rf "$H"' EXIT
mkdir -p "$H/home" "$H/tmp"
swift build -Xswiftc -O --scratch-path "$H/build" 2>&1 | tail -1
python3 -I scripts/transcript-load.py "$H/home" > /dev/null || exit 2
python3 -I scripts/transcript-load.py "$H/home" --append $((PASSES * 2 + 20)) 12 & AP=$!
out=$(env -u CLAUDE_CONFIG_DIR CFFIXED_USER_HOME="$H/home" HOME="$H/home" TMPDIR="$H/tmp/" perl -e 'alarm 300; exec @ARGV' \
      "$H/build/debug/tokenpanda" --transcript-passes "$PASSES" -nudges NO -keepAwake NO -keepAwakeWhileOpen NO -restoreSessions NO 2>&1 | tail -1)
print -r -- "transcript load: $out"
cpu=$(print -r -- "$out" | sed -nE 's/.*= ([0-9.]+)% of one core.*/\1/p')
[ -n "$cpu" ] || { print "transcript load: no figure; the measuring mode did not run"; exit 1; }
python3 -I -c "import sys; sys.exit(0 if float('$cpu') <= float('$MAX') else 1)" || { print "transcript load: $cpu% is over the limit of $MAX%"; exit 1; }
