# Automatching

Everything the client needs to complete an automatch connection, read from `MGO2.elf` and the disc
on 2026-07-28 by four parallel investigations. Three names in `PROTOCOL.md`/`PACKETS.md` were wrong
and are corrected here. **Implementation status is in §7a** — currently: the search, the queue, the
panel push and match forming all work and are confirmed live, but an automatch game **hangs on the
loading screen**, and slot-in is not built.

The short version: automatch is **not a separate connection path**. The server picks a host, tells
everyone, and the clients re-enter the ordinary create-game and join-game handshakes we already
serve. The gap is four packets and a matchmaker, not a subsystem.

---

## 1. What the feature is

The disc puts Automatching in the same family as Tournament, Survival, Official Tournament and
Training: a **scheduled, server-operated session with server-owned rules**. The server notice table
(`MGO_ERROR_RES_GMINFO`) carries a perfectly parallel set of announcements for each:

| id | notice |
| --- | --- |
| 478 | Automatching will be held from %s. |
| 485 | Automatching will be held from %s on the %s server. |
| 493 | Automatching will finish shortly. |
| 499 | Automatching rules have been updated. |

That parallel table is what explains the otherwise-puzzling error pair **4928 "not available"** vs
**4929 "not open"**: there is meant to be a *window*, and being outside it is a distinct state from
the feature being off. Whether Konami ran automatching on release day is a **scheduling question we
cannot answer from our artifacts** — see §8.

The player expresses one preference and the server decides everything else. The lobby-select
description says so: *"Automatically create a game with characters close to your level"* (string
260), and Otacon's offline tutorial repeats it — *"battle against players of the same level"*
(`ota_chat` string 49). **Level matching is advertised as the server's job, never as a control.**

---

## 2. The client's side, in order

State machine `0x93C7D8`, 18 states, jump table `0x93C940`. Screen object `S`: `S+0x64` state,
`S+0x68` request timer, `S+0x6C` search timer, `S+0x438` host id, `S+0x444` game id, `S+0x450` the
category list (792-byte rows).

```
construct 0x93B4D0 ──▶ states 0,1,2,3   pure UI, NO traffic
   confirm on the rule list (0x94A224 returns 1)
state 4   0x93CD58   SEND 0x43e0 <u8 rule>          builder 0xD5BCB4, wait slot 50
state 5   0x93CDBC   await 0x43e1                   6000 ticks ──▶ 4931
   result 0: build panel 0x93C2C4, REGISTER push channel 60 at 0x93CF10
state 6   0x93CF78   SEARCHING — sends nothing, ever
   180000 ticks ──▶ state 7 (self-cancel);  cancel button ──▶ state 7
   event 42 (0x43e4) repaints in place, stays in 6
state 7   0x93D0F8   UNREGISTER channel 60, SEND 0x43e2   builder 0xD5BBDC, wait slot 51
state 8   0x93D160   await 0x43e3                   6000 ticks ──▶ 4933

  ── asynchronously, from state 6 ──
event 44 (0x43f1)  0x93DBF4   hostId == my char id ? state 12 : state 18 (park)
state 12  0x93D334   spawn create-game task 0x8C9FA4 ──▶ 13
state 13  0x93D47C   failure ──▶ state 1, NO DIALOG
event 45 (0x43f2)  0x93DDA0   unregister ch 60; store game id; ──▶ state 11
state 11  0x93D2C8   wait 180 ticks, then stagger (myCharId & 7)*150 + 150
state 14/15/16      count down, spawn join task 0x94459C, await it
                    failure ──▶ state 1, NO DIALOG
```

**Entering the lobby sends nothing.** `PROTOCOL.md` said `0x43e0` is "sent on entry to the
automatching lobby". It is sent on **confirm**, from state 4 only, and the constructor
`0x93B4D0` contains no network call at all (verified by enumerating every `bl` target in
`0x93B4D0..0x93BDC8`).

**There is no heartbeat.** State 6 calls only widget, sprintf, input and sound routines. While
searching, the client is purely push-driven — if the server goes quiet, the player watches a
stopwatch until the 180000-tick timeout.

### Timing

Both timers advance `+5` per screen update.

| timer | ticks | meaning |
| --- | --- | --- |
| reply to `0x43e0` / `0x43e2` | 6000 | the house-standard command deadline — this literal appears at 64 sites |
| the search itself | 180000 | 30× the standard deadline |

Calibrating against this project's observed **~40 s** command timeout gives **≈150 units/s**, so the
search window is **≈20 minutes**. The 150 figure is *derived from a tier-2 observation*, not read
from the binary; the joiner stagger corroborates it (`(charId & 7)*150 + 150` decremented by 5 is
1–9 s in 1-second steps, which is what a staggered join should be).

---

## 3. The packets

| cmd | dir | VA | size | role |
| --- | --- | --- | --- | --- |
| `0x43e0` | C→S | builder `0xD5BCB4` | 1 B | **START automatching.** u8 = rule filter |
| `0x43e1` | S→C | parser `0xD5BF98` | 6 B | u32 result; **if 0 only**: u8 band, u8 players-needed |
| `0x43e2` | C→S | builder `0xD5BBDC` | empty | **CANCEL** |
| `0x43e3` | S→C | parser `0xD5BB04` | 4 B | u32 result |
| `0x43e4` | S→C push | parser `0xD5BDCC` | 36 B | search panel; event 42 |
| `0x43f0` | S→C push | parser `0xD5B868` | 78 B | event 43 — **the automatch screen ignores it** |
| `0x43f1` | S→C push | parser `0xD5B664` | 223 B | **THE MATCH.** u32 host char id + settings; event 44 |
| `0x43f2` | S→C push | parser `0xD5B588` | 4 B | **u32 game id** — releases the joiners; event 45 |
| `0x43f3` | S→C push | parser `0xD5B4D0` | 4 B | event 46 ⇒ error 4945 |
| `0x43f4` | S→C push | parser `0xD5B45C` | empty | event 47 ⇒ error 4929 |
| `0x43f5` | S→C push | parser `0xD5B3B0` | empty | event 55 — **not** on this screen |

