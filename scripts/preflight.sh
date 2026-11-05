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

step "release check (CI)";          sh scripts/release-check.sh
step "lint (CI)";                   swiftlint lint --strict --quiet
step "build (CI), warnings fail";   out=$(swift build --scratch-path "$SCRATCH" 2>&1) || { print -r -- "$out"; exit 1; }
                                    if print -r -- "$out" | grep -v "ld: warning: search path" | grep -q "warning:"; then print -r -- "$out" | grep "warning:"; exit 1; fi
# a test that compares clock times passed here and failed in CI, which runs in UTC (0.1.15)
for zone in "" UTC America/Los_Angeles; do
  step "tests ${zone:-Mac zone}";   TZ="${zone:-$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')}" swift test --scratch-path "$SCRATCH" 2>&1 | tail -1
                                    [ "${pipestatus[1]}" = 0 ] || exit 1
done
step "REUSE";                       reuse lint --quiet || { reuse lint | tail -20; exit 1; }
# no trace of the tools that wrote the code in commit messages (his rule)
step "commit messages since $BASE"; if git log "$BASE"..HEAD --format=%B | grep -qi claude; then git log "$BASE"..HEAD --format='%h %s' | grep -i claude; print "a commit message names Claude"; exit 1; fi
# every outside link in the README answers (a REUSE link sat at 404 for weeks)
step "README links";                for u in $(grep -oE 'https://[^) "]+' README.md | sort -u); do
                                      c=$(curl -s -o /dev/null -L -m 15 -w '%{http_code}' "$u") || c=000
                                      if [ "$c" = 403 ]; then print "403 $u (refuses scripts; open it in a browser once)"
                                      elif [ "$c" -ge 400 ] || [ "$c" = 000 ]; then print "$c $u"; bad=1; fi
                                    done; [ -z "${bad:-}" ] || exit 1
print "preflight: all passed"
