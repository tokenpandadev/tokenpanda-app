#!/bin/zsh
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# Before a push or a tag: every step CI runs, here, plus the checks earlier releases missed.
#   scripts/preflight.sh [base]   base: the commit the new commits start from (default origin/main)
# Stops at the first failure. Needs swiftlint and reuse on PATH; Xcode is used when installed.
set -eu
cd "$(dirname "$0")/.."
BASE="${1:-origin/main}"
SCRATCH="${TMPDIR:-/tmp}/tokenpanda-preflight"
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
step() { print "== $1"; }
# checks added 05.11.2026 from the release lessons warn only until they have run clean on a few releases; STRICT=1 makes them fail
WARNS=0
warn() { print "WARN: $1"; WARNS=$((WARNS + 1)); [ -z "${STRICT:-}" ] || exit 1; }

step "release check (CI)";          sh scripts/release-check.sh
step "CI steps all covered here";   python3 -I scripts/ci-lines.py || warn "a CI step is new or changed: run it here or name why not in scripts/ci-lines.txt"
# the newest CHANGELOG section as release.yml reads it at the tag: dated, not unreleased, not empty
step "CHANGELOG";                   heading=$(grep -m1 '^## [0-9]' CHANGELOG.md)
                                    case "$heading" in "## "[0-9]*.[0-9]*.[0-9]*", 20"[0-9][0-9]-[01][0-9]-[0-3][0-9]*) ;; *) warn "newest CHANGELOG heading has no version and date: $heading";; esac
                                    case "$heading" in *unreleased*) warn "CHANGELOG still says: $heading";; esac
                                    awk -v h="${heading%%,*}," 'index($0, h) == 1 {on=1; next} /^## / {on=0} on' CHANGELOG.md | grep -q '[^[:space:]]' || warn "the newest CHANGELOG section is empty"
step "lint (CI)";                   swiftlint lint --strict --quiet
# a fresh scratch folder for this build: a module cached from an earlier build is not compiled again and hides its warnings
FRESH=$(mktemp -d "${TMPDIR:-/tmp}/tokenpanda-preflight-fresh.XXXXXX")
trap 'rm -rf "$FRESH"' EXIT
step "build (CI), warnings fail";   out=$(swift build --scratch-path "$FRESH" 2>&1) || { print -r -- "$out"; exit 1; }
                                    if print -r -- "$out" | grep -v "ld: warning: search path" | grep -q "warning:"; then print -r -- "$out" | grep "warning:"; exit 1; fi
                                    rm -rf "$FRESH"
# a test that compares clock times passed here and failed in CI, which runs in UTC (0.1.15)
for zone in "" UTC America/Los_Angeles; do
  step "tests ${zone:-Mac zone}";   TZ="${zone:-$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')}" swift test --scratch-path "$SCRATCH" > "$SCRATCH.test.log" 2>&1 && rc=0 || rc=$?
                                    tail -1 "$SCRATCH.test.log"; [ "$rc" = 0 ] || exit 1
                                    # the Swift runtime logs isolation failures and goes on; a passing run can still carry them (0.1.16)
                                    n=$(grep -ciE "data race detected|incorrect actor executor|isolation" "$SCRATCH.test.log") || true
                                    [ "$n" = 0 ] || warn "$n isolation warnings in the test log $SCRATCH.test.log"
done
# the app under many sessions: CPU and isolation failures no unit test sees (0.1.16)
step "tests leave no folders";       left=$(find /tmp/ "${TMPDIR:-/tmp}/" -maxdepth 1 \( -name 'tokenpanda-test-run-*' -o -name 'tokenpanda-tests-*' -o -name 'tokenpanda-tload.*' \) 2>/dev/null | wc -l | tr -d ' '); [ "$left" = 0 ] || warn "$left test folders left in /tmp: the test temp root did not clean up"
step "load test, 22 sessions";      swift build -c release --scratch-path "$SCRATCH-release" 2>&1 | tail -1
                                    lt=$(scripts/load-test.sh "$SCRATCH-release/release/tokenpanda" 60 5) && rc=0 || rc=$?
                                    print -r -- "$lt"; [ "$rc" = 0 ] || exit 1
                                    case "$lt" in *"load test: WARN"*) warn "the load test may have touched the user's real temp folder";; esac
# the open panel's transcript pass at a heavy user's size, which the 22-session test has no history for (0.1.18; warn first)
step "transcript load, a heavy month"; tl=$(zsh scripts/transcript-load-test.sh 30 6) || warn "transcript load test failed or over its limit"
                                    print -r -- "$tl" | tail -1
step "REUSE";                       reuse lint --quiet || { reuse lint | tail -20; exit 1; }
# no trace of the tools that wrote the code in commit messages; the product name Claude Code is fine
TRACES='co-authored-by:.*claude|claude-session|claude\.ai/code|generated with'
step "commit messages since $BASE"; if git log "$BASE"..HEAD --format=%B | grep -qiE "$TRACES"; then
                                      for c in $(git log "$BASE"..HEAD --format=%h); do git log -1 --format=%B "$c" | grep -qiE "$TRACES" && git log -1 --format='%h %s' "$c"; done
                                      print "a commit message carries a tool trace"; exit 1; fi
# every outside link in the README answers (a REUSE link sat at 404 for weeks)
step "no private words in commit messages"; git log "$BASE"..HEAD --format=%B | python3 -I scripts/private-words.py --text || { print "a commit message names a private word"; exit 1; }
step "README links";                for u in $(grep -oE 'https://[^) "]+' README.md | sort -u); do
                                      c=$(curl -s -o /dev/null -L -m 15 -w '%{http_code}' "$u") || c=000
                                      if [ "$c" = 403 ]; then print "403 $u (refuses scripts; open it in a browser once)"
                                      elif [ "$c" -ge 400 ] || [ "$c" = 000 ]; then print "$c $u"; bad=1; fi
                                    done; [ -z "${bad:-}" ] || exit 1
# every place the app writes or deletes, and no launcher that leaves the real temp folder in a test run (05.11)
step "write places";                python3 -I scripts/write-places.py || warn "a write or delete place is new, or a launcher misses TMPDIR: see scripts/write-places.txt"
# a stand-in app named like a real one, left in a temp folder, made macOS call that app damaged (05.11)
step "no fake apps in temp folders"; python3 -I scripts/fake-apps.py || warn "move them out of the temp folders before reporting the run"
[ "$WARNS" = 0 ] && print "preflight: all passed" || print "preflight: passed with $WARNS warnings"