`PACKETS.md` filed the whole `0x43f*` range as "an in-match subsystem". It is the automatch family:
all six parsers touch the same status block and raise UI events **42–47**, and the only handler for
those is `0x93D6E0`, the automatch screen's own jump table (`0x93D748`, six arms).

Naming corrections this forces:

- **`0x43e0` is "start automatching", not "status fetch".** Proof is the client's own error table:
  a timeout on `0x43e0`'s slot raises 4931 *"…Unable to **start** automatching"* (`0x93CDD4`);
  `0x43e2`'s raises 4933 *"…Unable to **cancel**"* (`0x93D178`).
- `0x43e2` **is** cancel, as documented. Its result-0 reply clears the status block.
- A rescan of all 115 `bl 0xD5CF40` send sites confirms **`0x43e0` and `0x43e2` are the only
  automatch sends in the binary.** Each builder has exactly one caller.

### `0x43e1` — 6 bytes

```
u32 result        ; 0 = accepted. Only on 0 are the next two bytes read.
u8  band          ; level half-width, clamped [0,22] — the lit window on the gauge
u8  playersNeeded ; nonzero → printed via string 917 "%d"; zero → string 48
```

**`playersNeeded` confirmed live 2026-07-28.** A search with one player queued and `MIN_PLAYERS = 2`
sent `0x01` in this byte, and the client displayed **"Players Needed: 1"**. Until then the field was
an inference from crossing the ELF read at `0x93D7A8` against disc strings 916/917; it is now
observed. The `band` byte is still inference only — nothing has yet sent a nonzero one.

Result 0 does two things nothing else does: it sets the **loaded flag** (§4) and it **registers push
channel 60**. Anything pushed before that is parsed into memory and dropped.

### `0x43e4` — 36 bytes, the search panel

```
[0x00..0x0F] arrayA        ; 23 packed nibbles, 12 bytes used, 4 ignored
[0x10]       band          ; same as 0x43e1's
[0x11]       playersNeeded ; same as 0x43e1's
[0x12]       eventArg      ; passed to event 42 and discarded by the only handler
[0x13..0x22] arrayB        ; same packing
[0x23]       unused        ; stored at block+4, never read anywhere
```

Packing: byte *j* holds column `2j` in the low nibble and `2j+1` in the high nibble, columns 0–22.
Bar height for column *i* is `A[i] + B[i]`, clamped to 15 (960 px / 64 px per unit,
`0x93C754`–`0x93C784`).

**The axis is player level.** The centre column is `levelFromScore(charRec+0x120)` via `0x6F9260`,
clamped 0–22; the lit window is `[centre − band, centre + band]`. The 23 is confirmed four ways: the
loop bound at `0x93C790` and four 23-entry sprite-hash tables at `0xE14BA0 + 128/220/312/404`.

**The level table is not in the binary — it is on the disc, and has been recovered** (2026-07-28).
`0x6F9260` walks a 128-entry u32 array in `.bss` at `0x1659D24` — pointer at `0xFDE280`, zero at
load — filled at runtime by the GCX native `0x6F9370` (option letter `-r`) from a stage script. It
sits `0x200` bytes below the `ComputeScore` table `ADDRESSES.md` already records as script-fed: same
allocation, same lifecycle.

**The numbers, read from six stage scripts byte-identically** (`lobby`, `n002a`, `n003a`, `n004a`,
`n007a`, `n012a`), the sole call site of that native in each:

```
125 250 375 500 650 800 950 1100 1275 1450
1625 1800 2000 2200 2400 2600 2850 3100 3350 3600 4100 4600
```

Twenty-two entries, so the cap is **level 22 at 4,600 experience** — which is exactly why the gauge
is 23 columns. All twelve recorded live readings reproduce, with `T[3] = 500` bracketed to a single
experience point. Now in `mgo2server.common.Level`.

The native was identified through the GCX registration table rather than the shape of the data:
hash `0x00D3656D` at `0x1031584` → OPD `0x1014CF0` → `0x6F9370`. The same walk reproduces the
sibling `ComputeScore` native that `ADDRESSES.md` already records, which is what validates it.

The algorithm *is* readable, and it corrects a claim in `CharacterService`: the level is the **count
of thresholds `<=` experience**, not one more than that count (signed `ble` at `0x6F9278`; the
return is the count). Below the first threshold it returns 0. `charRec+0x120` is
`session+0x58F8`, written by the `0x4101` parser from **wire offset `0x1C` — the u32 the server
already sends as "experience"**, not a separate career score and not `chara.rank`.

The 22 is a presentation clamp at `0x93C348`, not a property of the table. `countLevels()` at
`0x6F9328` exists precisely because the client does not know how many levels there are either.

The same function is a **real gate elsewhere**: `0x8BA560` admits a player to a game only when
`base − tolerance <= level <= base + tolerance`, behind bit 12 of the flags word — so
`level_limit_base` and `level_limit_tolerance` are in **level units**, not experience.

**What A and B are** — the ELF cannot distinguish them (nothing reads them apart; the only consumer
sums them), but the disc names the panel: **"Entry Status"** (915) with two values, **"Matching"**
(924) and **"In Game"** (923). So one series is players queued and the other players already in a
game, per level band. *Which array is which is undetermined* — and because the client only ever
displays the sum, no client behaviour can tell us. Pick one, and say in the code that it is a guess.

**`0x43e4` can never cause a stall.** It uses the fire-and-forget event path `0xD33CD8`, not the
request-status completion path `0x43e1` (slot 50) and `0x43e3` (slot 51) use. Nothing waits on it,
an all-zero push renders a flat graph, and no value it can carry changes control flow.

### `0x43f1` — 223 bytes, the match announcement

