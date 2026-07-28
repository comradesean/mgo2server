#!/usr/bin/env bash
# Watch the freebattle1 DEBUG log for a given command id and capture its payload the moment it
# arrives. Baseline-count based, so it is immune to the --since timezone bug (docker logs --since
# reads a bare timestamp as host-local while the container logs UTC).
#
# Requires the freebattle1 to be running at DEBUG (MGO2SERVER_LOG_LEVEL=DEBUG) so payloads are
# hex-dumped. Run it in the background of an agent session (run_in_background) so the agent is
# notified when the command fires.
#
# Usage:
#   dev/tools/watch_command.sh 4390            # watch for end-of-round stat reports
#   dev/tools/watch_command.sh 4310 20 mgo2server-freebattle1-1   # id, minutes, container
set -euo pipefail

CMD="${1:?usage: watch_command.sh <cmd-hex> [minutes] [container]}"
MINUTES="${2:-25}"
CONTAINER="${3:-mgo2server-freebattle1-1}"
NEEDLE="In  - command ${CMD}"

baseline() { docker logs "$CONTAINER" 2>&1 | grep -c "$NEEDLE" || true; }

BASE=$(baseline)
echo "Baseline '${NEEDLE}' count = $BASE. Watching up to ${MINUTES} min ..."
for _ in $(seq 1 $(( MINUTES * 12 ))); do
  CUR=$(baseline)
  if [ "$CUR" -gt "$BASE" ]; then
    sleep 3   # let siblings in the same burst land
    NEW=$(( $(baseline) - BASE ))
    echo "=== $NEW new 0x${CMD} packet(s) — payload hex follows ==="
    docker logs "$CONTAINER" 2>&1 | grep -A1 "$NEEDLE" | tail -n $(( NEW * 3 ))
    docker logs "$CONTAINER" 2>&1 | grep -E "stats for character|set relation|advanced to rotation" | tail -n "$NEW" || true
    exit 0
  fi
  sleep 5
done
echo "No new 0x${CMD} within ${MINUTES} min."
