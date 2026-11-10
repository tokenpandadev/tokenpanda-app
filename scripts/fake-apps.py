#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""App bundles under the temp folders that carry a real app's name or bundle id.
macOS registers any .app it sees; a test stand-in named like a real app made the Mac report that app as damaged (05.11.2026).
Read only. Exit 1 when one is found."""
import glob, os, plistlib, subprocess, sys

def info(app):
    try:
        with open(os.path.join(app, "Contents", "Info.plist"), "rb") as f:
            return plistlib.load(f).get("CFBundleIdentifier", "")
    except Exception:
        return ""

home = os.path.expanduser("~")
real = [a for d in ("/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", home + "/Applications") for a in glob.glob(d + "/*.app")]
names = {os.path.basename(a).lower() for a in real}
ids = {i.lower() for i in map(info, real) if i}

roots = sorted({os.path.realpath(r) for r in ("/tmp", os.environ.get("TMPDIR", "/tmp"))})
found = subprocess.run(["find", *roots, "-maxdepth", "9", "-type", "d", "-name", "*.app", "-prune"],
                       capture_output=True, text=True).stdout.splitlines()
hits = []
for p in found:
    s = os.path.basename(p)
    # only real bundles count: Python's bytecode cache copies app paths as plain folders (Library/Caches/com.apple.python)
    if "/Library/Caches/com.apple.python/" in p or not os.path.isfile(os.path.join(p, "Contents", "Info.plist")):
        continue
    bid = info(p).lower()
    if s.lower() in names or (bid and bid in ids):
        hits.append(f"{p} ({bid or 'no bundle id'})")
for h in sorted(hits):
    print("fake app under a temp folder:", h)
sys.exit(1 if hits else 0)
