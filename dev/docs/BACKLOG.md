# Backlog

Deliberately deferred work. Each entry records why it is deferred and what the fix would look
like, so picking it up later does not mean re-deriving it. Entries move to the ordinary docs when
done.

## Lobby Select population — derived counts shipped, presence table still open

*Pinned 2026-07-21; first sketch implemented 2026-07-22.* The lobby-list entry (`0x2003`, offset
`0x29`, u16) now carries **players-in-games per lobby**, derived from `game_player`
(`GameService.countPlayersByLobby`, served by `LobbyGameController`). That was the cheapest of the
sketches: zero new state, but players idling in a lobby without having joined a game are
invisible, so the count reads "0 unless games are up" rather than true occupancy.

Still open if true occupancy is ever wanted:

- **Presence table.** The lobby servers are separate JVMs, so live occupancy has to go through
  postgres: a row per authenticated connection (`lobby_id`, `account_id`, `updated_at`); insert on
  auth, delete on disconnect, and on process start delete every row for the process's own
  `lobby_id` so a crash cannot leave phantom occupants. The `0x2005` handler then selects counts
  grouped by lobby. The gate serves the list but owns no lobby population of its own, which is why
  the counts must come from shared state rather than in-memory connection counts.
- Whatever the source, what the client *renders* for the field is a presentation claim and has not
  been checked against the binary (see `CLAUDE.md` on presentation claims).

## The peer-connect FSM — fully traced; blocker is the UDP handshake

*Pinned 2026-07-21, from a deep ELF trace of the client's peer state machine `0x276F60`.* The
entire TCP connect path is now understood and the server side is provably complete:

- The host runs a per-peer FSM. State `0x201` sends **`0x4340`** (payload = the joiner's chara id
  as a u32 key) and blocks on the **`0x4341`** reply, which must be `{u32 result, u32 key}` (8
  bytes; parser `0xD42D58` stops after two u32s — **there is no address in `0x4341`**). We echo the
  key correctly.
