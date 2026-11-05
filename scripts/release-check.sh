#!/bin/sh
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
# Release check: no leftover placeholder text and no absolute home path in any text file of the repository:
# the files git tracks plus new files not ignored, so local caches (node_modules, build output) are never read.
# The one allowed home path is the generic example /Users/someone in tests and fixtures.
# Casks/tokenpanda.rb is skipped: its RELEASE_VERSION and RELEASE_SHA256 are set by each release.
#   scripts/release-check.sh
cd "$(dirname "$0")/.." || exit 2
files() { git ls-files -z --cached --others --exclude-standard | grep -zvE '(^|/)(release-check\.sh|tokenpanda\.rb)$'; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "release check: not a git checkout"; exit 2; }
PLACEHOLDERS=$(files | xargs -0 grep -niIE 'goes here|placeholder|<app>|no name yet|the owner' 2>/dev/null)
PATHS=$(files | xargs -0 grep -nIE '/Users/[A-Za-z0-9._-]' 2>/dev/null | sed 's#/Users/someone##g' | grep -E '/Users/[A-Za-z0-9._-]')
if [ -n "$PLACEHOLDERS$PATHS" ]; then
  [ -n "$PLACEHOLDERS" ] && { echo "placeholders:"; echo "$PLACEHOLDERS"; }
  [ -n "$PATHS" ] && { echo "absolute paths:"; echo "$PATHS"; }
  exit 1
fi
echo "release check: 0 hits"
