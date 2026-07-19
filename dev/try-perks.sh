#!/usr/bin/env bash
# Sets the third field of the login reply and restarts the web server.
#
#   ./dev/try-perks.sh "$(printf '2000000000_%.0s' {1..10} | sed 's/_$//')"
#   ./dev/try-perks.sh ""        # back to the default
#
# Restart takes a couple of seconds and needs no rebuild, so values can be tried quickly
# against a real client.
set -euo pipefail
cd "$(dirname "$0")/.."
export NOMAD_DB_PORT=${NOMAD_DB_PORT:-55432} NOMAD_WEB_PORT=${NOMAD_WEB_PORT:-18080}
export NOMAD_GATE_PORT=${NOMAD_GATE_PORT:-15731} NOMAD_LOG_LEVEL=${NOMAD_LOG_LEVEL:-DEBUG}
export NOMAD_LOGIN_PERKS="${1-}"
docker compose up -d --force-recreate web >/dev/null 2>&1
sleep 4
echo -n "login reply: "
curl -sk -m 8 -X POST \
  -d "name=122345677&passwd=$(printf '1234' | md5sum | cut -d' ' -f1)&seed=a&np=t" \
  https://192.168.1.100/us/mgo2/kid/gidauth5.html
echo
