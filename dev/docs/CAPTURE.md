# Live-capture harness

How to capture and decode packets off a real client without repeated emulator sessions. This is
the rig that mapped the Common Settings, the weapon restrictions, the `0x4390` scoreboard, and the
ADDLIST family — all against `BLUS30109` on RPCS3. Tools live in `dev/tools/`.

The method throughout: **enable DEBUG so payloads are hex-dumped, archive anything the client
overwrites, then correlate the bytes to what the client displays.** No Wireshark needed — the
server logs the decrypted payload.

## 1. Turn on packet tracing

Deploy the game servers with DEBUG logging; the decoder hex-dumps every payload it decrypts
(`GamePacketDecoder`, gated on `logger.isDebugEnabled()`):

```
MGO2SERVER_LOG_LEVEL=DEBUG docker compose up -d --build gamelobby
```

Every inbound command then logs `In  - command XXXX - N bytes` followed by the payload hex.

## 2. Archive what the client overwrites

Some state is overwritten on each push (the `0x4310` host-settings blob is upserted per character).
Install the audit trigger once so consecutive hosts do not clobber the evidence:

```
docker exec -i mgo2server-postgres-1 psql -U mgo2server -d mgo2server < dev/tools/blob_audit.sql
```

It archives every `0x4310` blob to a `blob_audit` table with a timestamp. It is a **dev tool, not
schema** — drop it with the statements in the file header when done. (An agent session cannot run
inline `psql` DDL through the sandbox classifier; feed it from the file as above.)

## 3. Catch a command the moment it fires

`docker logs` re-invokes an agent only when a background job exits, so watch for the command with
a background job that exits on capture:

```
dev/tools/watch_command.sh 4390          # end-of-round stats; also 4310, 4500, 4392, ...
```

Baseline-count based (immune to the `docker logs --since` timezone pitfall). Launch it with an
agent's `run_in_background` so the agent is notified when the packet lands, with the payload hex
already captured.

## 4. Decode

- **Stat reports** (`0x4390`): `python3 dev/tools/decode_stats.py <hex>` — prints the labelled
  struct-A slots and the unmapped struct-B block. Paste several payloads to compare players.
- **Host settings** (`0x4310`): dump the archived blob as hex and pipe to
  `python3 dev/tools/decode_settings.py -`.

## 5. Correlate

The bytes only get labelled by matching them to what the client shows:

- **Single-variable sweep** (settings, weapon restrictions): change exactly one thing per hosted
  game, diff consecutive `blob_audit` rows — the one moved bit/byte is that setting. This mapped
  the entire Common Settings block and weapon table.
- **Scoreboard correlation** (`0x4390`): play a round, read the results screen, sum each player's
  per-round slots and match to the reported per-category totals. **Distinct values are essential**
  — if every category reads 1, the slots cannot be told apart. Push for a match where the
  categories differ (varied kills/objectives, ideally 3+ players to break the 1v1 symmetry that
  leaves e.g. headshot-deaths inferable-but-not-proven).

## Current mapping status (2026-07-22)

- **`0x4310` settings** — fully mapped and confirmed (`decode_settings.py` has the offsets).
- **`0x4390` scoreboard** — kills/deaths/score/stun/headshots confirmed and persisted to
  `chara_stats`; headshot-deaths (`A7`) strongly supported; `A14` = Team Win or Target Defence
  (unsplit); Goal/Assist and the 58-slot struct-B block still unlabelled. See
  `dev/docs/OBSERVED.md`, "The 0x4390 scoreboard" and "…mode-independent". **Layout is
  mode-independent; scoring weights are mode-specific** — confirm the rest with a match that gives
  the objective categories distinct values.
- **Rule/map ids** — rule 1 = Team Deathmatch, rule 2 = Rescue (rest inferred from screen order);
  map 2 and 12 (Midtown Maelstrom) seen.
