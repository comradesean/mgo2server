#!/usr/bin/env bash
# Append every game-lobby container's log to a file that survives container recreation.
#
# `docker compose up -d --build` replaces containers and discards their logs with them; two live
# test sessions were lost that way on 2026-07-26. The docker log itself cannot be preserved, so
# this keeps its own copy: one follower per container, restarted automatically when a stream ends
# (which is exactly what a redeploy looks like from here).
#
# Usage:  dev/tools/capture_logs.sh [output-dir]     (default dev/analysis/logs)
# Stop:   kill the process group, or Ctrl-C in the foreground.
set -uo pipefail

OUT="${1:-$(dirname "$0")/../analysis/logs}"
mkdir -p "$OUT"

CONTAINERS=(
    mgo2server-gamelobby-1
    mgo2server-automatching-1
    mgo2server-basictraining-1
    mgo2server-combattraining-1
)

follow() {
    local name="$1" file="$OUT/$1.log"
    while true; do
        # --since 0 replays what the (possibly new) container already has, so a restart that
        # happens between polls does not leave a hole. Duplicates on restart are preferable to
        # gaps: this file is evidence, and a missing packet is indistinguishable from one that
        # was never sent.
        echo "=== follow start $(date -u +%FT%TZ) $name" >> "$file"
        docker logs -f --since 0 "$name" >> "$file" 2>&1
        echo "=== stream ended $(date -u +%FT%TZ) $name (container replaced or stopped)" >> "$file"
        sleep 2
    done
}

for c in "${CONTAINERS[@]}"; do follow "$c" & done
echo "Capturing ${#CONTAINERS[@]} containers into $OUT — survives redeploys. PIDs: $(jobs -p | tr '\n' ' ')"
wait
