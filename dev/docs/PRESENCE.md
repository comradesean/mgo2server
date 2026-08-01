# Per-character presence across lobby processes

**Which lobby is each character in, right now.** The server has never known this, and three
features are blocked on it. This page is the design, the reasoning, and the staging.

## Why it does not exist yet

Production runs **one process per lobby**. Each knows only its own connections —
`ChannelRegistry` is deliberately an instance rather than a static, because the integration suite
stands several servers up in one JVM and a shared map would silently join them. So no process can
answer "where is this character" about anyone outside itself, and nothing durable records it.

## What is blocked on it

| consumer | what it sends today | why that is wrong |
| --- | --- | --- |
| `0x4582` roster, wire `0x14` (`ROSTER_ENTRY_VISIBLE`) | hardcoded **1** | [ELF] it is a **lobby id**, rendered into `STRING_F_LIST_LOBBY` and handed to `0x884300`/`0xD47CE0` on "move to lobby". We tell every client that every friend is in lobby 1, and aim the jump there |
| `0x4602` player-search tail | three zeros | `lobby_id`, `lobby_name`, `game_id`, `game_name`, `lobby_type` — all confirmed 2026-07-31. Deliberately blank rather than guessed |
| automatch slot-in eligibility | — | needs the same "who is where" query |

The `0x4582` case is the sharp one: it is not a blank, it is a **wrong answer that misroutes a
player action**.

## The design

**One table, written from `ChannelRegistry`'s existing hooks, swept by `GameServer`'s existing
scheduler.** No new lifecycle, no new thread, no new component.

```sql
CREATE TABLE public.chara_presence (
    chara_id  bigint PRIMARY KEY REFERENCES chara(id) ON DELETE CASCADE,
    lobby_id  bigint NOT NULL REFERENCES lobby(id) ON DELETE CASCADE,
    since     timestamptz NOT NULL DEFAULT now(),
    last_seen timestamptz NOT NULL DEFAULT now()
);
```

### `chara_id` alone is the primary key

Not `(chara_id, lobby_id)`. **A character is in exactly one lobby at a time**, and making that the
key lets the database enforce the invariant instead of relying on every call site being careful.
It also makes a lobby change a single upsert rather than a delete-then-insert with a window in the
middle.

### Game membership is NOT duplicated here

`game_player` already records which game a character is in. Presence answers *which lobby*; the
game comes from a join. Two tables both claiming to know the current game is exactly the kind of
second source that goes stale and then gets believed.

So `0x4602`'s five-field tail is one query: `chara` → `chara_presence` → `lobby` (name, subtype) →
`game_player` → `game` (id, name).

### The race that will bite if it is missed

A lobby hop is **two processes racing**: the destination's insert and the origin's
disconnect-delete, in either order. So the two statements are asymmetric on purpose:

- **enter** — upsert: `ON CONFLICT (chara_id) DO UPDATE SET lobby_id = excluded.lobby_id, ...`
- **leave** — *conditional*: `DELETE ... WHERE chara_id = :chara AND lobby_id = :myLobby`

**Without `AND lobby_id = :myLobby`, a late disconnect from the old process erases the presence the
new one just wrote**, and the player intermittently disappears from every friend list in the game.
It is one clause, and it is very hard to diagnose after the fact — the symptom is intermittent and
depends on process scheduling.

### Crash recovery: a process clears its own lobby on boot

`DELETE FROM chara_presence WHERE lobby_id = :myLobby`, after a successful bind.

**By definition nobody is connected to a process that has just started**, so this is unconditionally
correct, and it handles hard kills, `docker restart` and crash-loops with no staleness heuristic.
That matters here specifically: this project has already had a container crash-loop ~1300 times, and
a TTL-only design would have left every one of those players "present" until the timer expired.

The heartbeat below therefore covers only the remaining case — a process that dies and **never comes
back**.

### Heartbeat

One batched statement per scheduler tick, over the live channel set:

