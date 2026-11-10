#!/bin/bash
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# Load test: the app under 22 Claude Code sessions writing their status line every 0.3 s, in a throwaway home under /tmp
# (never the real ~/.claude, data folder, temp folder or preferences: CFFIXED_USER_HOME, TMPDIR, settings in the argument domain).
# Fails when the app uses more than MAX_CPU percent of one core, or when the Swift runtime logs any isolation failure
# ("data race detected"): 0.1.15 used 76.6% here and logged about 7,000 a minute, and no other check saw either.
#   scripts/load-test.sh <app binary> [seconds] [max cpu percent]
set -u
BIN=$1; SECS=${2:-60}; MAX_CPU=${3:-5}
cd "$(dirname "$0")/.." || exit 2
H=$(mktemp -d /tmp/tokenpanda-load.XXXXXX)
trap 'kill $AP $WP 2>/dev/null; wait 2>/dev/null; rm -rf "$H"' EXIT
mkdir -p "$H/home/.claude" "$H/tmp"
# an old Reopen folder in the throwaway temp folder: the app's launch cleanup must remove it, which proves it used TMPDIR
mkdir "$H/tmp/tokenpanda-reopen-loadtest" && touch -t 202601010000 "$H/tmp/tokenpanda-reopen-loadtest"
DATA="$H/home/Library/Application Support/dev.tokenpanda.app"; mkdir -p "$DATA/sessions"
python3 -I scripts/load-writer.py Tests/tokenpandaTests/Fixtures/feed-sample.json "$DATA" "$H/home" $((SECS + 15)) > "$H/writer.log" 2>&1 &
WP=$!
sleep 2
# proof the run kept out of the user's real temp folder: its Reopen folders are the same before and after
REAL_TMP=$(getconf DARWIN_USER_TEMP_DIR)
real_reopen() { ls -d "$REAL_TMP"tokenpanda-reopen-* 2>/dev/null | sort; }
BEFORE=$(real_reopen)
# the temp folder does not follow CFFIXED_USER_HOME: without its own TMPDIR the app's launch cleanup of old Reopen
# folders runs in the user's real temp folder (05.11.2026)
env -u CLAUDE_CONFIG_DIR CFFIXED_USER_HOME="$H/home" TMPDIR="$H/tmp/" "$BIN" -nudges NO -keepAwake NO -keepAwakeWhileOpen NO -restoreSessions NO \
    -macFiguresInBar NO -listPriceEquivalent YES > "$H/app.log" 2>&1 &
AP=$!
sleep 10   # the launch settles: first transcripts pass, first scans
kill -0 $AP 2>/dev/null || { echo "load test: the app did not start"; cat "$H/app.log"; exit 1; }
T0=$(ps -o time= -p $AP); S0=$(date +%s)
sleep "$SECS"
T1=$(ps -o time= -p $AP); S1=$(date +%s); RSS=$(ps -o rss= -p $AP)
[ ! -e "$H/tmp/tokenpanda-reopen-loadtest" ] || echo "load test: WARN the app did not clean its own TMPDIR, so it may be using the user's real temp folder"
[ "$(real_reopen)" = "$BEFORE" ] || echo "load test: WARN the user's real temp folder changed (Reopen folders before: $(echo "$BEFORE" | grep -c .), after: $(real_reopen | grep -c .))"
RACES=$(grep -ci "data race detected\|isolation" "$H/app.log")
python3 -I - "$T0" "$T1" "$S0" "$S1" "$RSS" "$RACES" "$MAX_CPU" <<'PY'
import sys
def sec(t):
    s = 0.0
    for x in t.strip().split(":"): s = s * 60 + float(x)
    return s
t0, t1, s0, s1, rss, races, cap = sys.argv[1:]
cpu = 100 * (sec(t1) - sec(t0)) / (int(s1) - int(s0))
print(f"load test: 22 sessions, {cpu:.2f}% of one core (limit {cap}%), {int(rss)//1024} MB, {races} isolation warnings")
sys.exit(0 if cpu <= float(cap) and int(races) == 0 else 1)
PY