```
u32 hostCharaId   ; compared against [net+0x57D8] = the char id we send in 0x4101[0x000]
u32 ?
u8  ?
u8  ?
u32 ?
u32 ?
u8  rotationIdx
... 204-byte shared settings block, decoded by 0xD4364C
```

**The leading u32 is the host's character id.** Two independent investigations agree
(`0xD5B7DC`, `0x93DD60`, `0x907F14`, `0xD3A094`); a third read it as a game id compared against the
live game object and was wrong. If it names you, you go to state 12 and create the game. If it does
not, you park at state 18 and wait. Get it wrong and either nobody hosts or two clients do.

**Settled 2026-07-28: the block is 204 bytes.** An itemised trace of every read in
`0xD4364C..0xD43BF4` totals exactly 204 with **no gaps in the destination offsets**, which
independently confirms every field width. Three further checks agree: `19 + 204 = 223`, the parser's
own size; `obj+148 + 204 = obj+352`, where the trailing u8 lands; and the `0x4310` builder emits this
same block minus eight fields (22 bytes), giving `163 + 182 = 345` — the known `0x4310` size.
**`PROTOCOL.md`'s 159 is a stale figure and should be corrected.**

### The six scalars before the block

Identified by structural identity: `obj = 0xD3F7B0(net)` has five writers, and the four
non-automatch ones say what each slot holds.

| wire | size | meaning |
| --- | --- | --- |
| `0x00` | u32 | **host character id.** Compared at `0xD5B7F4` against `net+0x57D8`; never stored |
| `0x04` | u32 | **lobby id** (`lobbyObj+0x25C` in all four siblings) |
| `0x08` | u8 | **lobby subtype** — the same field as `0x4310[0xA2]` and `0x4316`'s u8 |
| `0x09` | u8 | subtype's sibling, `lobbyObj+0x261`. Meaning not established |
| `0x0A` | u32 | **zeroed by all four sibling writers.** Send 0 |
| `0x0E` | u32 | likewise. Send 0 |
| `0x12` | u8 | **rotation index** — which of the 16 rotation entries the match starts on |

**The rotation index has a silent fallback the server must respect.** At `0x93D3BC`–`0x93D414`, in
state 12 immediately before the create task, the client reads `rules[idx]`, `maps[idx]` and
`flags[idx]` out of the block — and **if `maps[idx] == 0` or `rules[idx] > 10` it discards the index
and uses entry 0.** So naming an index only works when that entry is populated with a nonzero map.

**`0x43f1` carries no game id, no timestamp and no player count.** Rule, map and flags live *inside*
the block, selected by the rotation index. The game id arrives separately in `0x43f2`.

### The block is the host's settings object, not a message (2026-07-28)

The tempting reading — that the client takes rule, map and flags out of the block and gets everything
else from its own stored settings — is **wrong**, and building on it would have shipped a match with
a zero-length round.

There is one **968-byte settings struct**. It lives at `screen+112` on the automatch screen and at
`net+0x8EF8` as the live game object; `0x4313`'s parser `memset`s 968 bytes there at `0xD44484`, and
`screen+112+968` is exactly the screen's host-id field. **The settings block sits at `+752` inside
it**, so the `memcpy(screen+864, obj+148, 204)` at `0x93D398` is dropping our block into the block
slot of the very struct about to be handed to the create task. `screen+864/880/896` are not three
fields lifted out of the block — they are `rules[0]`, `maps[0]`, `flags[0]` *inside the copy*.

The create task `0x8C9FA4` is only a spawner; its body `0x8CA0CC` calls the `0x4310` builder
`0xD446C8`, which **reads nothing but that struct** and performs **no numeric validation at all** —
only `strlen` and a charset check on name, comment and password. So zeros go out as zeros: max
players 0, briefing 0, every timer 0. The running game then reads those exact offsets through a bank
of ~70 getters at `0x907030`–`0x907A70`.

**Therefore: serve the same 204 bytes you would serve in a `0x4313` for that game.** Same structure,
same offsets, same reader (`0xD4364C`) — that is the whole shortcut.

Three rules that follow, each of which is a silent bug otherwise:

1. **Send rotation index 0 and put the elected rule/map at entry 0 yourself.** The client rewrites
   entry 0 from entry `idx` but does **not** clear entry `idx`, so any nonzero index makes that rule
   play twice per cycle.
2. **The rotation must be contiguous from index 0 with nonzero maps** — the blob-save loop at
   `0x8CA254` stops at the first zero map, and `rules[] > 10` triggers the entry-0 fallback.
3. **22 of the 204 bytes never reach the wire** (blocks 67, 76–79, 82–83, 88–91, 170–176, 184–187),
   because `0x4310` omits them. For the *host* they still land in the live game object via
   `memcpy(net+0x8EF8, S, 968)` at `0x8CAAC8`; for joiners they come only from our `0x4313`. Six are
   read by the getter bank, so author them the same in both or host and clients disagree.

Timer units, **inferred**: the post-create cache at `0x8CA470` multiplies eight of the seventeen u32s
by 60 and stores the other nine as bytes — so blocks 100–167 are eight `{minutes, count}` pairs plus
a lone value at 132.

### What an automatch game actually looked like (observed 2026-07-28)

From YouTube captures of real Konami-era automatch sessions. **Tier 2-3**: observed behaviour of the
retail service, not read from our artifacts, and only two rules have been seen.

| | |
| --- | --- |
| **Map** | random from a pool that **does not change**. One observed: Blood Bath |
| **Rules** | assembled from the **union of the searchers' requested rules** — e.g. a session with TDM, SNE and BASE requests ran a rotation of all three |
| **Common settings** | nothing special; no unusual toggles |
| **TDM** | round limit 4, round time 5 min, tickets 25 |
| **SNE** | round limit 4, round time 7 min, "kill Snake" 3 |

**Two consequences for the server, and the first is a correction.**

