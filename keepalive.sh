#!/usr/bin/env bash
# Keep a free instabox sandbox effectively always-on.
#
# Two limits must be defeated:
#   1. idle auto-pause   — a free box pauses after 30 min with no activity.
#   2. max-run 480 min   — a free box is force-paused after 8h of runtime,
#                          then a 10-min cooldown blocks any wake.
#
# Strategy, run on a schedule (GitHub Actions cron, every ~10 min):
#   - if paused/stopped, wake it;
#   - run a trivial command to register activity (resets the idle timer);
#   - if runtime is close to the 8h cap, suspend+resume BEFORE the forced
#     pause so we never hit the cooldown; suspend/resume keeps processes
#     and resets both timers.
#
# Requires: INSTABOX_API_KEY (scope machines:write), INSTABOX_BOX (name or id).
set -euo pipefail

: "${INSTABOX_API_KEY:?set INSTABOX_API_KEY}"
: "${INSTABOX_BOX:?set INSTABOX_BOX (sandbox name or id)}"

# Rotate this many minutes before the 480-min cap. 7h = 420 min leaves slack
# for cron delay (GitHub cron can lag 10-15 min).
ROTATE_BEFORE_MIN="${ROTATE_BEFORE_MIN:-60}"

ib() { instabox "$@"; }

echo "::group::status"
ib get "$INSTABOX_BOX" --json | tee /tmp/box.json | \
  jq -r '"state=\(.state) runStartedAt=\(.runStartedAt) maxRunMinutes=\(.maxRunMinutes) cooldownUntil=\(.cooldownUntil)"'
echo "::endgroup::"

state=$(jq -r '.state' /tmp/box.json)
cooldown=$(jq -r '.cooldownUntil // empty' /tmp/box.json)

if [ -n "$cooldown" ]; then
  echo "box in cooldown until $cooldown; nothing to do this run"
  exit 0
fi

# Wake if not running.
if [ "$state" != "running" ]; then
  echo "state=$state -> waking"
  ib wake "$INSTABOX_BOX" || ib resume "$INSTABOX_BOX" || ib start "$INSTABOX_BOX"
  ib get "$INSTABOX_BOX" --json > /tmp/box.json
fi

# Register activity (resets the 30-min idle timer).
ib ssh "$INSTABOX_BOX" -- 'true' >/dev/null 2>&1 && echo "activity registered"

# Decide whether to rotate to reset the 8h runtime timer.
started=$(jq -r '.runStartedAt // empty' /tmp/box.json)
maxrun=$(jq -r '.maxRunMinutes // 480' /tmp/box.json)
if [ -n "$started" ] && [ "$maxrun" -gt 0 ]; then
  start_s=$(date -u -d "$started" +%s 2>/dev/null || python3 - "$started" <<'PY'
import sys,datetime
print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))
PY
)
  now_s=$(date -u +%s)
  elapsed_min=$(( (now_s - start_s) / 60 ))
  threshold=$(( maxrun - ROTATE_BEFORE_MIN ))
  echo "runtime ${elapsed_min}m / ${maxrun}m (rotate at ${threshold}m)"
  if [ "$elapsed_min" -ge "$threshold" ]; then
    echo "approaching runtime cap -> suspend+resume to reset timer"
    ib suspend "$INSTABOX_BOX"
    ib resume "$INSTABOX_BOX"
    echo "rotated"
  fi
fi

echo "done"
