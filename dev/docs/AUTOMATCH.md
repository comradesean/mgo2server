# Automatching

Everything the client needs to complete an automatch connection, read from `MGO2.elf` and the disc
on 2026-07-28 by four parallel investigations. Three names in `PROTOCOL.md`/`PACKETS.md` were wrong
and are corrected here. **Implementation status is in §7a** — currently: the two client→server
commands are validated and refused outside a configured window; none of the four pushes exist yet.

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

**The level table is not in the binary and cannot be extracted from it** (investigated 2026-07-28).
`0x6F9260` walks a 128-entry u32 array in `.bss` at `0x1659D24` — pointer at `0xFDE280`, zero at
load — filled at runtime by the GCX native `0x6F9370` (option letter `-r`) from a stage script. It
sits `0x200` bytes below the `ComputeScore` table `ADDRESSES.md` already records as script-fed: same
allocation, same lifecycle. Getting the numbers means extracting the script per `ASSETS.md`, or
bisecting experience against the rendered level on a live client.

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

The 204-byte block is the same one the lobby and game-list parsers use — `0xD4364C` has 9 callers.
Note that `PROTOCOL.md` calls this block **159 bytes** (under `0x4905`, and used by `0x4313`); an
itemised trace of every read in `0xD4364C..0xD43BF4` totals **204**, corroborated by two
`memcpy(…, 204)` sites at `0x93D398` and `0xD5B810`. **Unresolved, and out of scope here** — our
`0x4313` parser is `0xD44388`, so the relationship needs checking before anyone edits anything. If
159 is wrong then `0x4905`'s documented 822 bytes is wrong too.

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

So the flag is a **mode bit**: it tags the create-game handshake as automatch-originated, and any
failure in that handshake tears it down. `PROTOCOL.md` records `0x4316`'s u8 as a byte "we do not
read at all" — **its meaning is "this game is being created for automatching"**, and our handler
must accept `2` there.

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
failure at `0x93D52C` — but **both return to state 1 with no dialog at all.** Same dead-string
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
8. Accept `2` in `0x4316`'s u8 and at `0x4310+168` from an automatch host.
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

Still unimplemented: the queue, the scheduler, and all four pushes.

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
- **Whether the 204-byte reading of `0xD4364C` or `PROTOCOL.md`'s 159 is right** (§3).
- **The 150 units/s calibration**, which is anchored on a tier-2 observation. If the ~40 s figure is
  loose, the 20-minute search window moves with it.
