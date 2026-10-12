#!/bin/bash
# ChatGPT/Codex usage for the Touch Bar widget.
#
# Same --raw contract as claude-touchbar.sh:
#   "<5h%> <7d%> <resetMin> <ageSec> <state> <scopedPct> <scopedName>
#    <reset7Min> <reset5Epoch> <reset7Epoch>"
# Codex reports real reset timestamps, so the epochs are filled in and the
# widget shows clock times for GPT instead of countdowns.
#
# Source: the newest ~/.codex/sessions rollout log. Codex writes a
# `rate_limits` object (primary/secondary windows) into every token_count
# event. Local file read only — no network, no token, auth.json is never opened.
# The numbers are only as fresh as the last Codex turn; AGE says how old.
#
# Windows are matched by window_minutes (300 = 5h, 10080 = 7d), never by
# primary/secondary position.
set -uo pipefail

PY=/usr/bin/python3
[ -x "$PY" ] || PY=$(command -v python3) || { echo "0 0 -1 -1 none -1 - -1 0 0"; exit 0; }

exec "$PY" -I - "${CODEX_HOME:-$HOME/.codex}/sessions" <<'EOF'
import json, os, sys, time

root = sys.argv[1]

def newest_with_limits():
    files = []
    for d, _, fs in os.walk(root):
        files += [os.path.join(d, f) for f in fs if f.endswith(".jsonl")]
    files.sort(key=os.path.getmtime, reverse=True)
    for p in files[:20]:                      # a few newest; skip logs with no turn yet
        try:
            lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        for l in reversed(lines):
            if "rate_limits" not in l:
                continue
            try:
                e = json.loads(l)
            except ValueError:
                continue
            pl = e.get("payload") or {}
            rl = pl.get("rate_limits") or e.get("rate_limits")
            if isinstance(rl, dict) and (rl.get("primary") or rl.get("secondary")):
                return rl, e.get("timestamp"), os.path.getmtime(p)
    return None, None, 0

rl, ts, mtime = newest_with_limits()
if not rl:
    print("0 0 -1 -1 none -1 - -1 0 0"); sys.exit(0)

now = time.time()
age = max(0, int(now - mtime))
p5 = p7 = -1
reset = reset7 = -1
e5 = e7 = 0
for w in (rl.get("primary"), rl.get("secondary")):
    if not isinstance(w, dict):
        continue
    used, mins, at = w.get("used_percent"), w.get("window_minutes"), w.get("resets_at")
    if not isinstance(used, (int, float)):
        continue
    if isinstance(at, (int, float)) and at < now:
        used = 0                              # window rolled over since the log line
    if mins == 300:
        p5 = round(used)
        if isinstance(at, (int, float)) and at >= now:
            reset = round((at - now) / 60)
            e5 = int(at)
    elif mins == 10080:
        p7 = round(used)
        if isinstance(at, (int, float)) and at >= now:
            reset7 = round((at - now) / 60)
            e7 = int(at)

if p5 < 0 and p7 < 0:
    print("0 0 -1 -1 none -1 - -1 0 0"); sys.exit(0)

state = "stale" if age > 3600 else "ok"       # Codex idle for an hour: say so
print(f"{max(p5,0)} {max(p7,0)} {reset} {age} {state} -1 - {reset7} {e5} {e7}")
EOF
