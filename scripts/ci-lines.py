#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""Every `run:` step of the CI workflows, and how preflight covers it.
A step whose text is not in scripts/ci-lines.txt is new or changed: run it here, or name why it cannot run here,
then add its line to ci-lines.txt (`python3 -I scripts/ci-lines.py --list` prints the fingerprints).
Exit 1 when a step is not listed."""
import glob, hashlib, os, re, sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

def steps():
    for f in sorted(glob.glob(".github/workflows/*.yml")):
        lines = open(f, encoding="utf-8").read().split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"^(\s*)(?:- )?run:\s*(.*)$", line)
            if not m:
                continue
            indent, value = len(m.group(1)), m.group(2).strip()
            if value in ("|", ">", "|-", ">-"):
                body = []
                for nxt in lines[i + 1:]:
                    if nxt.strip() and len(nxt) - len(nxt.lstrip()) <= indent:
                        break
                    if nxt.strip():
                        body.append(nxt.strip())
                value = "\n".join(body)
            yield f, i + 1, value

known = {}
for line in open("scripts/ci-lines.txt", encoding="utf-8"):
    if line.strip() and not line.startswith("#"):
        fp, _, note = line.strip().partition(" ")
        known[fp] = note

missing = 0
for f, n, text in steps():
    fp = hashlib.sha256(text.encode()).hexdigest()[:12]
    first = text.split("\n")[0]
    if "--list" in sys.argv:
        print(f"{fp} {f}:{n} {first[:70]}")
    elif fp not in known:
        print(f"not in ci-lines.txt: {f}:{n} {first[:70]} ({fp})")
        missing += 1
sys.exit(1 if missing else 0)