1. **The rotation is multi-entry, not a single elected rule.** The natural implementation — force the
   one elected rule into entry 0 and truncate — is wrong. Build one rotation entry per distinct rule
   the group asked for, still contiguous from index 0 and still with rotation index 0.
2. **The per-rule timers are fixed automatch values, not the host's.** Combined with the block being
   the host's settings object (above), this is the strongest argument yet that the original server
   authored the whole block rather than letting the elected host's saved settings through.

The TDM figures also **decoded the 68-byte timer block**, which had been one undecoded line in
`PROTOCOL.md`. See `dev/proto/blanks/inbound/mgo2_cmd_4310_c2s.ksy`: the ordering `SNE t/r, CAP t/r,
RES t/r, TDM t/r/tickets, DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r` was a tier-4 guess; it is now
corroborated by the client scaling exactly the eight *time* indices by 60 (`0x8CA470`) and by TDM's
observed 5/4/25 landing on indices 6, 7, 8 in order.

**Resolved the same day.** SNE's third figure is not in the array at all — it is the byte at
`0x4310` wire `0x14a` (block 189), which our docs labelled "sneaking Snake side". It reads 3 in every
stored blob, which is the client's default SNAKE setting. So all eight rules are `{time, rounds}`
here and TDM alone carries the third slot.

The ordering is now **confirmed, not inferred**: four stored blobs from characters who had never
edited a timer read `[0]=8 [1]=4` and `[6]=3 [7]=4 [8]=15`, matching the client's own defaults for
Sneaking (8/4) and Team Deathmatch (3/4/15) at exactly the predicted indices.

### The original server authored these values — proof

| | client default | observed in a real automatch game |
| --- | --- | --- |
| TDM | 3 / 4 / **15** | 5 / 4 / **25** |
| SNE | **8** / 4 / 3 | **7** / 4 / 3 |

Both differ from the defaults, so the automatch server set its own timers rather than letting any
host's saved settings through. **This retires the "maybe it just used the host's settings" reading
as an explanation of the retail behaviour** — it is now known not to be what Konami did, and the
fallback in `AutomatchSettingsBlock` is a stand-in with a known-wrong provenance rather than an
untested one.

Known real automatch values so far, **two of the six rules we serve**:

| rule | time | rounds | extra |
| --- | --- | --- | --- |
| TDM (1) | 5 | 4 | tickets 25 |
| SNE (4) | 7 | 4 | **SNAKE 3** |

SNE's SNAKE value is 3, which is *also* the client default — so it is written explicitly by the
server anyway. The bytes are identical either way; leaving it implicit would make an observed figure
indistinguishable from a placeholder, and regenerating the default block from a different capture
would silently drop it.

Still needed: DM, RES, CAP, BASE. Each is one observed automatch game of that rule.

### The decoded timer array, and the client's defaults

`0x4310` wire `0xFC`, block offset 100: **seventeen u32s**, eight rules. `PROTOCOL.md` carried this
as a single line reading "per-rule timers/rounds/tickets" until 2026-07-28.

| index | rule | field | client default |
| --- | --- | --- | --- |
| 0 / 1 | **SNE** (4) | time / rounds | 8 / 4 |
| 2 / 3 | **CAP** (3) | time / rounds | 4 / 4 |
| 4 / 5 | **RES** (2) | time / rounds | 4 / 4 |
| 6 / 7 / 8 | **TDM** (1) | time / rounds / tickets | 3 / 4 / 15 |
| 9 / 10 | **DM** (0) | time / tickets | 5 / 30 |
| 11 / 12 | **BASE** (5) | time / rounds | 5 / 4 |
| 13 / 14 | **BOMB** (6) | time / rounds | 30 / 4 |
| 15 / 16 | **TSNE** (7) | time / rounds | 10 / 4 |

Plus **SNAKE at block 189** (`0x4310` wire `0x14a`), default 3 — Sneaking's third on-screen setting,
which is not in this array. Times are minutes; the client multiplies exactly the eight time indices
by 60 at `0x8CA470`, which is what fixes the 2/2/2/3/2/2/2/2 shape.

Deathmatch is the one rule with no rounds slot.

### What the server sends today

`AutomatchSettingsBlock` starts from a captured **client-default block** and overrides only what has
been observed. Everything not in the observed table is a **placeholder that is known to be wrong** —
the retail service authored its own values, and we have two of the six rows.

The defaults are used rather than something invented because they are a real, fixed, self-consistent
table from the game itself; swapping in a real row is one line in `AUTOMATCH_TIMERS` per rule.

Also fixed by the server, and these parts are *not* placeholders:

| | value | why |
| --- | --- | --- |
| rotation | one entry per distinct requested rule, contiguous from 0 | observed |
| rotation index | 0 | client copies entry `idx` to 0 without clearing `idx` |
| `flags[]` | 0 | the only rule-option value legal for every rule |
| map | one of `{2,3,4,7,12}` | the disc's `map_bit`, and the five stage dirs |
| max players | 16 | client default |

### The map pool, and why the masks do not constrain us (2026-07-28)

The lobby stage script's `-rule_bit 191 -map_bit 4252 ×9 -ruleopt_bit 6 6 6 6 4 6 0` is consumed by
GCX native `0x8E0A64` (hash `0xAB3201`), which writes a single struct at **`0x166E944`**: `rule_bit`
at `+0`, `map_bit[rule]` at `+4`, `ruleopt_bit[rule]` at `+0x30`.

**Nine `map_bit` values because there are nine selectable rules.** `countSelectableRules`
(`0x8E0824`) walks 0–10 with hardcoded skips at 6 and 8, giving `{0,1,2,3,4,5,7,9,10}` — exactly the
nine unrolled store offsets. Rules 6 (BOMB) and 8 (COOP) have no slot at all, which is why they are
unreachable from the server regardless of any mask.

