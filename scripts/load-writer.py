#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tokenpanda
# SPDX-License-Identifier: MIT
"""22 synthetic Claude Code sessions: each session's snapshot is rewritten every 300 ms (tmp file, then mv, as hook.sh
does). Half the sessions move their figures on every write (working), half write the same figures (idle). A fake
Claude Code session registry (home/.claude/sessions/<pid>.json) points at 22 sleeping child processes.
  writer.py <fixture json> <data dir> <home dir> <seconds>"""
import json, os, sys, time, subprocess, signal
signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))   # so the finally below stops the children and prints the count
fixture, data, home, seconds = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
base = json.load(open(fixture))
sdir = os.path.join(data, "sessions"); os.makedirs(sdir, exist_ok=True)
rdir = os.path.join(home, ".claude", "sessions"); os.makedirs(rdir, exist_ok=True)
now = int(time.time())
N = 22
kids = [subprocess.Popen(["sleep", str(int(seconds) + 30)]) for _ in range(N)]
sessions = []
for i in range(N):
    sid = "3f1a9c2e-0000-4000-8000-%012d" % (i + 1)
    snap = json.loads(json.dumps(base))
    snap["session_id"] = sid
    snap["cwd"] = "/tmp/work/project-%d" % i
    snap["workspace"]["current_dir"] = snap["cwd"]
    snap["context_window"]["used_percentage"] = (i * 4) % 100
    snap["rate_limits"] = {"five_hour": {"used_percentage": 31, "resets_at": now + 3 * 3600},
                           "seven_day": {"used_percentage": 13, "resets_at": now + 3 * 86400}}
    sessions.append(snap)
    reg = {"pid": kids[i].pid, "sessionId": sid, "cwd": snap["cwd"], "name": "session %d" % i, "nameSource": "user",
           "kind": "interactive", "entrypoint": "cli", "startedAt": now * 1000}
    json.dump(reg, open(os.path.join(rdir, "%d.json" % kids[i].pid), "w"))
period = 0.3
end = time.time() + seconds
writes = 0
try:
    while time.time() < end:
        t0 = time.time()
        for i, snap in enumerate(sessions):
            if i % 2 == 0:
                snap["cost"]["total_cost_usd"] += 0.001
                snap["context_window"]["current_usage"]["output_tokens"] += 7
            p = os.path.join(sdir, snap["session_id"] + ".json")
            with open(p + ".tmp", "w") as f: f.write(json.dumps(snap, separators=(",", ":")))
            os.replace(p + ".tmp", p)
            writes += 1
            time.sleep(period / N)
        time.sleep(max(0, period - (time.time() - t0)))
finally:
    for k in kids: k.kill()
    print("writes", writes, flush=True)