```sql
UPDATE chara_presence SET last_seen = now() WHERE chara_id = ANY(:ids)
```

One statement per lobby per tick regardless of population. **30s tick, 120s staleness.** A reaper
deletes rows older than the staleness bound.

### Writes go on transitions, never in `onPacket`

`ChannelRegistry.onPacket` fires for **every inbound packet on every controller**. A database write
there is a write per packet. Presence is written where the channel map is written — `track()`, which
the authenticating handler also calls precisely because `onPacket` runs before `authenticate()` and
would otherwise miss a character until its second packet.

## Only game lobbies record presence

Gate and account servers are constructed with `lobbyId` 0, which is not a row in `lobby`. They
**do not write presence**, for two reasons and not just the foreign key: a connection to a gate is
not "in a lobby" in any sense a player would recognise, and the character may not even be selected
yet. Asserting otherwise would put a false row in front of every friend list.

They **do** still run the reaper. It is scoped to no lobby — it has to be, since its whole job is
cleaning up after a process that is not running — so every server that runs it shortens the window
after a lobby dies and never returns.

## Test hazard, and it is the same one `ChannelRegistry` documents

The integration suite stands **several servers up in one JVM against one database**. Presence is
keyed by `lobby_id`, so distinct lobby ids do not collide — but **the boot-time DELETE means
starting a second server for lobby 1 wipes the first one's rows.** Any test that stands two servers
on the same lobby id will see the second clear the first.

`TestDatabase`'s truncation keep-list also needs a decision; `starter_gear` was truncated between
tests once already, and its own comment had predicted it.

## Staging

1. **Plumbing only, no wire change.** Migration, service, boot-clear, hooks, heartbeat, reaper.
   Independently testable: rows appear on connect, vanish on disconnect, survive a heartbeat, and a
   lobby hop leaves exactly one row pointing at the destination. **Nothing the client sees changes**,
   so this cannot regress a live screen.
2. **`0x4582` wire `0x14`.** The smallest consumer, and the only one whose current value is actively
   wrong. One field, one query.
3. **`0x4602`'s five-field tail.** The full join, filling three fields we deliberately blanked.

Automatch slot-in eligibility becomes possible after step 1 and is tracked separately.

## Status

- **Step 1: DONE** (2026-08-01). `V72__chara_presence.sql`, `PresenceService`, hooks in
  `ChannelRegistry`, boot-clear and the periodic heartbeat/reap. `mvn verify` 233 unit / 236
  integration, ten of them `PresenceServiceIT`. No wire change: nothing the client sees moved.
- **Step 2: DONE** (2026-08-01). `0x4582` wire `0x14` now carries the friend's actual lobby, from
  one bulk lookup per roster rather than one query per row. Offline friends send 0, which the
  client renders as `"----"` and still displays.
- Step 3: not started — `0x4602`'s five-field tail

### Two things step 1 got wrong first, kept because they will recur

**`GameServer` had a single periodic-task slot**, held by automatching. It is now a list on the same
single thread, which strengthens the existing guarantee rather than weakening it: no two tasks can
overlap either, not just no two runs of one task. Building that list with `List.of(automatchTask,
presenceTask)` then failed **51 integration tests at server construction**, because `automatchTask`
is null on every non-game lobby and `List.of` rejects nulls before the constructor's own filter sees
them.

**The reaper's SQL could never have compiled.** `where last_seen < now() - make_interval(secs =>
:seconds)` renders through StringTemplate, which reads the `<` as an expression opener and consumes
up to the `>` in `=>`. Reversing it to `where now() > last_seen + ...` fixes it. This is the third
time the project has hit that trap, so it is now a rule in `CLAUDE.md` rather than a third inline
comment.

Worth noting *how* it was caught: the test backdates a row and then reaps. A test that merely called
`reapStale()` on fresh data would have passed against a statement that cannot compile, because Jdbi
only parses on execution.