**`map_bit 4252` = bits 2, 3, 4, 7, 12 = the five stages on this disc.** Bit index is the map id
(the counter at `0x8E09AC` excludes bit 0; the name helpers bound `mapId-1 ≤ 14`). The ELF holds
exactly five stage-directory literals — `n002a`, `n003a`, `n004a`, `n007a`, `n012a` — and the disc
extract has exactly those five directories. Map 12 is capture-confirmed as Midtown Maelstrom.
**All nine rules carry the same mask**, so the pool is rule-independent.

That matches the observed behaviour above — *"random map from a pool that never changes"* — from a
completely different direction.

**The masks are create-game menu construction only.** The address `0x166E944` appears exactly once
in the 17 MB binary; all 21 dereferences live in `0x8E0824`–`0x8E2100`, and the complete caller list
of those eight accessors is inside `0x899000`–`0x8B6000` — the Create Game, rule-select, map-select
and rule-options screens. Nothing in the netcode, round setup, or the automatch screen consults them.
**So they will not refuse anything we author**, and they are evidence of intent rather than a
validator. We follow them anyway: rules `{0,1,2,3,4,5}` and maps `{2,3,4,7,12}`.

**`ruleopt_bit` is a whitelist of legal values for a per-rule option byte**, not a count: `0x8E0A2C`
tests `(ruleopt[rule] & value) != 0` and every one of its ten call sites passes a literal 2 or 4. So
rules 0,1,2,3,5 accept `{0,2}`, rule 4 (Sneaking) accepts `{0}` unless the Team Sneaking feature bit
is set, and rule 7 accepts `{0}`.

*Inferred:* the create form's rule byte sits at `+752` and its option byte at `+784` — the same
offsets as `rules[0]` and `flags[0]` in the settings struct — so **the rotation's `flags[]` is that
option byte**. Sending 0 is legal for every rule, and that is what we send.

### Two things outside the server's control

- **The game name is client-side, and it is the CHARACTER NAME.** `0x93D354` reads record 25 key
  140; the only writer, `0x947B94`, copies `session+0x57DC` — which the `0x4101` parser fills with the
  16-byte character name. So the name is never a stray short string and the player never types it.
  See [CLIENT_STORE.md](CLIENT_STORE.md) §4.
  <br>The real constraint is narrower: that record is **zeroed at boot and never persisted**, and only
  state 4 of the Create-Game settings screen (`0x946F00`) fills it — a screen the automatch menu item
  does **not** spawn. So a player who reaches automatching without passing through it this session
  has an empty name, and the create is refused with **error 3845**. Whether some lobby-entry step
  spawns that screen automatically is the open question; `0x890DCC` is the candidate caller.
- **Comment, password flag and password are never written on the automatch path** and come from the
  raw screen allocation. *Inferred* that the allocator zeroes them; if it does not, the first
  automatch `0x4310` we receive will carry a garbage comment or a spurious password flag. Cheap to
  confirm from a capture, and worth checking, because a password on a formed game would make every
  join fail — silently, again.

### The block's field map

Block offset *N* is `0x4313` wire `0xA8 + N`. Every `0x4313` name in `PROTOCOL.md` drops straight in,
and the three capture-proven `0x4310` anchors land where they should.

| block | size | meaning | `0x4310` wire |
| --- | --- | --- | --- |
| 0–47 | 48 | rotation: **rules[16] @0, maps[16] @16, flags[16] @32** — read as 16 interleaved triples | `0xA3` |
| 50 | 16 | weapon restrictions | `0xD5` |
| 66 / 67 | 1 / 1 | max players / **current player count** | `0xE5` / *omitted* |
| 68 | 4 | briefing time | `0xE6` |
| 94 / 95 / 96 | 1 / 1 / 4 | stance / level-limit tolerance / level-limit base | `0xF6` / `0xF7` / `0xF8` |
| 100–167 | 68 | per-rule timers, rounds, tickets | `0xFC` |
| 168 | 2 | unique characters red/blue | `0x140` |
| 177 / 178 | 1 / 1 | commonA / commonB | `0x142` / `0x143` |
| 180 / 182 | 2 / 2 | idle kick u16 / team-kill kick u16 | `0x145` / `0x147` |
| 188 / 189 | 1 / 1 | capture extra time / **sneaking SNAKE count** | `0x149` / `0x14A` |
| 190–203 | 14 | byte timers, extra-time flags | `0x14B` |

**One off-by-one to re-check, not resolved here:** `PROTOCOL.md` puts non-stat at `0x4310` wire
`0x155` bit 1; this arithmetic puts block 199 at wire `0x154`. One of the two is wrong.

### `0x43f2` — 4 bytes

`u32 gameId`, also stored at gameObj+144. Processing it **unregisters channel 60**, so it is a
one-shot: nothing after it reaches the screen.

---

## 4. The status block at `net+0x114A0`

37 bytes, cleared by `0xD5B41C` (`memset(net+0x114A0, 0, 37)`), which is itself called by the
session-wide reset `0xD35780`.

| off | written by | contents |
| --- | --- | --- |
| `+0x00` | `0x43e1` **result 0 only** | the **loaded** flag |
| `+0x01` | `0x43e1`, `0x43e4` | band |
| `+0x02` | `0x43e1`, `0x43e4` | players needed |
| `+0x03` | `0x43e4` | event-42 argument |
| `+0x04` | `0x43e4` | never read |
| `+0x05` | `0x43e4` | array A, 16 B |
| `+0x15` | `0x43e4` | array B, 16 B |

`+0x01..+0x24` **gate presentation only**; nothing branches on them. The loaded flag is different,
and it is the interesting one — `0xD5BDA0` is its only reader, and every use is **outside** the
automatch screen:

| VA | what it gates |
| --- | --- |
| `0xD43CA0` | forces **`0x4316`'s single u8 to 2** when set |
| `0xD44810` | same substitution for the byte at `+168` in `0x4310` |
| `0xD434FC` | clears the block after `0x4322` (join failed) |
| `0xD435E4` | clears the block on a nonzero `0x4311` result |
| `0xD44318` | clears the block on a nonzero `0x4317` result |

