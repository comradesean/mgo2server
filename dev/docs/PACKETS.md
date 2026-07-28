# Packet reference — every lobby command id, one line each

A flat index of **every Channel A command id** in both directions, with its payload size and a
one-line summary. It is the lookup table; [`COMMANDS.md`](COMMANDS.md) is the architecture — read
that first for the Channel A / Channel B split, the dispatcher addresses, and why the id space is
known to be complete. Byte-level layouts live in [`PROTOCOL.md`](PROTOCOL.md), live-capture facts
in [`OBSERVED.md`](OBSERVED.md), and per-id Kaitai specs in `dev/proto/` (verified) and
`dev/proto/blanks/` (drafts — see [`blanks/README.md`](../proto/blanks/README.md)).

Everything here is **Channel A** (the lobby TCP link our server terminates). Channel B, the
in-game host-to-peer link, is a disjoint id space and is not listed.

> **On the word *dead*.** `COMMANDS.md` used to apply it to "we have code for it but the client
> never uses that id" — **the wrong side of the wire.** The client is the specification, so an id
> our server touches which the client neither sends nor parses is a **defect** (misnumbered,
> invented, or inherited from a reference server targeting another build), not inert leftover code.
> Reading `0x43CA` as harmless vestige is exactly why start-round stalled; the real id was
> `0x43C8`. `COMMANDS.md`'s legend was corrected on 2026-07-26 and the two files now agree.
>
> `dead` is used here only with its honest meaning: **code in the ELF that goes nowhere** — an
> unreachable builder, a stub parser, a dispatcher arm that falls through. That is a fact about the
> game and a genuine category; it is simply never a description of our own code. It appears in the
> `client` column, never in `our status`. **No id currently carries it** — see
> [What is not established](#what-is-not-established).

## Counts

| | ids | rows here |
| --- | --- | --- |
| client → server (`dev/analysis/c2s_ids.txt`) | 112 | 112 |
| server → client (`dev/analysis/s2c_ids.txt`) | 204 | 204 |
| distinct ids | 315 | 315 |

`0x0005` (ping) and `0x49C0` are the only two ids the client both sends and parses. `0x0005` is a
single row — the same empty schema each way. `0x49C0` gets two rows because the two directions
carry entirely unrelated layouts under one id; both are labelled `sends+parses`. Every id in both
lists appears exactly once, checked programmatically against the two id files.

## Legend

**Payload** is the decrypted body *after* the 24-byte transport header (see
[`CRYPTO.md`](CRYPTO.md)) — no header bytes, no XOR/Blowfish.

- `N B` — fixed size, summed from the spec's `seq`.
- `variable` — contains a repeat, a length-prefixed field, or a string.
- `empty` — positively established as zero bytes (builder immediately followed by the seal, or a
  parser that opens no reader).
- `unread` — the parser opens no reader at all, so whatever is sent is discarded. Distinct from
  `empty`: `0x2002`/`0x2004` carry four bytes nobody reads.

**client** — what the client's own code does with the id, read from the ELF. This column is ground
truth and does not depend on our server at all.

- `sends` — the client has a builder for it.
- `parses` — the client has a parser for it.
- `sends+parses` — both.
- `dead` — the id exists in the ELF but goes nowhere: a builder in a function no reachable path
  calls, a parser that reads and stores nothing, or a dispatcher arm falling through to a stub.
  This is dead code **in the game**, and it is the only correct use of the word here — contrast
  `MISNUMBERED`/`PHANTOM` below, which are defects in *our* server.

  **No id currently carries this label, and that is not evidence of liveness.** No reachability
  pass has been run over the binary: the builder scan proved every call site exists and resolves
  to a literal id, not that every call site is reachable from live code. Applying `dead` requires
  positive evidence — name the address and say what makes it a dead end. Establishing which ids
  qualify is outstanding work, listed under [What is not established](#what-is-not-established).

  Two cases that are *not* `dead`: `0x43CA`/`0x43CB` have no builder and no parser anywhere in the
  ELF, and absence from the binary is not dead code in the binary (they were our misnumbering, now
  resolved). `0x0001` (echo) has no builder in the lobby packet library yet is plainly in use — it
  lives in the pre-lobby handshake, outside that library's scope.

**our status** — our server's conformance to that.

- `served` — we handle or emit it correctly.
- `gap` — the client sends it and we do not implement it. A potential `FFFFFF60` stall, but only
  once the menu that triggers it is reached.
- `unsent` — the client can parse it and we never emit it. Benign unless the client requested the
  feature and blocks on the reply.
- **`MISNUMBERED`** — we implement a neighbouring id instead of the real one.
- **`PHANTOM`** — we emit it and the client has **no parser** for that id.

**The last two are bugs, not tidiness.** An id our server touches which the client does not use is
a defect to be fixed — the client cannot be wrong about its own protocol. `MISNUMBERED` and
`PHANTOM` are rendered in caps for that reason, and neither is ever "cleanup we can defer".

No row in the tables below carries either: both id lists come from the ELF, so every id with a row
is one the client genuinely uses. The defects live *outside* the id space, and are listed in
[Defects — ids our server touches that the client does not](#defects--ids-our-server-touches-that-the-client-does-not)
below.

**[UNKNOWN]** prefixes any summary whose *meaning* is not established. The field order and widths
may still be solid — read out of the builder or parser — but what the command is for is not known,
and the text after the tag describes only shape. It is not a guess to be repaired with a plausible
name. Where a spec and `COMMANDS.md` disagree, the row says so instead of picking a side.

`served †` marks eight ids implemented in our source tree that `COMMANDS.md` (send-scan of
2026-07-22) still files as gaps: `0x4220`/`0x4221`, `0x43A6`/`0x43A7`, `0x43D0`/`0x43D1`,
`0x43E0`/`0x43E1`. `COMMANDS.md` is the stale side there; the handlers exist in
`src/main/java/mgo2server/game/controller/`.

`*(verified spec)*` marks the nine ids promoted to `dev/proto/`: layout confirmed against a
capture, not only read from the ELF.

## Summary sources

Each row's summary is the `meta.title` of that id's Kaitai spec, which in turn cites the builder
call site (client → server) or parser address (server → client) in its `doc:`. Sizes are computed
from the spec `seq`. Nothing here was re-derived, and nothing came from another server
implementation.

---

## Tables

### Gate, account and character (`0x0003`–`0x3108`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x0003` | sends | empty | Disconnect | served |
| `0x0004` | parses | 4 B | Disconnect acknowledgement | unsent |
| `0x0005` | sends+parses | empty | Ping — identical empty schema in both directions | served |
| `0x2002` | parses | unread | Lobby-list start | served |
| `0x2003` | parses | variable | Gate lobby-list entries | served |
| `0x2004` | parses | unread | Lobby-list end | served |
| `0x2005` | sends | empty | Get lobby list | served |
| `0x2006` | sends | empty | [UNKNOWN] Unidentified gate/lobby-layer request | gap |
| `0x2007` | parses | 4 B | [UNKNOWN] Gate reply, single u32 — no 0x2005/0x2008 pairing established | unsent |
| `0x2008` | sends | 1 B | Get news | served |
| `0x2009` | parses | 4 B | News-list start | served |
| `0x200A` | parses | variable | News item | served |
| `0x200B` | parses | 4 B | News-list end | served |
| `0x3003` | sends | 21 B | Check session | served |
| `0x3004` | parses | 4 B | Check-session result — 0x3004 is also a Channel B id; unrelated message there | served |
| `0x3040` | sends | 1 B | [UNKNOWN] Unidentified account-lobby request | gap |
| `0x3041` | parses | 24 B | [UNKNOWN] Reply to 0x3040 | unsent |
| `0x3048` | sends | empty | Get character list | served |
| `0x3049` | parses | variable | Character list | served |
| `0x3101` | sends | 43 B | Create character | served |
| `0x3102` | parses | 4 B | Create-character result | served |
| `0x3103` | sends | 1 B | Select character — a **slot index**, not a character id *(verified spec)* | served † |
| `0x3104` | parses | 4 B | Select-character result | served |
| `0x3105` | sends | 1 B | Delete character | served |
| `0x3106` | parses | 4 B | Delete-character result | served |
| `0x3107` | sends | 16 B | Check character name | served |
| `0x3108` | parses | 4 B | Check-character-name result | served |

### Connect burst and personal data (`0x41xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4100` | sends | empty | Character connect | served |
| `0x4101` | parses | variable | Character info, packet 1/9 of the connect burst | served |
| `0x4102` | sends | 4 B | Get personal stats | served |
| `0x4103` | parses | variable | Personal-stats character info (reply 1/4 of the 0x4102 burst) *(verified spec)* | served |
| `0x4105` | parses | variable | Per-mode stat grid (replies 2/4 and 3/4 of the 0x4102 burst) *(verified spec)* | served |
| `0x4107` | parses | 588 B | Personal scores (reply 4/4 of the 0x4102 burst, terminal) *(verified spec)* | served |
| `0x4110` | sends | variable | Update gameplay options | served |
| `0x4111` | parses | 4 B | Options write-back ack | served |
| `0x4112` | sends | 32 B | Connect-family write-back, **blocks** (wait slot `0x18`); 32-byte body still [UNKNOWN] | served |
| `0x4113` | parses | 4 B | Bare `{u32 result}` for `0x4112` — acknowledged, body dropped | served |
| `0x4114` | sends | variable | Update chat macros | served |
| `0x4120` | parses | variable | Gameplay and interface settings, packet 2/9 of the connect burst | served |
| `0x4121` | parses | variable | Chat macros, packets 3/9 and 4/9 of the connect burst | served |
| `0x4122` | parses | variable | Personal info, packet 5/9 of the connect burst | served |
| `0x4124` | parses | variable | Gear catalogue, packet 6/9 of the connect burst | served |
| `0x4125` | parses | variable | Skill catalogue, packet 7/9 of the connect burst | served |
| `0x4128` | sends | empty | Get post-game info | served |
| `0x4129` | parses | variable | Post-game info reply | served |
| `0x4130` | sends | variable | Update personal info | served |
| `0x4131` | parses | variable | Update-personal-info reply | served |
| `0x4132` | sends | empty | Outfit commit | served |
| `0x4133` | parses | variable | Loadout readback, reply to 0x4132 | served |
| `0x4150` | sends | 1 B | Lobby disconnect | served |
| `0x4151` | parses | 4 B | Lobby-disconnect ack | served |

**No set-title command exists, as far as this table can tell.** All 24 ids in the family are
accounted for above and every one is served, so there is no unclaimed id in the family that owns
every other personal-data write. The **worn title** (`0x4103` wire 541) is therefore **computed by
the server** — the best unlocked title by rank — not chosen by the player; the mask at wire 563 is
the collection it is chosen from. See [`AWARDS.md`](AWARDS.md) for the rest of the evidence. This is
an argument from a complete id list, not a proof: an equip command living outside `0x41xx` would
announce itself as a `No handler for command …` line once players have collections to choose from.

### Player card / overview (`0x42xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4210` | sends | empty | [UNKNOWN] Own player card / overview request | gap |
| `0x4211` | parses | 4 B | [UNKNOWN] List start for the 0x4210 triple | unsent |
| `0x4212` | parses | variable | [UNKNOWN] List records for the 0x4210 triple | unsent |
| `0x4213` | parses | 4 B | [UNKNOWN] List end for the 0x4210 triple | unsent |
| `0x4220` | sends | 4 B | Player details request | served † |
| `0x4221` | parses | 201 B | Player-details card (single reply to 0x4220 {u32 character id}) *(verified spec)* | served † |

### Host and game session (`0x43xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4300` | sends | 4 B | Get game list | served |
| `0x4301` | parses | 4 B | Game-list START (reply 1/3 to 0x4300) | served |
| `0x4302` | parses | variable | Game-list entries (reply 2/3 to 0x4300) | served |
| `0x4303` | parses | 4 B | Game-list END (reply 3/3 to 0x4300) | served |
| `0x4304` | sends | empty | Get host settings | served |
| `0x4305` | parses | variable | Saved host settings (reply to 0x4304) | served |
| `0x4310` | sends | variable | Check/push host settings | served |
| `0x4311` | parses | 4 B | Host-settings push ack (reply to 0x4310) | served |
| `0x4312` | sends | 4 B | Get game details | served |
| `0x4313` | parses | variable | Game details (reply to 0x4312) | served |
| `0x4316` | sends | 1 B | Create game | served |
| `0x4317` | parses | 8 B | Create-game result (reply to 0x4316) | served |
| `0x4320` | sends | 21 B | Join game | served |
| `0x4321` | parses | 41 B | Join-game endpoints (reply to 0x4320) | served |
| `0x4322` | sends | empty | Join failed | served |
| `0x4323` | parses | 4 B | Join-failed ack (reply to 0x4322) | served |
| `0x4340` | sends | 4 B | Peer register | served |
| `0x4341` | parses | 8 B | Peer-register ack for 0x4340 player connected | served |
| `0x4342` | sends | 4 B | Peer register | served |
| `0x4343` | parses | 8 B | Peer-register ack for 0x4342 player disconnected | served |
| `0x4344` | sends | 5 B | Peer register | served |
| `0x4345` | parses | 8 B | Peer-register ack for 0x4344 peer-register phase 2 | served |
| `0x4346` | sends | 4 B | Peer register | served |
| `0x4347` | parses | 8 B | Peer-register ack for 0x4346 peer-register phase 3 | served |
| `0x4348` | sends | empty | [UNKNOWN] Unidentified in-match command | gap |
| `0x4349` | parses | 171 B | [UNKNOWN] Reply to 0x4348 (subsystem unidentified) | unsent |
| `0x4380` | sends | empty | Quit game | served |
| `0x4381` | parses | 4 B | Bare result ack for 0x4380 quit game | served |
| `0x4390` | sends | 167 B | Host's end-of-round stat report *(verified spec)* | served |
| `0x4391` | parses | 4 B | Bare result ack for 0x4390 update stats | served |
| `0x4392` | sends | 1 B | Set game / advance the rotation | served |
| `0x4393` | parses | 4 B | Bare result ack for 0x4392 set game (advance the rotation) | served |
| `0x4394` | sends | variable | [UNKNOWN] In-match large record push | gap |
| `0x4395` | parses | 4 B | [UNKNOWN] Bare result ack for 0x4394 (never observed; COMMANDS.md lists it as a reachable gap, large struct) | unsent |
| `0x4398` | sends | variable | Update pings | served |
| `0x4399` | parses | 4 B | Bare result ack for 0x4398 update pings | served |
| `0x43A0` | sends | 8 B | Pass host | served |
| `0x43A1` | parses | 4 B | Bare result ack for 0x43a0 pass host | served |
| `0x43A2` | sends | variable | Per-player round weapon tallies *(verified spec)* | served |
| `0x43A3` | parses | 4 B | Bare result ack for 0x43a2 per-player weapon tallies | served |
| `0x43A4` | sends | variable | [UNKNOWN] In-match per-player list report | gap |
| `0x43A5` | parses | 4 B | [UNKNOWN] Bare result ack for 0x43a4 (never observed; COMMANDS.md reachable-in-ordinary-flow gap) | unsent |
| `0x43A6` | sends | 4 B | [UNKNOWN] In-match single-id command — our code names it PUT_CLIENT_SETTING; the spec title records only the shape | served † |
| `0x43A7` | parses | 4 B | [UNKNOWN] Bare result ack for 0x43a6 (never observed; COMMANDS.md reachable-in-ordinary-flow gap) — our code names it PUT_CLIENT_SETTING_RESULT; shape is a bare u32 | served † |
| `0x43B0` | sends | 29 B | [UNKNOWN] In-match eight-field report | gap |
| `0x43B1` | parses | 4 B | [UNKNOWN] Bare result ack for 0x43b0 (never observed; COMMANDS.md reachable-in-ordinary-flow gap) | unsent |
| `0x43C0` | sends | 162 B | In-game info / edit game settings | served |
| `0x43C1` | parses | 4 B | Bare result ack for 0x43c0 in-game info (edit name/comment/password) | served |
| `0x43C4` | sends | 4 B | [UNKNOWN] In-match enumerated command | gap |
| `0x43C5` | parses | 4 B | [UNKNOWN] Bare result ack for 0x43c4 (never observed; COMMANDS.md reachable-in-ordinary-flow gap) | unsent |
| `0x43C8` | sends | 5 B | Start round | served |
| `0x43C9` | parses | 8 B | Start-round reply (reply to 0x43c8) | served |
| `0x43D0` | sends | 1 B | Training parameter fetch | served † |
| `0x43D1` | parses | variable | Training parameters (reply to 0x43d0) | served † |
| `0x43E0` | sends | 1 B | Automatch status fetch — spec calls it automatch (PROTOCOL.md-backed via 0x43e1); COMMANDS.md still files 0x43e0/0x43e2 as "an in-match subsystem" and as a gap | served † |
| `0x43E1` | parses | 6 B | Automatch status (reply to 0x43e0) | served † |
| `0x43E2` | sends | empty | Automatch subsystem command — spec calls it automatch; COMMANDS.md files it as an unidentified in-match subsystem and a gap | gap |
| `0x43E3` | parses | 4 B | Automatch ack (reply to 0x43e2) | unsent |
| `0x43E4` | parses | 36 B | Automatch state push (UNSOLICITED, no result field) | unsent |
| `0x43F0` | parses | variable | [UNKNOWN] In-match subsystem push (UNSOLICITED, no result field) | unsent |
| `0x43F1` | parses | variable | [UNKNOWN] In-match game-settings push (UNSOLICITED, no result field) | unsent |
| `0x43F2` | parses | 4 B | [UNKNOWN] Unidentified in-match notification | unsent |
| `0x43F3` | parses | 4 B | [UNKNOWN] Unidentified in-match notification | unsent |
| `0x43F4` | parses | unread | [UNKNOWN] Unidentified in-match notification, EMPTY payload | unsent |
| `0x43F5` | parses | unread | [UNKNOWN] Unidentified in-match notification, EMPTY payload | unsent |

### Team and spectator (`0x44xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4400` | sends | 129 B | In-game chat send — `u8` coarse kind, ASCII channel digit (`'0'`-`'3'`), NUL-terminated text; capture-proven 2026-07-26 | served |
| `0x4401` | parses | variable | The chat line to display: `{u32 speaker chara_id, '0'+channel, text, NUL}`. Fanned out to every player in the game, sender included — the client has no local echo | served |
| `0x4440` | sends | 1 B | Team / spectator change | served |
| `0x4441` | parses | 4 B | 0x4440 ack | served |
| `0x4442` | parses | 4 B | [UNKNOWN] 0x4440-family push notification — client parses it, we only ever send 0x4441 — COMMANDS.md flags this as unresolved | unsent |

### ADDLIST, roster, search and history (`0x45xx`–`0x46xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4500` | sends | 5 B | ADDLIST add / change relationship | served |
| `0x4502` | parses | 25 B | Add/change relationship reply | served |
| `0x4510` | sends | 5 B | ADDLIST remove relationship | served |
| `0x4512` | parses | 9 B | Remove relationship reply | served |
| `0x4580` | sends | 1 B | Bulk roster fetch | served |
| `0x4581` | parses | 4 B | Bulk roster fetch, list START | served |
| `0x4582` | parses | variable | Bulk roster entries | served |
| `0x4583` | parses | 4 B | Bulk roster fetch, list END | served |
| `0x4600` | sends | 18 B | Player search; second byte is **ignore case** (1 = ignore) *(verified spec)* | served † |
| `0x4601` | parses | 4 B | Player search, list START | served |
| `0x4602` | parses | variable | Player-search result records | served |
| `0x4603` | parses | 4 B | Player search, list END | served |
| `0x4680` | sends | 4 B | Match history list request | served |
| `0x4681` | parses | 4 B | Match-history list START | served |
| `0x4682` | parses | variable | Match-history list record(s) (item packet of the 0x4680 triple) *(verified spec)* | served |
| `0x4683` | parses | 4 B | Match-history list END | served |
| `0x4684` | sends | 4 B | Match detail request | served |
| `0x4685` | parses | 4 B | Match-detail list START | served |
| `0x4686` | parses | variable | Match-detail record(s) (item packet of the 0x4684 triple) *(verified spec)* | served |
| `0x4687` | parses | 4 B | Match-detail list END | served |

### Connection info (`0x47xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4700` | sends | 22 B | Update connection info | served |
| `0x4701` | parses | 4 B | Connection-info ack | served |

### Mail (`0x48xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4800` | sends | 967 B | Send mail — `{u8 count, 8 x char[16] recipients, char[128] subject, char[708] body, s8 x2}`; all three text fields capture-confirmed | served |
| `0x4801` | parses | 5 B on success | Send-mail reply; **flags bit 0 must be SET** or the client silently re-sends the whole letter as 0x4860. Error list only when status is nonzero | served |
| `0x4802` | parses | unread | Mail-send notification, EMPTY payload | unsent |
| `0x4820` | sends | 1 B | Get messages | served |
| `0x4821` | parses | 4 B | Mailbox list START | served |
| `0x4822` | parses | 266 B | Mailbox entry, **one per packet**; wire byte 0 is a routing category 0..3, not a type — 0x0F corrupts the client heap | served |
| `0x4823` | parses | 4 B | Mailbox list END | served |
| `0x4840` | sends | 2 B | Open a letter — `{s1 category, u1 index}`, capture-confirmed | served |
| `0x4841` | parses | 712 B | Opened letter: u32 result + 708-byte body block (layout undecoded; we send the body text) | served |
| `0x4860` | sends | 969 B | File / forward mail | gap |
| `0x4861` | parses | 4 B | 0x4860 mail-manage ack | unsent |
| `0x4880` | sends | 2 B | Delete a letter — same `{s1 category, u1 index}` pair as 0x4840 | served |
| `0x4881` | parses | 4 B | 0x4880 delete ack, bare u32 | served |

### Game lobby / GHQ (`0x49xx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4900` | sends | empty | Get game lobby info | served |
| `0x4901` | parses | 4 B | Game-lobby list START | served |
| `0x4902` | parses | variable | Game-lobby list entries *(verified spec)* | served |
| `0x4903` | parses | 4 B | Game-lobby list END | served |
| `0x4904` | sends | 4 B | [UNKNOWN] Game lobby info request variant (one id) | gap |
| `0x4905` | parses | 822 B | [UNKNOWN] Game-entry info reply, 822 bytes | unsent |
| `0x4908` | sends | 1 B | [UNKNOWN] Game lobby info request variant (one byte) | gap |
| `0x4909` | parses | variable | [UNKNOWN] 912-byte detail record (0x49xx clan/GHQ/roster block) | unsent |
| `0x4910` | sends | 168 B | [UNKNOWN] Create/configure game lobby entry (168 bytes) | gap |
| `0x4911` | parses | variable | [UNKNOWN] Clan record (shared 0xD4AF34 layout) | unsent |
| `0x4912` | sends | 20 B | [UNKNOWN] Game lobby request with id and optional 16-byte name | gap |
| `0x4913` | parses | variable | [UNKNOWN] Clan record (shared 0xD4AF34 layout) | unsent |
| `0x4914` | sends | empty | [UNKNOWN] Game lobby request, empty body | gap |
| `0x4915` | parses | 4 B | [UNKNOWN] Result ack that tears down the cached clan on success | unsent |
| `0x4918` | parses | 28 B | [UNKNOWN] Clan notification — member joined/updated (28-byte payload) | unsent |
| `0x4919` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x491A` | parses | 6 B | [UNKNOWN] Clan notification — header only (no payload beyond the 6-byte key) | unsent |
| `0x491B` | sends | 11 B | [UNKNOWN] Game lobby request (u4, u2, u1, u4) | gap |
| `0x491C` | parses | 12 B | [UNKNOWN] Two-word result reply, 0x49xx clan/GHQ family | unsent |
| `0x4920` | sends | 5 B | [UNKNOWN] Game lobby request (u4, u1) | gap |
| `0x4921` | parses | 4 B | [UNKNOWN] Result ack, 0x49xx clan/GHQ family | unsent |
| `0x4922` | parses | 15 B | [UNKNOWN] Clan notification carrying u32 + u8 + u32 | unsent |
| `0x4923` | sends | 1 B | [UNKNOWN] Game lobby request (one byte) | gap |
| `0x4924` | parses | 4 B | [UNKNOWN] Result ack, 0x49xx clan/GHQ family | unsent |
| `0x4925` | parses | 26 B | [UNKNOWN] Clan notification carrying u32 + 16-byte string | unsent |
| `0x4930` | sends | 1 B | [UNKNOWN] Game lobby request (boolean byte) | gap |
| `0x4931` | parses | 4 B | [UNKNOWN] Result ack, 0x49xx clan/GHQ family | unsent |
| `0x4932` | parses | 12 B | [UNKNOWN] Clan notification carrying u8 + u32 + u8 | unsent |
| `0x4940` | sends | 1 B | [UNKNOWN] Game lobby request (one byte) | gap |
| `0x4941` | parses | 4 B | [UNKNOWN] Result ack, 0x49xx clan/GHQ family | unsent |
| `0x4942` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x4943` | parses | variable | [UNKNOWN] Clan notification carrying u8 + eight u8s | unsent |
| `0x4950` | parses | variable | [UNKNOWN] Clan notification — full member refresh (u8 + eight u8s + 204-byte block) | unsent |
| `0x4960` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word (key check waived) | unsent |
| `0x4961` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x4964` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x4965` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x4966` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x4967` | parses | 10 B | [UNKNOWN] Clan notification carrying one 4-byte word | unsent |
| `0x4980` | sends | empty | [UNKNOWN] Game lobby request, empty body | gap |
| `0x4981` | parses | 4 B | [UNKNOWN] Clan-member list START (opens the 0x4981/0x4982/0x4983 triple) | unsent |
| `0x4982` | parses | variable | [UNKNOWN] Clan-member list ENTRIES (middle of the 0x4981/0x4982/0x4983 triple) | unsent |
| `0x4983` | parses | 4 B | [UNKNOWN] Clan-member list END (closes the 0x4981/0x4982/0x4983 triple) | unsent |
| `0x4984` | sends | 4 B | [UNKNOWN] Game lobby request (one u4) | gap |
| `0x4985` | parses | variable | [UNKNOWN] Clan record — allocating variant (shared 0xD4AF34 layout) | unsent |
| `0x4986` | sends | 4 B | [UNKNOWN] Game lobby request (one u4) | gap |
| `0x4987` | parses | variable | [UNKNOWN] Clan record + 204-byte block (shared 0xD4AF34 layout) | unsent |
| `0x4990` | sends | empty | Get game entry info | served |
| `0x4991` | parses | variable | Game entry info — reply to 0x4990 (four 57-byte records) | served |
| `0x4992` | sends | 4 B | [UNKNOWN] Game entry info request (one u4) | gap |
| `0x4993` | parses | 8 B | [UNKNOWN] Game entry withdraw/remove ack (removes one 0x4991 record) | unsent |
| `0x49A0` | sends | 1 B | [UNKNOWN] Game lobby request (one byte from a struct) | gap |
| `0x49A1` | parses | variable | [UNKNOWN] Clan record (shared 0xD4AF34 layout) | unsent |
| `0x49A2` | parses | variable | [UNKNOWN] Clan notification — member array refresh (u8 + eight 21-byte records) | unsent |
| `0x49A8` | parses | 8 B | [UNKNOWN] Clan notification — serial bump (u16 payload) | unsent |
| `0x49B0` | sends | 8 B | [UNKNOWN] Game lobby request (two u4) | gap |
| `0x49B1` | parses | variable | [UNKNOWN] Unmapped 0x49xx full-record reply, 420 bytes | unsent |
| `0x49C0` | sends+parses | variable | [UNKNOWN] Game-lobby request with a counted id list — two unrelated layouts share this id, one per direction (see blanks/README.md) | gap |
| `0x49C0` | sends+parses | variable | [UNKNOWN] Unmapped 0x49xx keyed-update reply — two unrelated layouts share this id, one per direction (see blanks/README.md) | unsent |
| `0x49C1` | parses | 32 B | [UNKNOWN] Unmapped 0x49xx single-record reply | unsent |
| `0x49C2` | sends | 5 B | [UNKNOWN] Game-lobby / roster request, u32 + small enum | gap |
| `0x49C3` | parses | 9 B | [UNKNOWN] Unmapped 0x49xx reply | unsent |

### Unidentified subsystem (`0x4Axx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4A00` | parses | variable | [UNKNOWN] Unmapped 0x4Axx record reply | unsent |
| `0x4A01` | parses | variable | [UNKNOWN] Unmapped 0x4Axx record reply with a state-bounded blob | unsent |
| `0x4A02` | parses | 139 B | [UNKNOWN] Unmapped 0x4Axx reply, echo plus a 128-byte blob | unsent |
| `0x4A03` | parses | 12 B | [UNKNOWN] Unmapped 0x4Axx reply, word plus four halves | unsent |
| `0x4A10` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A11` | parses | variable | [UNKNOWN] Unmapped 0x4Axx list reply, 45-byte records | unsent |
| `0x4A12` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A13` | parses | variable | [UNKNOWN] Unmapped reply, two named eight-word groups | unsent |
| `0x4A20` | parses | variable | [UNKNOWN] Unmapped 0x4Axx reply, counted groups plus state-bounded blob | unsent |
| `0x4A21` | parses | variable | [UNKNOWN] Unmapped 0x4Axx reply, counted groups plus state-bounded blob | unsent |
| `0x4A22` | parses | 143 B | [UNKNOWN] Unmapped 0x4Axx reply, blob plus trailing word | unsent |
| `0x4A24` | parses | variable | [UNKNOWN] Unmapped 0x4Axx full-record reply | unsent |
| `0x4A25` | sends | empty | [UNKNOWN] Unidentified subsystem, no payload | gap |
| `0x4A26` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A27` | parses | 15 B | [UNKNOWN] Unmapped 0x4Axx reply, byte plus 8-byte blob | unsent |
| `0x4A28` | parses | variable | [UNKNOWN] Unmapped 0x4Axx reply, eight-word array | unsent |
| `0x4A29` | parses | 139 B | [UNKNOWN] Unmapped 0x4Axx reply, echo plus a 128-byte blob | unsent |
| `0x4A30` | sends | 4 B | [UNKNOWN] Unidentified subsystem, single u32 | gap |
| `0x4A31` | parses | variable | [UNKNOWN] Unmapped 0x4Axx full-record reply | unsent |
| `0x4A32` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A33` | parses | variable | [UNKNOWN] Unmapped 0x4Axx list reply, 45-byte records | unsent |
| `0x4A34` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A40` | sends | empty | [UNKNOWN] Unidentified subsystem, no payload | gap |
| `0x4A41` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A42` | parses | variable | [UNKNOWN] Unmapped 0x4Axx list reply, 94-byte records | unsent |
| `0x4A43` | parses | 4 B | [UNKNOWN] Unmapped clan/GHQ-block reply | unsent |
| `0x4A47` | parses | 5 B | [UNKNOWN] Unmapped 0x4Axx reply, parsed inline in the dispatcher | unsent |
| `0x4A50` | parses | 269 B | [UNKNOWN] Unmapped 0x4Axx reply with a 256-byte text block | unsent |

### Clan / GHQ (`0x4Bxx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4B00` | sends | 144 B | [CONFIRMED] Create clan: `name[16]` + `description[128]` | served |
| `0x4B01` | parses | 8 B | [CONFIRMED] Create result `{result, clan_id}`; client sets itself leader | served |
| `0x4B04` | sends | empty | [CONFIRMED] Disband clan, leader only, no payload | served |
| `0x4B05` | parses | 4 B | [CONFIRMED] Disband result (`-1205` inside the cooldown) | served |
| `0x4B10` | sends | 6 B | [CONFIRMED] Clan list `{u8 kind, s32 amount, u8}`; amount is a 1-based entry index | served |
| `0x4B11` | parses | 12 B | [CONFIRMED] Clan-list header `{result, offset, total}` — offset FIRST | served |
| `0x4B12` | parses | variable | [CONFIRMED] Clan-list records, 48 B; the 101st fails the packet with `-71` | served |
| `0x4B13` | parses | 4 B | [CONFIRMED] Clan-list END | served |
| `0x4B20` | sends | 4 B | [CONFIRMED] Clan profile request, own clan only (id cross-checked) | served |
| `0x4B21` | parses | 777 B | [CONFIRMED] Clan profile block — see PROTOCOL.md for the slot map | served |
| `0x4B30` | sends | 4 B | [CONFIRMED] Accept applicant `{u32 chara id}` | served |
| `0x4B31` | parses | 4 B | [CONFIRMED] Accept-applicant result | served |
| `0x4B32` | sends | 4 B | [CONFIRMED] Decline applicant `{u32 chara id}` | served |
| `0x4B33` | parses | 4 B | [CONFIRMED] Decline-applicant result | served |
| `0x4B36` | sends | 4 B | [CONFIRMED] Banish member `{u32 chara id}` | served |
| `0x4B37` | parses | 4 B | [CONFIRMED] Banish result | served |
| `0x4B40` | sends | empty | [CONFIRMED] Cancel join / leave clan, no payload | served |
| `0x4B41` | parses | 4 B | [CONFIRMED] Cancel-join result | served |
| `0x4B42` | sends | 4 B | [CONFIRMED] Apply to join `{u32 clan id}`; not sent unless the cached record holds an id | served |
| `0x4B43` | parses | 4 B | [CONFIRMED] Apply-to-join result | served |
| `0x4B46` | sends | 2 B | [CONFIRMED] Clan-record probe — **blocks from the clan menu**, not from the connect burst | served |
| `0x4B47` | parses | 28 B | [CONFIRMED] Clan record `{result, id, state, privileges, emblem flag, name[16]}` | served |
| `0x4B48` | sends | 4 B | [CONFIRMED] Emblem fetch, own clan; blocks character select | served |
| `0x4B49` | parses | 772 B | [CONFIRMED] Emblem, result + 768-byte block -> `profile+6873` | served |
| `0x4B4A` | sends | 4 B | [CONFIRMED] Emblem display fetch `{u32 clan id}` | served |
| `0x4B4B` | parses | 772 B | [CONFIRMED] Emblem, result + 768-byte block | served |
| `0x4B4C` | sends | 4 B | [CONFIRMED] Second emblem fetch, sent right after the profile | served |
| `0x4B4D` | parses | 772 B | [CONFIRMED] Emblem, result + 768-byte block | served |
| `0x4B50` | sends | 769 B | [CONFIRMED] Emblem UPLOAD `{u8 mode, byte[768]}`; mode 3 = put on display | served |
| `0x4B51` | parses | 4 B | [CONFIRMED] Emblem-upload result (`-1216` on cooldown) | served |
| `0x4B52` | sends | 4 B | [CONFIRMED] Roster request `{u32 clan id}` | served |
| `0x4B53` | parses | 4 B | [CONFIRMED] Roster START — result code, never a count | served |
| `0x4B54` | parses | variable | [CONFIRMED] Roster ITEMS, 68 B; `isMember` 1 = member, 0 = applicant | served |
| `0x4B55` | parses | 4 B | [CONFIRMED] Roster END | served |
| `0x4B60` | sends | 4 B | [CONFIRMED] Transfer leadership `{u32 chara id}` | served |
| `0x4B61` | parses | 4 B | [CONFIRMED] Transfer-leadership result | served |
| `0x4B62` | sends | 4 B | [CONFIRMED] Set emblem editor `{u32 chara id}` | served |
| `0x4B63` | parses | 4 B | [CONFIRMED] Set-emblem-editor result | served |
| `0x4B64` | sends | 128 B | [CONFIRMED] Set clan COMMENT (the `T+0x67A` field) | served |
| `0x4B65` | parses | 4 B | [CONFIRMED] Set-comment result | served |
| `0x4B66` | sends | 512 B | [CONFIRMED] Set clan NOTICE (the `T+0x700` field) | served |
| `0x4B67` | parses | 4 B | [CONFIRMED] Set-notice result | served |
| `0x4B70` | sends | 4 B | [CONFIRMED] Clan stats request | served |
| `0x4B71` | parses | 584 B | [CONFIRMED] Clan per-mode stat grid; second word must be 2 or 3, send exactly ONE | served |
| `0x4B72` | parses | 580 B | [CONFIRMED] Clan stat blocks, sent after the single 0x4B71 | served |
| `0x4B73` | sends | 4 B | [ELF] Applicant-list request — **never sent**; applications arrive as mail (`0x4820` type `0x10`) | served |
| `0x4B74` | parses | 4 B | [ELF] Applicant-list START | unsent |
| `0x4B75` | parses | variable | [ELF] Applicant-list ITEMS, 93 B | unsent |
| `0x4B76` | parses | 4 B | [ELF] Applicant-list END | unsent |
| `0x4B80` | sends | 4 B | [CONFIRMED] Clan Info for a clan you are NOT in `{u32 clan id}` | served |
| `0x4B81` | parses | 217 B | [CONFIRMED] Partial clan profile; `subject_id` NOT cross-checked | served |
| `0x4B90` | sends | 18 B | [CONFIRMED] Clan search `{u8 exact_only, u8 ignore_case, name[16]}` | served |
| `0x4B91` | parses | 4 B | [CONFIRMED] Clan-search START | served |
| `0x4B92` | parses | variable | [CONFIRMED] Clan-search ITEMS, 44 B (another build writes 48) | served |
| `0x4B93` | parses | 4 B | [CONFIRMED] Clan-search END; sets block+0x08 = 0, block+0x0C = record count | served |

### Tail subsystems (`0x4Dxx`–`0x4Exx`)

| id | client | payload | summary | our status |
| --- | --- | --- | --- | --- |
| `0x4D00` | parses | 6 B | [UNKNOWN] 6-byte notification | unsent |
| `0x4E00` | sends | empty | [UNKNOWN] Isolated tail subsystem, no payload | gap |
| `0x4E10` | parses | 236 B | [UNKNOWN] Session/room state push, 236 bytes | unsent |
| `0x4E11` | parses | variable | [UNKNOWN] Session/room list ITEMS, 47-byte records | unsent |
| `0x4E12` | parses | 4 B | [UNKNOWN] 0x4e1x tail subsystem reply, single result code— list-triple END | unsent |
| `0x4E20` | parses | 53 B | [UNKNOWN] Context update, 53 bytes | unsent |
| `0x4E22` | parses | 8 B | [UNKNOWN] Context update, 8 bytes | unsent |
| `0x4E23` | parses | 8 B | [UNKNOWN] Context update, 8 bytes | unsent |


---

## Defects — ids our server touches that the client does not

These have **no row above**, because they are absent from both ELF-derived id lists — which is
precisely the problem. Each is our code emitting or binding an id the client has no use for.

| id | our status | what | action |
| --- | --- | --- | --- |
| `0x4115` | **PHANTOM** | chat-macro write-back reply. `0x4114` is fire-and-forget (observed non-blocking), so the ignored reply costs nothing today — but the client has no parser for it. | stop sending |
| `0x4140` | **PHANTOM** | skill sets, emitted inside the connect burst. No client parser, so saved skill-set slots may never populate from it. | trace the real path (`0x4133` outfit readback is the likelier one) before changing — the burst otherwise works |
| `0x4142` | **PHANTOM** | gear sets, same position and same problem as `0x4140`. | as above |
| `0x4501` / `0x4503` | **PHANTOM** | ADDLIST acks. `HostGameController` records that an exhaustive scan found no parser for either. | verify against `0x4502` and remove |
| `0x43CA` / `0x43CB` | **MISNUMBERED** *(resolved 2026-07-23)* | our start-round handler was bound to `0x43CA`; the client sends `0x43C8` and parses `0x43C9`. `0x43CA` has no builder anywhere in the ELF. | done — renumbered in code; listed here as the worked example, and because comments in `GameService`/`HostGameController` still mention the old ids |

`0x4442` is the mirror shape and is in the tables above: the client parses it, we only ever emit
`0x4441`, and whether the `0x4440` team/spectator flow expects both is unresolved.

---

## Completely unknown — the countable remainder

**120 of 315 ids** have no established meaning, down from 175: **the whole 55-id clan block came
off this list on 2026-07-27**, identified command by command against a live client. (`0x4400` and
`0x4401` came off 2026-07-26.) Their layouts are largely recovered; their purpose is not.

The per-direction figures previously quoted here (55 of 112 and 121 of 204) never summed to the
totals — 55 + 122 = 177 against 112 + 204 = 316 — a discrepancy that predates all of this and has
still not been chased down, so no per-direction split is given now. Grouped:

- **Gate / account** (4): `0x2006` · `0x2007` · `0x3040` · `0x3041`
- **Connect family** (2): `0x4112` · `0x4113` — both answered since 2026-07-27 and `0x4112` is
  known to block, but the 32 bytes it carries are still unidentified, so it stays on this list.
- **Player card** (4): `0x4210` · `0x4211` · `0x4212` · `0x4213`
- **Host / game** (18): `0x4348` · `0x4349` · `0x4394` · `0x4395` · `0x43A4` · `0x43A5` · `0x43A6` · `0x43A7` · `0x43B0` · `0x43B1` · `0x43C4` · `0x43C5` · `0x43F0` · `0x43F1` · `0x43F2` · `0x43F3` · `0x43F4` · `0x43F5`
- **Team / spectator** (1): `0x4442` — (`0x4400` and `0x4401` both left this list 2026-07-26: the
  in-game chat send and its delivery, decoded from four live captures plus an ELF trace of the
  consumer, then implemented and confirmed against two clients.)
- **Game lobby / GHQ** (55): `0x4904` · `0x4905` · `0x4908` · `0x4909` · `0x4910` · `0x4911` · `0x4912` · `0x4913` · `0x4914` · `0x4915` · `0x4918` · `0x4919` · `0x491A` · `0x491B` · `0x491C` · `0x4920` · `0x4921` · `0x4922` · `0x4923` · `0x4924` · `0x4925` · `0x4930` · `0x4931` · `0x4932` · `0x4940` · `0x4941` · `0x4942` · `0x4943` · `0x4950` · `0x4960` · `0x4961` · `0x4964` · `0x4965` · `0x4966` · `0x4967` · `0x4980` · `0x4981` · `0x4982` · `0x4983` · `0x4984` · `0x4985` · `0x4986` · `0x4987` · `0x4992` · `0x4993` · `0x49A0` · `0x49A1` · `0x49A2` · `0x49A8` · `0x49B0` · `0x49B1` · `0x49C0` · `0x49C1` · `0x49C2` · `0x49C3`
- **Unidentified `0x4Axx`** (28): `0x4A00` · `0x4A01` · `0x4A02` · `0x4A03` · `0x4A10` · `0x4A11` · `0x4A12` · `0x4A13` · `0x4A20` · `0x4A21` · `0x4A22` · `0x4A24` · `0x4A25` · `0x4A26` · `0x4A27` · `0x4A28` · `0x4A29` · `0x4A30` · `0x4A31` · `0x4A32` · `0x4A33` · `0x4A34` · `0x4A40` · `0x4A41` · `0x4A42` · `0x4A43` · `0x4A47` · `0x4A50`
- ~~**Clan / GHQ** (55)~~ — **all 55 identified 2026-07-27.** Every id in the block has a meaning
  and a handler; see the clan section of `PROTOCOL.md` and the `mgo2_cmd_4b*` specs. The three
  applicant-list replies (`0x4B74`/`0x4B75`/`0x4B76`) are understood but unexercised, because the
  client never sends `0x4B73` — clan applications arrive as mail.
- **Tail** (8): `0x4D00` · `0x4E00` · `0x4E10` · `0x4E11` · `0x4E12` · `0x4E20` · `0x4E22` · `0x4E23`

`0x49xx` (game lobby / GHQ) now dominates alone. It is wired end to end in the client — request
builders and reply parsers both — and neither `PROTOCOL.md` nor `OBSERVED.md` says a word about it.
`0x4Bxx` was its twin in that description until 2026-07-27, and the way it fell is the lesson: not
by disassembly, but by answering all 23 requests at once, watching which screens came alive, and
letting each newly-truthful field unlock the next dormant branch. `0x4Axx` is worse: no subsystem identification at all, only parser
shapes. Several `0x4Axx` and `0x49xx` parsers read byte-for-byte identical layouts to each other
(`0x4A11`/`0x4A33`, and the seven `0x49xx` "one 4-byte word" notifications); that is a matching
shape, not a proven duplicate, and no divergence test has been run.

Everything above is ELF-derived unless a row is marked as a verified spec. Confirming any of it
means putting the client in front of the feature and capturing what it actually sends.

---

## What is not established

Limits of this document, stated so they are not mistaken for findings.

- **No reachability pass has been run.** The send-side scan proved that every builder call site
  exists and resolves to a literal id; it did **not** prove that every call site is reachable from
  live code, that no parser is a stub, and that no dispatcher arm falls through. Until that pass
  runs, **no id can be labelled `dead`, and no id's lack of that label means it is live.** This is
  the single largest unknown in the table: some fraction of the 177 `[UNKNOWN]` ids may be
  unreachable in the shipped game, and there is currently no way to tell which from this file.

  The `dead` label was searched for and applied to nothing — not inferred away, checked. Every
  spec's evidence was read for the positive markers that would justify it (a builder with no
  caller, a parser that reads and stores nothing, a dispatcher arm falling through to a stub) and
  none surfaced. The closest-looking candidates are all the opposite of dead:

  | id | why it looked dead | why it is not |
  | --- | --- | --- |
  | `0x43F4` | parser `0xD5B45C` opens no reader; no read primitive anywhere in the function | it fires UI event `0x2F` with value 0 and calls `0xD5B41C`. A bare notify — the id *is* the message |
  | `0x43F5` | parser `0xD5B3B0`, same shape, no reader | fires UI event `0x37`. Bare notify |
  | `0x4802` | parser `0xD54090`, no reader opened | stores `-1` at `ctx+0x1554` and fires UI event `0x32`. Bare notify |
  | `0x2002` / `0x2004` | payload `unread` — we send four bytes nobody reads | the *packet* is load-bearing (list start/end); only its body is ignored |

  "Opens no reader" is a statement about the payload, not about the id — conflating the two is how
  a live notify gets deleted.

  Two ids that would be miscategorised by a careless pass:

  - **`0x43CA` / `0x43CB`** have no builder and no parser anywhere in the ELF. Absence *from* the
    binary is not dead code *in* the binary — there is nothing there to be dead. They were our
    misnumbering of `0x43C8`/`0x43C9`, resolved 2026-07-23, and appear only in the defects table.
  - **`0x0001`** (echo) has no builder in the lobby packet library and is plainly in use. It lives
    in the pre-lobby handshake, outside that library's scope, so it has no row here at all. The
    builder scan's completeness claim is scoped to the lobby library and does not extend to it.

- **Meaning vs shape.** 177 of 315 ids carry `[UNKNOWN]`. Every one has field order and widths
  from the binary, and a `meta.title` — but a title is not a meaning. Where the title reads
  "unmapped `0x4Axx` list reply, 45-byte records", that is a description of bytes, not of purpose.
- **Sizes are computed, not captured.** Payload sizes come from summing each spec's `seq`, which
  is the parser's or builder's own read/write sequence. Where a spec is wrong, the size inherits
  the error. Only the nine verified specs in `dev/proto/` have been checked against live bytes.
- **Matching shapes are not proven duplicates.** Several ids read byte-identical layouts. No
  divergence test has been run on any of them, so they are recorded as matching, never as the
  same message.
- **`served` reflects the source tree, not a live test.** It means a handler exists, not that the
  client has been observed accepting the reply.
