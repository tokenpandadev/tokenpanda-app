#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""Transcripts at a heavy user's size in a throwaway home, for the transcript load measure (0.1.18).
A month of heavy use measured on 10.11.2026: 863 transcript files touched in 32 days, about 150,000 assistant lines.

  scripts/transcript-load.py <throwaway home> [files] [records]          write <home>/.claude/projects
  scripts/transcript-load.py <throwaway home> --append <seconds> [live]  then add one line a second to <live> sessions

Refuses any home that is not under a temp folder, so it can never write into a real ~/.claude."""
import json, os, random, sys, time
from datetime import datetime, timedelta, timezone

home = os.path.realpath(sys.argv[1])
if not (home.startswith("/private/tmp/") or home.startswith("/private/var/folders/")):
    sys.exit(f"refused: {home} is not under a temp folder")
root = os.path.join(home, ".claude", "projects")
MODELS = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1", "claude-opus-4-1"]
rng = random.Random(7)


def line(i, ts, session, cwd):
    u = {"input_tokens": rng.randint(1, 900), "cache_creation_input_tokens": rng.randint(0, 40000),
         "cache_read_input_tokens": rng.randint(0, 900000), "output_tokens": rng.randint(1, 8000),
         "cache_creation": {"ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": rng.randint(0, 40000)}}
    m = {"model": rng.choice(MODELS), "id": f"msg_{session}_{i}", "type": "message", "role": "assistant",
         "content": [{"type": "text", "text": "ok"}], "usage": u}
    return json.dumps({"parentUuid": "x", "isSidechain": rng.random() < 0.2, "message": m, "requestId": f"req_{session}_{i}",
                       "type": "assistant", "uuid": "u", "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%S.000Z"), "cwd": cwd,
                       "sessionId": session, "version": "2.1.300"}, separators=(",", ":")) + "\n"


def sessions():
    out = []
    for d in sorted(os.listdir(root)):
        for f in sorted(os.listdir(os.path.join(root, d))):
            out.append(os.path.join(root, d, f))
    return out


if "--append" in sys.argv:
    k = sys.argv.index("--append")
    secs = float(sys.argv[k + 1]); live = int(sys.argv[k + 2]) if len(sys.argv) > k + 2 else 12
    files = sessions()[-live:]
    end = time.time() + secs; i = int(time.time() * 1000) * 100   # ids never repeat across runs
    while time.time() < end:
        for f in files:
            s = os.path.basename(f)[:-6]
            with open(f, "a") as fh:
                fh.write(line(i, datetime.now(timezone.utc), s, "/work/" + os.path.basename(os.path.dirname(f))))
            i += 1
        time.sleep(1)
    sys.exit(0)

nfiles = int(sys.argv[2]) if len(sys.argv) > 2 else 863
nrec = int(sys.argv[3]) if len(sys.argv) > 3 else 150_000
now = datetime.now(timezone.utc)
per = max(1, nrec // nfiles)
for n in range(nfiles):
    proj = f"-work-project-{n % 40:02d}"
    os.makedirs(os.path.join(root, proj), exist_ok=True)
    session = f"{n:08d}-0000-4000-8000-{n:012d}"
    start = now - timedelta(days=30 * (n / nfiles))
    with open(os.path.join(root, proj, session + ".jsonl"), "w") as fh:
        for i in range(per):
            fh.write(line(i, start + timedelta(seconds=20 * i), session, "/work/" + proj))
    t = (start + timedelta(seconds=20 * per)).timestamp()
    os.utime(os.path.join(root, proj, session + ".jsonl"), (min(t, now.timestamp()), min(t, now.timestamp())))
print(f"{nfiles} files, {per * nfiles} assistant lines under {root}")
