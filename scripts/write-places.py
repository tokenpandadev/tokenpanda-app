#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""Every place the app writes or deletes files, and every script that runs the app in a throwaway home.
A 0.1.16 test run used a throwaway home but the real temp folder, and the app's own cleanup deleted two of the
user's Reopen folders (05.11.2026). So:
1. Each write or delete call in Sources must be listed in scripts/write-places.txt with where it lands. A new or
   changed call is not listed: name where it writes, then add it (`--list` prints the keys).
2. Each script that starts the app with CFFIXED_USER_HOME must also point TMPDIR into that throwaway home, since
   the temp folder does not follow the home.
Read only. Exit 1 on a miss."""
import glob, hashlib, os, re, sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CALL = re.compile(r"temporaryDirectory|tempFolder\(|removeLeftovers\(|NSTemporaryDirectory|removeItem|trashItem|moveItem|copyItem|createDirectory|createFile|\.write\(to:|\.write\(toFile:|\"/tmp")

places = []
for f in sorted(glob.glob("Sources/**/*.swift", recursive=True)):
    for line in open(f, encoding="utf-8"):
        s = line.strip()
        if s.startswith("//") or not CALL.search(s):
            continue
        key = hashlib.sha256((f + "\n" + " ".join(s.split())).encode()).hexdigest()[:12]
        places.append((key, f, s))

known = {}
for line in open("scripts/write-places.txt", encoding="utf-8"):
    if line.strip() and not line.startswith("#"):
        k, _, where = line.strip().partition(" ")
        known[k] = where

if "--list" in sys.argv:
    for k, f, s in places:
        print(k, f, s[:90])
    sys.exit(0)

miss = 0
for k, f, s in places:
    if k not in known:
        print(f"not in write-places.txt: {f}: {s[:90]} ({k})")
        miss += 1
outside = sum(1 for k, _, _ in places if k in known and not known[k].startswith("data folder"))
print(f"write places: {len(places)} calls, {outside} land outside the app's data folder (listed in write-places.txt)")

# launchers: a throwaway home without its own temp folder
for f in sorted(set(glob.glob("scripts/*") + glob.glob("Tests/**/*.sh", recursive=True) + glob.glob("Tests/**/*.py", recursive=True))):
    if f.endswith(("write-places.py", "write-places.txt")) or not os.path.isfile(f):
        continue
    text = open(f, encoding="utf-8", errors="replace").read()
    if "CFFIXED_USER_HOME" in text and "TMPDIR" not in text:
        print(f"{f} starts the app in a throwaway home but leaves TMPDIR on the real temp folder")
        miss += 1
sys.exit(1 if miss else 0)