- The `result` word is a **P2P role selector**, read at `0x277170`:
  - `result == 0` → **active** (state `0x203`, `0x2771B8`): builds a connection object at
    `peer+0x10` via `0x263240`, arms the 30 s (`0x7530`) budget via `0x26C6D8`, and dials the
    joiner (whose address it has from the incoming connect — *not* from `0x4341`).
  - `result != 0` → **degenerate stub** (`0x277B20`): `vtable[+4](peer,0)` only, no connection
    object, no timer → the budget check reports expired on the next tick, the peer is freed
    (`0x2772DC`→`0x270F58`), and the joiner's next packet recreates it — a ~2 s recycle. **Not a
    working passive mode.** (Verified live: `result=1` gave exactly this 2 s loop and changed the
    host's UDP reply 16→25 bytes, but never connected.)
  - **So `result = 0` is correct.** Do not "flip to passive" — the binary has no passive-via-4341.
- **No server→peer push exists.** Every inbound `0x434x` (0x4341/4343/4345/4347/4349) is a reply to
  a client-sent even command; none is an unpaired server-initiated message. There is no
  "you're admitted"/roster push to add.
- **Endpoints verified correct** (2026-07-21): `chara_connection` and the `0x4321` both carry
  `192.168.1.100:5730` (host) / `192.168.1.102:5730` (joiner), public and private — no loopback,
  no container/WSL address, right port.

**Conclusion: there is no remaining server-side lever in the connect.** The join deadlocks in FSM
state `0x210` (`0x277254`) polling the UDP transport for `status==8`, which never arrives, then
tears down at the 30 s budget (the observed `0x4340 → ~28 s → 0x4342 → retry` loop). That status is
driven by the game-level UDP P2P handshake between the two RPCS3 instances, which the server does
not participate in.

**Now proven at the architecture level (2026-07-22).** A full ELF classification (see
`dev/docs/COMMANDS.md`, "Two architectures") showed the in-game host↔peer link is a **completely
separate packet stack** — its own builder (`0xD824D0`), dispatcher (`0xD78CC8`), framing, and
session object, sharing **zero** serialization primitives with the lobby protocol, and an id space
(`0x1101`–`0x56xx`) disjoint from the lobby's except for one value. Join and peer-register are
lobby-TCP (Channel A, ours); the gameplay link the join hands off to is Channel B, which never
reaches our server. So "the server does not participate in P2P" is no longer an inference from
packet decryption — it is a structural fact of the binary.

Remaining, non-server hypotheses (both need external evidence):
1. **Same-LAN, both-active simultaneous open.** Host goes active (`result=0`) and the joiner is
   also active (dials from `0x4321`). If retail P2P needs exactly one listener and the asymmetry is
   created outside this FSM, two co-located active peers may never reach `status==8`.
2. **Capture a working MGO2PC session** to see whether the host even runs this connect FSM (sends
   `0x4340`) or accepts passively by another path — that is the fastest way to learn the retail
   asymmetry. Community (MGO2PC/SaveMGO Discord) is the right source.

Grounded in FSM `0x276F60` (states `0x201`/`0x202`/`0x203`/`0x210`), reply parser `0xD42D58`,
role branch `0x277170`, teardown `0x2772DC`→`0x270F58`, connection creator `0x263240`.

## P2P works one direction — post-connection commands (superseded by the FSM trace above)

*Pinned 2026-07-21.* Reversing the test (mx1 **joining** a game hosted by localhost) got the P2P
link to actually form: the host sent **`0x4340`** ("player connected to me"), which the client
only emits *after* a successful peer connection — the first time we have ever seen it. So the
"host silently drops packets" finding below was **direction-specific** (mx1-as-host, likely its
UPnP/NAT), not a universal P2P failure. Localhost-as-host accepts the peer.

It hung only because `0x4340` had no handler (→ ack `0x4341`). Fix applied: `HostGameController`
now acknowledges `0x4340` and `0x4342` (player connected/disconnected), same empty-ack pattern as
`0x4344`/`0x4398`. That closed the last server gap — **no `No handler` lines appear anywhere in a
join now.** The joiner goes idle after `0x4321` and waits for P2P game data from the host; it
needs no further server push (matches all three references).

**Conclusion after exhaustive elimination (2026-07-21):** with the server complete, both firewalls
open, mx1 classified **full-cone** (Test II answered from `.201`, mx1 reaches `.201` both ways —
verified live), and addresses correct, sustained P2P game data between the two RPCS3 instances
*still* does not flow — the joiner spins or hits "unable to connect to host." The host reports
`0x4340` (brief initial contact) but the bidirectional flow never sustains. Everything we control
is verified correct; the remaining failure is the emulator-level encrypted P2P, which the earlier
decryption proved is not our protocol.

**Prime remaining suspect: the co-located `.100` machine** runs the server (mirrored-WSL) *and* a
native RPCS3 client simultaneously. WSL cannot even see localhost's native P2P egress, and mx1's
tcpdump during a spin showed no host→joiner game traffic — both consistent with mirrored
networking interfering with native RPCS3 peer traffic. **Next test: P2P between two machines where
neither is the server host** (server on a third/headless box). If two clean clients connect, the
server is proven done and the dual-role `.100` machine was the blocker. Do not reopen server code
for P2P without evidence contradicting the three-reference agreement and the packet decryption.

## The peer-to-peer connection — the earlier frontier (mx1 as host)

*Pinned 2026-07-21.* The whole TCP join handshake now works end to end and is verified against two
live clients: `4320 → 4321` succeeds, the joiner is handed the host's endpoint, the client accepts
it and **attempts the peer connection**. That attempt fails: ~40 s later the client sends `0x4322`
(join failed), which we now answer so it fails cleanly instead of hanging on `0B08:FFFFFF60`.

**The server side of join is complete — this is now an RPCS3 problem, not a server one.**
Established by captures on both machines 2026-07-21:

- The `0x4321` reply carries correct bytes (`192.168.1.102:5730`, result 0).
- The joiner (`.100`) sends a 44-byte UDP packet to the host every ~1.9 s. **mx1's tcpdump shows
  every one arriving** on `eth0:5730`. Firewall and addressing are conclusively ruled out.
- **mx1's game socket never replies.** The host receives the hole-punch and ignores it, while
  sitting in its own game room (checked — not a wrong-screen issue).

**Proven by decrypting the P2P packets (2026-07-21).** The joiner's 44-byte UDP packets to the
host were captured (Wireshark, joiner side) and decrypted with the game's global keys. The XOR
method is validated — it turns a captured TCP frame into a clean `cmd=0x0005` ping — and applied
to the UDP packets it produces garbage that varies per packet. They are **not** MGO2 game packets,
and carry no `0x0573` STUN magic either. They are **RPCS3's own PSN/P2P signaling**, opaque below
MGO2. The same capture shows the joiner doing sustained, working RPCN traffic to an external
server (`104.29.153.67:19295`) while the direct `.100:5730 → .102:5730` punch gets 0 bytes back.

**So the MGO2 server is confirmed complete and not the cause** — the failing packets are not our
protocol. Our `0x4321` hands over the host address correctly; RPCS3's signaling takes over and the
host's emulator never authorizes the peer. The stale-socket idea is also dead: `ss` on mx1 showed
exactly one clean owner of `:5730`.

This is an **RPCS3/RPCN** problem, outside this codebase. Leads, in order:

1. **RPCN NAT type / P2P** in each RPCS3 (Settings → Network). A restrictive type reported to RPCN
   stops the broker from setting up the direct punch, so the host drops it.
2. **Two RPCS3 instances, same LAN, RPCN P2P** is known-fiddly — RPCN may hand out the wrong
   (public vs LAN) peer address or refuse same-account/same-IP pairs. Confirm the two instances use
   **different RPCN accounts**.
3. **Host-side `sys_net`/RPCN Trace log** — it will show the signaling layer receiving the punch
   and why it drops it.

Do not treat `0x4322` being handled as "join works" — it means join *fails politely* (`0B09`).
Do not reopen the server code for P2P: the decryption proves the failing traffic isn't ours.

## The TCP join handshake (done)

*Pinned 2026-07-21, from the first two-client session.* Join Game, Game Details and Player List
all failed `0B10:FFFFFF60` on the same missing reply: the client sends `0x4312` (get game
details) and retries every ~2 s. It never gets far enough to send `0x4320` (join game). Order of
work:

1. ~~**`0x4312`**~~ — **implemented and verified against a live client 2026-07-21.** The parser
   at `0xD44388` accepts our reply: Game Details opens. Layout and provenance in PROTOCOL.md.
2. **Flesh out the `0x4313` player entries — the Player List failure.** *Verified against a live
   client 2026-07-21:* Player List sends the **same** `0x4312` and consumes the **same** `0x4313`
   reply as Game Details (packet trace: no distinct command, no `No handler`). Game Details reads
   only the header and opens; Player List additionally walks the per-player entries, validates
   each, and rejects ours with **`0B0F:00000000`**. Our entry is minimal — `charaId`, 16-byte
   name, `ping=0`, `exp=0`. The binary has five `li r3,0x0B0F` raise sites; the player-entry
   validator reached via `0x904DC0 → 0x883FB4` reads a much larger per-player struct (offsets
   `0x00`, `0x04`, `0xB0`, `0xB4`, `0x300`, each required non-zero/valid). **Not yet pinned:**
   which wire field at which offset the player-list consumer requires — that needs tracing the
   consumer, not the producer. Do that before adding fields; do **not** guess values.
3. ~~**`0x4320`**~~ — **implemented 2026-07-21** from the reply parser at `0xD440DC` (layout in
   PROTOCOL.md). Reads game id (+ optional password), serves the host's endpoint. Awaiting live
   verification — the sender side is not yet located, so the request width is unconfirmed.
4. ~~**Persist `0x4700`**~~ — **done 2026-07-21.** Stored in `chara_connection` keyed by
   character; `0x4320` reads it back. The public IP comes off the socket.
5. **Store the `0x4310` settings blob.** Until then every game row materialises with defaults,
   which the browser renders as map "----", rule 0, Avg Level 0 and a blank host score —
   observed against a real client 2026-07-21. The details reply has slots for the rotation,
   weapon restrictions, timers and uniques that all sit at zero for the same reason; one fix
   clears the whole cluster.

## Game-list refresh semantics are unverified

*Pinned 2026-07-21.* During the first two-client session, a game created on one machine did not
appear in a game list already fetched by the other; re-entering the browser showed it. The server
side is fact (our code): `0x4300` is answered from a snapshot query with no staleness filter, no
heartbeat, and nothing pushes updates to an open list. **The client side is unverified**: whether
the browser screen re-polls `0x4300` on a timer, or expects unsolicited updates, has not been
checked against the ELF or a capture — and an expected-but-unanswered command is this client's
signature failure mode.

To settle it:

1. Tier 1: find the game-browser screen's state machine in the ELF and see what drives `0x4300`.
2. Tier 2: run the gamelobby at debug logging, hold an open game list on one client for 60
   seconds while the other creates a game. Nothing sent → snapshot model confirmed, the empty
   first list was a request/creation race, and this entry closes. Anything sent and unanswered →
   promote to a bug.

*Reference data point (2026-07-22):* Nomad also has **no push and no re-poll trigger** — its
`0x4300` is pure request/response, and games vanish from the next poll when a 60-second reaper
kills hosts that stopped sending `0x4398` pings. That reaper is why Nomad's `lastUpdate` exists;
we now track `last_update` from `0x4398` too but deliberately do not reap on it — our
disconnect teardown covers dead hosts. Supports the snapshot model without proving it.

## Unique characters: bit 0x142/7 and bytes 0x140/0x141 are unverifiable on this build

*Pinned 2026-07-22, during the per-setting capture sweep.* Every other commonA/commonB bit was
confirmed by single-variable hosting (see OBSERVED.md, "The Common Settings map, confirmed
setting by setting"), but **uniques could not be tested: the setting does not appear in this
client's Create Game screens** — the operator's read is that unique characters arrived in a later
update/expansion, which squares with the lobby list's "expansion required" restriction bit. The
decode (`0x142` bit 7 → `uniques_enabled`) and the red/blue selectors at `0x140/0x141` stay
implemented as transcribed from Nomad, harmless while the client never sets them. If an expansion
client (or a capture from one) ever surfaces, that is the moment to verify; until then treat the
uniques fields as reference-only.

## ~~The 0x4310 byte 0x142/0x143 conflict~~ — RESOLVED by capture 2026-07-22

**Settled the same day it was pinned** — see OBSERVED.md, "Where the Common Settings toggles
live". A single-variable hosting capture (only friendly fire flipped) moved exactly byte `0x142`
bit 3: Nomad's map was right on every count. The toggles are commonA/commonB at `0x142`/`0x143`
in the `0x4310` blob, level-limit base is a u32 at `0xF8`, and `applyHostSettings`' u16-at-`0x142`
read was a bug that stored toggle bits as the base — fixed; the decode now feeds the toggle
columns, and the earlier `0x4110`-header theory (the entry that used to sit below this one) was
wrong outright: `0x4110` never even appeared in a session with a created game, a joiner, and a
started match. The populated `0x4305` was also live-verified in the same session (visual pre-fill,
plus our injected constants round-tripping back in the next push). Still open from the old
entries, now minor: whether the populated `0x4305` should canonicalise as Nomad does
(`commonA |= 0b100`, kick zeroing, derived `wr[10]`) rather than echo raw — the raw echo works
against the live client, so it stays.

## The round snapshot never populates — quitter stats are dropped ✅ RESOLVED

*Resolved 2026-07-23: both proposed fixes are applied in code — `game_round` is populated on
game create and on join (`GameService.createGame`/`addPlayer`), and the start-round handler is
renumbered to the real `0x43c8`/`0x43c9` pair (`HostGameController.START_ROUND`). The section
below is kept as history; note a live capture of `0x43c8`'s payload semantics is still worth
recording in OBSERVED.md when one is next taken.*

*Pinned 2026-07-22 (evening); root cause found same day.* `game_round` is filled by the `0x43ca`
handler, but this client **never sends `0x43ca`** — the full-binary send-site enumeration
(2026-07-22) found no builder for `0x43ca` at all, while it *does* build **`0x43c8`** (`0xD40CB4`,
payload `{u32, u8}`). So our start-round handler is **dead code bound to the wrong id**, which is
why the snapshot is always empty and `0x4390` stat application falls back to current membership
alone (observed: a crashed joiner's end-of-round report was rejected where the mechanism exists to
accept it).

Two paths to fix, in order of confidence:

1. **Cheap and certain:** populate `game_round` on join (insert on `addPlayer` and at create),
   clearing only on game teardown — approximates "played in this game" without needing any round
   boundary. Independent of the id question.
2. **The real trigger:** `0x43c8` is the likely actual start-round command. Capture one against a
   live client (host a match, start a round, read the payload) and confirm before repointing the
   handler — do NOT swap `0x43ca`→`0x43c8` blind; that would repeat the guess-the-layout mistake.
   Its `{u32, u8}` shape needs a parser trace like `0x4500`/`0x4510` got.

See PROTOCOL.md, "The complete sendable set" for the enumeration and the sibling gaps.

## 0x4110 gameplay options are acked but not parsed

*Pinned 2026-07-22 (evening).* The options write-back is now identified (304 bytes, the `0x4120`
layout minus its 32-byte trailer) and its sibling `0x4114` macros are persisted, but `0x4110`
itself is dropped after the ack, so gameplay/interface option edits do not survive a session.
The parse is mechanical — invert `GameplaySettingsWriter` into the `chara_settings` columns,
including its off-by-one stored-vs-wire quirks — and directly serves the no-blobs goal. Verify
by editing one option, relogging, and checking the Options screen.

## 0x4440 carries an undecoded team/spectator byte

*Pinned 2026-07-22 (evening).* 0x4440 was long treated as a contentless in-match ping (acked with
result 0, byte discarded). Live traffic shows its **1-byte payload varies** — mostly `01`, but a
`02` appeared exactly when a player switched to **spectator**. So the byte is a team/side/spectator
selector, and we drop it on every ack, leaving team composition untracked server-side
(`game_player.team` exists but nothing writes it). Not a missing ack — a missing decode.

To map it: labeled sweep like the settings pass — switch deliberately to Auto / Red / Blue /
Spectator one at a time and record each byte value (only `01`/`02` seen so far). Then parse the
byte into `game_player.team` in the 0x4440 handler and, if useful, reflect it in game details.
Low urgency for a host-authoritative P2P match; a clean fit for the no-blobs goal. Do NOT guess
which value is which from the single `02`=spectator coincidence — capture each.

## Phantom / misnumbered reply ids (from the duplex ELF cross-check)

*Pinned 2026-07-22 (evening).* Enumerating both directions of the protocol from the binary (send
builders and the inbound dispatchers, see `dev/docs/COMMANDS.md`) exposed reply ids the server
emits that the client has **no parser for** — it is waiting on a different id. In priority order:

1. **`0x43ca`/`0x43cb` should be `0x43c8`/`0x43c9`.** The client sends `0x43c8` (start round) and
   parses `0x43c9`; it never sends `0x43ca` nor parses `0x43cb`. Our handler is bound to the
   wrong id on both halves — same off-by-2 as the `game_round`-never-populates bug. Capture a
   `0x43c8` live, confirm its `{u32, u8}` payload and the `0x43c9` reply shape, then repoint.
2. **`0x4140` (skill sets) and `0x4142` (gear sets) in the `0x4100` connect burst have no client
   parser.** The client instead parses `0x4103`/`0x4105`/`0x4107` (which we never send). This is
   inherited echo numbering, and it may mean saved skill-set / gear-set slots have never actually
   populated on this client — a latent bug hidden because the rest of the burst works and nobody
   checked the set slots. **Verify first**: on a live character, do the three skill-set and
   three gear-set slots show saved loadouts? If they are empty/default, trace `0x4103`/`0x4105`/
   `0x4107`'s parsers and remap. Do not change the working burst blind.
3. **`0x4115`** (our `0x4114` chat-macro reply) has no parser — harmless since `0x4114` is
   fire-and-forget, but the reply should not be sent.
4. **`0x4442`** is parsed by the client but we only send `0x4441`; check whether the `0x4440`
   team/spectator exchange expects `0x4442` too.

None is repointed here — each needs a live capture or parser trace first, per the project's
standing rule against guessing layouts/ids.

## Scoreboard stats — struct A fully labelled 2026-07-24; a handful of B slots left

*Pinned 2026-07-22; substantially closed 2026-07-24* (OBSERVED.md, "The B-block's running-max
family"). Struct A is now labelled end to end — the knockout dealt/received pairs (`0x0d`/`0x0f`,
`0x15`/`0x17`), assists (B37, screen-confirmed ×3), the OTHER category (B36 = kills·(kills−1)/2),
mode-specific stun multipliers (×2 TDM / ×3 DM), and the clamped-store score model are all in
PROTOCOL.md. The B-block's running-max family (B0/B1/B2/B12) is understood as per-stage
best-round records wired as store-if-greater deltas.

Closed later the same day (see OBSERVED): the headshot category (= `0x11`+`0x15`·2, body-dart
round), hacking (=B19·5, and hacks credit an assist each), wake (=B35·2), `0x21` (= flawless
win: won + zero deaths — the timer-end hypothesis is retired), B24 (= flawless TDM wins per
stage; survive-but-lose and win-but-die both tick nothing), B0/B1/B2 (= consecutive
kills/deaths/headshots streak records), B36 (= streak combo).

Further closed by the 2026-07-24 gesture rounds (see OBSERVED): B7 salutes, B8 preset radio,
B12 rolls, B15 catapult, B16 boosts, B17 falling deaths (which also tick B3 — suicides
include falls), B18 trap catches, B20 box seconds, B21 box uses; suicide deduction (−2 like
any death — the "deduct nothing" read was clamp artifact); knife kills shown to live in
0x43a2, ending round_weapon_tally's deferral; and the B-index = 0x4107-slot−1 rule (17/17).

B5/B6 friendly kills/stuns also closed 2026-07-24 (FF round; TKs score-neutral, absent from
the dealer's A counters).

Still open: get-stunned-with-banked-score round (does the OTHER knockout-received component
feed the wire score?); B9 text chat (blocked on the RPCS3 OSK commit path, not the server);
flag `0x04`; `0x19`, `0x1d`, and the trailing word (never nonzero). One question deliberately
left unresolved: whether the client's clamped score store resets per game or per stage —
client-internal bookkeeping with no observable consequence for anything we store or serve
(the wire semantics, delta-of-clamped-store, are fully pinned and documented in PROTOCOL.md).

## 0x4140 / 0x4142 loadout sets go nowhere on this build

*Pinned 2026-07-22 (evening).* We send saved skill sets as `0x4140` and gear sets as `0x4142` in
the `0x4100` connect burst, but the duplex ELF scan proved the client has **no parser for either**
— they are silently-ignored dead sends. The candidate alternates `0x4103`/`0x4105`/`0x4107` (which
the client *does* parse) were traced and are **not** skill/gear sets: no 63-byte set-name read
exists in any of them, and their shapes (profile record / numeric arrays) do not match the
set structs. So the saved-loadout-slots feature has **no known delivery command** on this build —
either it is cut, or its home id is elsewhere and unidentified. **Verify first with one live
glance**: on a character, do the three skill-set and three gear-set slots show saved loadouts, or
are they empty/default? If empty, the feature is inert regardless of what we send and the
`0x4140`/`0x4142` sends can be dropped from the burst; if populated, they arrive by a path we have
not found. Do not change the working burst before that check.

## Match/encounter history — phases 1+2 shipped 2026-07-23; 3 open, 4 deferred

*Pinned 2026-07-23, after the 0x4680/0x4220 fingerprint rounds settled the client contracts.*
Everything below serves screens whose byte layouts are now traced and (mostly) label-confirmed;
the missing half is storage. The ingestion source already exists: the host's per-player
per-round `0x4390` report (kills/deaths/score/stuns/headshots/seconds/exp all live-confirmed)
plus the `game_round` roster snapshot. Today we fold reports into lifetime totals and discard
the round-level detail; history is what falls out of keeping it.

**Storage principle (settled 2026-07-23): bare minimum — `round_report` is the single new
table, and every stats/history screen derives from it at query time.** No weekly or per-mode
accumulator tables, no encounter table: period views are time-window sums over `reported_at`,
per-mode views join `game` for the mode, encounters are the phase-2 self-join. This
supersedes the `chara_mode_stats` / `chara_personal_scores` schema sketched in OBSERVED.md
("The cumulative/weekly toggle") — those were never built and now should not be.
`chara_stats` (lifetime sums, shipped 2026-07-22) is **dropped by the phase-1 migration**:
inspection 2026-07-23 found it write-only — nothing selects from it — and holding exactly one
test round from the capture session that labelled the slots (already recorded in OBSERVED.md),
so there is no history to preserve. `GameService.accumulateStats` becomes the `round_report`
insert; lifetime totals are a `sum(...) group by chara_id`. Revisit materialization only if
the table ever becomes too large, which at this population it will not. On fidelity: the original backend's schema is
unobservable — no capture can reveal it — so "recreate the original" can only ever mean
matching its *wire behaviour* (tiers 1–2). What the history and weekly screens prove is that
Konami's backend kept per-round, per-player data; a raw round-report table is the minimal
store consistent with that evidence, which is exactly why it is the right shape.

**Phase 1 — keep the round reports.** The `round_report` table, one row per `0x4390` report:
game id, round, reporter (host) id, target chara id, the parsed fields as typed columns
(kills, deaths, score, stuns, headshots dealt/taken, seconds, exp-total, aborted flag), and
the still-unlabelled counters as named-by-offset columns (`counter_0x0f`, struct-B slots) —
decoded columns, not blobs, per the no-blobs rule; plus `reported_at`. A non-cascading
relationship to `chara` (deleted players must not vanish from others' histories). Play time
for the `0x4221` card (confirmed, seconds) is then `sum(seconds)` — derived, not accumulated.

**Phase 2 — serve `0x4680` by deriving encounters from `round_report`.** No separate
encounter table (a `chara_encounter` materialization was considered and rejected 2026-07-23:
at this population it buys nothing and adds an upsert hook, a prune policy, and derived state
that can drift). Who the viewer met is a self-join — other players with a report in the same
(game, round) — grouped by met-chara with `max(reported_at)`, newest 64 (client table cap),
name joined from `chara`. Record layout per `mgo2_cmd_4682.ksy` — all four fields labelled,
u8 sent 0 (cosmetically inert in the fingerprint). Two decisions this derivation forces on
the phase-1 migration: character deletion must not cascade into `round_report` (soft-delete
or preserve rows, else deleted players vanish from every history), and history depth equals
`round_report` retention — which is "keep indefinitely", since stats want it anyway.

**Phase 3 — `0x4221` player details from real data.** Name and comment from the chara row,
play time from phase 1, id echo as implemented. LEVEL is client-derived from an exp-like u32
(candidates: wire 0x18 vs 0x1E — the next fingerprint round varies one at a time to split
them, then we send experience in the winning slot). CLAN stays honestly empty until clans are
modelled (the card already renders "---"; whether the 16B string or a gating id drives it is
the same fingerprint round's second question).

**Phase 4 — deferred: `0x4684` match details.** Layout traced (93-byte records,
`mgo2_cmd_4686.ksy`) but no UI path has ever been observed to send it. If it surfaces, the
natural serving is per-player round lines straight out of `round_report`. Do not build ahead
of an observed trigger.

**Explicitly not in scope here:** streak counters for medals/titles. Those are stat *slots*
(`0x4107` slot 1 consecutive kills, slot 25 consecutive TDM survivals), not history queries —
round-ordered processing of `round_report` is where they would be maintained. The labelling
half is now done (2026-07-24): slot 1 accumulates B0 deltas (per-stage consecutive-kills
records); slot 25's event is `0x21` = flawless win (won + zero deaths — survive-but-lose and
win-but-die both proven not to count), so the served value is a streak over TDM rounds'
ordered `0x21` column (reset on any 0), with current-vs-best-ever streak the one remaining
semantic choice (best-ever recommended, record-book convention). B24 is the client's own
per-stage count of the same events, wired as an absolute snapshot — do not sum it.

## Dual-login: stale sessions die lazily; active disconnect is the possible smoothing

*Pinned 2026-07-23 (evening), from deliberately triggering concurrent logins on one account.*
One session token per account, so a second login overwrites the first; the first client
discovers it only on its next session-bearing command ("Check session: no account holds the
presented session", five across gamelobby/account that session) and errors on whatever screen
it happens to be on. No unhandled packets are involved — the whole exchange is known commands.

If smoother flow is ever wanted: on a login that overwrites an existing session, actively
disconnect TCP connections still authenticated as that account, so the old client fails fast
at a clean point. **Operator policy, not protocol** — no capture shows how the original
handled concurrent logins; the current lazy invalidation is equally defensible and simpler.
Cheap observation to bank first: which error dialog(s) the stale client renders per screen on
invalid-session — unrecorded so far.

## round_report.seconds_in_game holds two wire fields — split at next deploy

*Pinned 2026-07-23 (late).* Wire 0x23 decoded as {u16 team slot, u16 seconds}; the column
stores the raw composite (team*65536+seconds). Next natural deploy: V18 migration splitting
into team_slot + seconds columns (existing rows: hi/lo of the stored value), matching parse
in updateStats. Deferred only to avoid a mid-session lobby restart.

## Store 0x43a2 per-weapon round tallies

*Pinned 2026-07-24, corrected same day.* 0x43a2 is fully decoded AND per-player: one
packet per scoring player (leading u32 = that player's chara id), sent right after their
0x4390, carrying {u8 weapon id, u16 kills, u16 headshot terminal blows, u16 faints caused}
per weapon (names in WEAPONS.md). Currently acked-and-dropped. Storage is now trivially
attributable: round_weapon_tally (game, chara, weapon, the triple, reported_at).
**Deferral rationale ended 2026-07-24**: the Personal Stats screen's weapon-specific lines
(Knife Kills at minimum) derive from these tallies, not struct B — the knife round put its 4
kills in 0x43a2 (weapon id 1) and nowhere else. Build the table at the next natural deploy.