So the flag is a **mode bit**, and any failure in the create handshake tears it down.

**But it is NOT an automatch tag, and the earlier reading of it here was wrong** (corrected
2026-07-28). Both overridden bytes are the **lobby subtype**:

- `0x4310`'s is at **wire `0xA2` (162), not 168** — the 168 in `0xD44828` is a *client-structure*
  offset, and `0xD448FC` emits that same struct byte at wire `0xA2`, immediately before
  `ROTATION_OFFSET = 163`. Nothing lands inside rotation entry 1. The builder's full put sequence
  from `0xD446C8` sums to **345 bytes**, matching `PROTOCOL.md`, and hits every known anchor exactly.
- Three proofs it is genuinely the subtype: it shares slot `+0x294` with the hub menu's subtype
  (`0x88EDD4` and `0x890640` write the same field); the builder validates it against **{1, 2, 7, 8}**
  at `0xD44834`, which is exactly the set of subtypes a player can host in — Free Battle, Automatching,
  Basic and Combat Training, with Tournament/Survival/Official excluded; and `0xD4C250` dispatches on
  it through a 7-arm jump table for subtypes 3–9.
- **`0x4316`'s single u8 is the same field** (`0xD43C94` loads it from `lobbyObj+0x260`, `0xD43CB4`
  overrides). So is `0x4320`'s trailing u8.

**Consequence: there is no server-side signal that a create is automatch-originated.** In the
automatching lobby the subtype is already 2, so the override is redundant there and the byte tells us
only which lobby the game is being created in — which the connection already tells us. Accept
`{1, 2, 7, 8}` and do not infer anything from the value 2.

---

## 5. The rule filter, and why 11

State 4 sends the low byte of the selected row's u32 (`lbz r4,11(r11)`, `r11 = S+0x450 + idx*792 +
768`). Rows are built at `0x93B60C`–`0x93B828`:

| row | value | label | VA |
| --- | --- | --- | --- |
| 0 | **11** | string 925 **"Do not specify rules."** | `0x93B610` |
| 1–6 | 0,1,2,3,4,5 | rule names via `0x8E11E0` | `0x93B650`…`0x93B794` |
| 7 | 7 | Team Sneaking — **behind the feature bit** | `0x93B7F4` |

The rule-label mapper accepts 0–10, so **11 is deliberately out of range**: a sentinel for "no
preference", and the default selection, which is why live capture observed exactly that value.

Expect **{0,1,2,3,4,5,11}**, plus 7 only if Team Sneaking is ever enabled. Rule 6 (BOMB) has no row.

The disc corroborates the mask independently: `lobby/scenerio.gcl` `proc17` carries
`-rule_bit 191` = `0b1011_1111` — bits 0–5 and 7, BOMB clear. Same number, different artifact.

**Five Team Sneaking enforcement sites `GATES.md` §1 does not list**: `0x93B7D8` (drops the rule-7
row), `0x93B894` (swaps the panel art), and `0x93C9C4`/`0x93CB30`/`0x93CC30` (background resource
selection). All read `0x4101[0x12A]` bit 0. Release-day policy means the automatch list has **seven
rows, not eight** — and that falls out of the bit we already clear.

---

## 6. The failure table, resolved

Every automatch error dialog's OK button runs `0x93C1CC`, which unregisters channel 60, clears the
status block, and returns to state 1. **No automatch failure ejects the player from the lobby.**

| id | text | what the server did | VA |
| --- | --- | --- | --- |
| 4928 | Automatching is currently not available. | **DEAD STRING — no raise site exists** | — |
| 4929 | Automatching is currently not open. | `0x43e1` or `0x43e3` result **−970**, or `0x43f4` received at all | `0x93D224`, `0x93DE50` |
| 4930 | Unable to start automatching. | `0x43e1` result **−950**, or any nonzero not in {−541, −970}; or a local send failure | `0x93CF50`, `0x93CF70` |
| 4931 | network error / start | **no `0x43e1` within 6000 ticks** | `0x93CDD4` |
| 4932 | Unable to cancel automatching. | `0x43e3` result **−952**, or any nonzero not in {−953, −970} | `0x93D208`, `0x93D238` |
| 4933 | network error / cancel | **no `0x43e3` within 6000 ticks** | `0x93D178` |
| 4934 | Unable to find opponent. | `0x43e3` **result 0** *and* search timer > 180000 | `0x93D1D4` |
| 4944 | Unable to create game for automatching. | **DEAD STRING** | — |
| 4945 | The host was unable to create game… | `0x43f3` received, or `0x43f2` naming me as host after my create had failed | `0x93DE40` |
| 4946 | Unable to connect to game… | **DEAD STRING** | — |
| 3336 | You are currently banned from creating and joining games. | `0x43e1` result **−541** | `0x93CF38` |

`−953` on `0x43e3` is the one code that **parks the client silently** rather than erroring — which
is what you want when a cancel races a match push already in flight.

**4928, 4944 and 4946 are unreachable.** A sweep of every instruction in `0x10230..0xDE9328` for
those immediates found 4946 zero times, and every hit for the other two is a struct displacement in
graphics code. The failure *paths* they describe do exist — host create failure at `0x93D578`, join
failure at `0x93D52C` — but **both return to state 1 with no dialog of their own.** (Refined
2026-07-28: the create *coroutine* can still raise its own dialog before that. A name-length refusal
returns `-24` from the builder and `0x8CA178` routes it to **error 3845**, so that particular failure
is visible even though the automatch state machine says nothing. What is silent is the state
machine, not necessarily the whole path.) Same dead-string
mechanism as the five clan sentences in `ERRORS.md` arm 29.

### The three silent failures, which is what will actually cost debugging time

1. **`0x43f2` never sent** → every joiner parks at state 18 forever. No error, no timeout, no
   dialog.
2. **Host's create-game fails** → state 1, no dialog.
3. **Joiner's join fails** → state 1, no dialog.

Note also that an unanswered `0x43e0` does **not** produce the usual `FFFFFF60`. It produces
*"A network server error has occurred. Unable to start automatching."* If the generic form appears
on this screen instead, the fault is upstream of `0x43e0`.

---

## 7. Checklist — what the server must do

1. Answer `0x43e0` with `0x43e1` **result 0** within ~40 s. Only result 0 arms the feature.
2. Accept rule ids **0–5 and 11**; 7 only when Team Sneaking is on.
3. Use the result codes deliberately: −970 = "not open", −950 = "unable to start", −541 = "banned".
   **Every other nonzero value prints "Unable to start" with our number in it** — a wrong code is a
   wrong sentence, never a silent pass.
4. Do not push `0x43f*` before `0x43e1` result 0 has been delivered; the channel is not registered
   yet and the push is silently dropped.
5. Push `0x43e4` to drive the panel. Nothing else repaints it, and the client never asks.
6. Announce with `0x43f1` whose leading u32 is the **chosen host's character id**.
7. Send `0x43f2` with the game id *after* the host's `0x4310`+`0x4316` have landed — too early and
   the host quits with 4945.
8. ~~Accept `2` in `0x4316`'s u8 and at `0x4310+168` from an automatch host.~~ **Withdrawn
   2026-07-28.** Both bytes are the **lobby subtype**, at wire `0xA2`, and carry 2 in this lobby
   whether or not automatching is involved. Accept `{1, 2, 7, 8}` and infer nothing from the value.
   See §4 — this was the one signal the design hoped to use, and it does not exist.
9. Answer `0x43e2` with `0x43e3` result 0 within ~40 s. This is also the **only** way the player
   ever sees "Unable to find opponent" — 4934 fires on a *successful* cancel whose search had
   already expired.
10. Use −953 on `0x43e3` when a cancel arrives after a match was already assigned.
11. Serve the ordinary create/join handshakes afterwards — **no new work**, automatch reuses
    `0x4310`/`0x4316`/`0x4320`/`0x4322`/`0x4380` unchanged.

**Negative result worth keeping:** `0x4348`, `0x4394`, `0x43a4`, `0x43a6`, `0x43b0` and `0x43c4` are
**not reachable** from any automatch code. They are not part of this flow.

---

## 7a. What is implemented (2026-07-28)

**Step 2 of the build: honest refusal.** `0x43e0` and `0x43e2` moved out of `HubGameController` into
`AutomatchGameController` — they had to move rather than be duplicated, because
`GameServerHandler` throws at construction if two controllers claim one command id.

What changed on the wire:

- `0x43e0` is validated. The rule filter must be in **{0–5, 11}**; 6 (BOMB) and 7 (Team Sneaking)
  are refused with **−950** rather than queued under a rule no menu row can produce.
- Outside the availability window — and by default there is no window, so always — the reply is
  **−970**, four bytes, and the client prints *"Automatching is currently not open"*.
- `0x43e2` still answers an explicit four-byte zero.

**This is already an improvement over what it replaced.** The old handler answered result 0
unconditionally, which registers the client's push channel and commits us to speaking again; we then
never did, and the player got a twenty-minute stopwatch with no explanation. Refusing honestly is
worse than matchmaking and much better than that.

Operator policy lives in `AutomatchPolicy` and is read from the environment
(`MGO2SERVER_AUTOMATCH_*`, documented in `server.env`), **not** from a classpath JSON beside
`awards.json`: that file is baked into the shaded jar, so editing a window would need a rebuild
where an env change needs a restart, and its process-wide `static CURRENT` cannot express
"window open" in one test and "closed" in the next within one JVM.

`_MODE` selects the strategy — `BOTH`, `FORM_ONLY` or `SLOT_IN_ONLY`. `SLOT_IN_ONLY` refuses to
start without `_SLOT_IN_LOBBIES`, because this lobby only ever contains games automatching itself
formed and that mode never forms one.

**Step 4: the queue and the first push — confirmed live 2026-07-28.** A search for rule 0
(Deathmatch) enqueued, was answered `0x43e1` result 0 with `playersNeeded = 1`, and received a
36-byte `0x43e4` every five seconds. The client accepted every push silently, displayed "Players
Needed: 1", and **cancelled cleanly with no error** — the cancel path returns result 0 and the client
drops back to the menu, since its own search timer had not expired.

That run is the first server→client push this project has made: until now every byte the server sent
was a reply to something. It also settles, by observation rather than argument, that pushing to a
client that has been answered result 0 works at all.

**Step 5: matching — built, and partly confirmed live.** A two-client search formed a match, elected
a host, pushed a 223-byte `0x43f1` to both, saw the host create the game, and released both with
`0x43f2`. Server-side the flow is complete and its packet was verified byte by byte on the wire.

**But an automatch game hangs on the loading screen, and that is unresolved.** The `0x43f1` is
structurally correct — right size, right scalars, rotation entry 0 populated, sane timers — so the
suspicion has moved to the **22 block bytes `0x4310` cannot carry**. Our default block was derived
from a captured `0x4310` blob, which structurally cannot contain them, so all six of the offsets the
game's getter bank reads (67, 82, 88, 170, 172, 184) currently go out as **zero**. For the host those
bytes become the live game object verbatim. Block 67 is suspected to be a live player count; a game
created with zero players is a plausible way to hang a load. **Under investigation from the ELF**
rather than by copying a real `0x4313`, so that we learn what each field is rather than inheriting
values nobody can justify.

**Level matching, built to the operator's design.** Each searcher carries a window of their level
±band, where the band widens with *their own* wait, and two players match when the windows **touch**
— so a long-waiting searcher reaches out to a newcomer rather than both needing to fit one shared
range. The same band is sent to each client, so the lit range on the gauge is the literal truth about
that player's search rather than a decoration, and it widens visibly as they wait. The histogram's
two nibble arrays are filled from real per-level counts using the threshold table recovered from the
disc, so searchers appear in their own columns.

Defaults: start ±1, widen one level every 30 s, cap 22 — reaching "anyone" in about eleven minutes,
inside the client's own ~20-minute search timeout. `MGO2SERVER_AUTOMATCH_BAND_*` in `server.env`.

**Still unimplemented:** slot-in to existing games (`MODE=SLOT_IN_ONLY`/`BOTH`'s first pass),
`0x43f4` on window close, and `0x43f0`/`0x43f5`, which the automatch screen ignores anyway.

## 8. Release-day scope

Automatching's lobby subtype 2 is **already served** — it is in the deployed lobby list, and the
client can enter it today and get a screen that can never complete a search.

Whether to *implement* it is a release-day question this file cannot answer. The notice strings
prove Konami ran it **on a schedule** ("will be held from %s", "will finish shortly"), which is a
different shape from Free Battle being permanently open. Per `CLAUDE.md`, *shipped on the disc* and
*active on release day* are different questions and only the first is readable from our artifacts.
So the scheduling model is operator policy, and the honest default for a small server is that a
matchmaker needing several queued players of similar level will rarely fire at all.

The strings and the checklist above are complete either way.

---

## 9. UI strings, for reference

Set `[2f0293]`, group hash `0xf914bf` ("lobby"), ids 904–925 — one contiguous block bounded by 903
(Combat Training) and 926 (PERSONAL DATA).

| id | text |
| --- | --- |
| 904 | AUTO MATCHING LOBBY |
| 906 / 907 | Automatching / Start Automatching |
| 908 | Create a game automatically with other players who have selected "Automatching." |
| 909 | Automatically create a game with characters close to your level. |
| 910 | **Select the desired rules.** |
| 911 | Searching for opponents... Please wait until the required number of players are found. |
| 912 | Searching for joinable games in progress. Please be patient... |
| 913 | Searching for open games... |
| 914 | Automatching successful. The match will begin shortly.\n\nRules: %s |
| 915 / 924 / 923 | **Entry Status** / Matching / In Game |
| 916 / 917 | **Players Needed** / %d |
| 918 / 919 | Search Time / %d:%d |
| 920 / 921 | SEARCH AREA / Not specified |
| 922 | Desired Rules: %s |
| 925 | **Do not specify rules.** |

`SEARCH AREA` is display-only: a full search of all 28 693 lobby resources found **no region value
vocabulary anywhere on the disc**. Nothing about team size, map, player count or skill is settable
— "Players Needed" is a readout, not an input.

Three search messages (911, 912, 913) suggest three distinct search phases — forming a new game,
joining a running one, joining a not-yet-started one. *Inferred from wording, not proved.*

---

## 10. Reading disc string resources

Method established while doing this, and reusable — it is how `LOBBIES.md`'s string ids stopped
being inherited guesses.

`gcx.exe -res` dumps every resource-table entry into a flat `N.bin` numbering. The low entries are
**header records**, not strings. `proc16` of the `.gcl` declares the sets:

```
-set [40eff4]  $strres:0      $strres:341     # rule/map name master list
-set [2f0293]  $strres:9789   $strres:11033   # the online lobby UI
-set [3d915]   $strres:21368  $strres:21898   # errors + server notices
-set [e60831]  $strres:17779  $strres:17942   # personal stats
```

Strings start at `lastHeaderIdx + 1`, and **`string id` (what the ELF uses) = `headerIndex −
setFirstHeaderIdx`**.

Header record, terminated by `0x00`: lead byte `>= 0x80` is an immediate of `b − 0xC1`; `0x02` + 1
byte u8; `0x01` + 2 bytes LE u16; `0x06` + 3 bytes LE u24; `0x0d` + 4 bytes LE u32. Fields in order:
`groupHash`, `resourceNameHash`, then six 1-based string ordinals — **JP, EN, FR, DE, IT, ES**.
File index = `stringBase + ordinal − 1`. Identical strings are shared, so a record can point outside
its own run.

The 24-bit name hash: `h = 0; for c in name: h = ((h<<5 | h>>19) + c) & 0xFFFFFF`. Validated against
`dev/tools/gcx/dictionary.txt` — `0xf914bf` = `"lobby"`, `0x4348fb` = `"MGO_ERROR_RES_LOBBY"`,
`0x4ccd4d` = `"MGO_ERROR_RES_GMINFO"`, `0x1ab3b6` = `"mgo2_res_myscore"` (the sub-group hash
`ASSETS.md` already records for Personal Stats).

**The ELF addresses these resources by numeric string id, not by hash.** None of the 35 automatch
name hashes appears in the binary, and the ASCII `Automatching` does not occur in it at all. Search
the ELF for the **small integers 904–925**, not for hashes. Name hashes are stable across stages
(`nttitle` carries the same resources under the same hashes at a different base), which makes them
safe identifiers *within the disc*.

This also names three lobby subtypes `LOBBIES.md` left unnamed: **3 = Tournament, 4 = Survival,
5 = Official Tournament** (its title string reads "OFFICIAL CUP LOBBY").

---

## 11. Undetermined

- **Which nibble array is "Matching" and which is "In Game".** The client only displays the sum, so
  no client behaviour can distinguish them. Unknowable from this side.
- **What `0x43f0` (event 43) is for.** Its parser fills the settings block and two 8-element arrays,
  but the automatch screen's dispatcher explicitly does nothing with event 43 (`0x93DE5C`).
- **Where event 55 (`0x43f5`) is handled.** Not on channel 60, not in this screen.
- **Byte `+0x04` of the status block**, and the four tail bytes of each nibble array. Written, never
  read.
- **The wire meaning of `0x43f1`'s fields between the host id and the settings block.**
- **The 150 units/s calibration**, which is anchored on a tier-2 observation. If the ~40 s figure is
  loose, the 20-minute search window moves with it.
