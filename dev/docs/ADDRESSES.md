# Address index: where the important findings live in `MGO2.elf`

Every load-bearing conclusion in this project is anchored to an address in the decrypted binary.
Those anchors are the expensive part — a fact can be re-derived from a capture in an evening, but
finding the function again costs a full disassembly pass. This page is the index.

**Binary:** `dev/ref/MGO2 (decrypted).elf` — ELF64, **PowerPC 64, big-endian**.
File offset = VA − `0x10000`. Text section spans roughly `0x10230`..`0xDE9328`.

**Reading it.** `powerpc64-linux-gnu-objdump -D -b elf64-powerpc` is on PATH, and `capstone` 5.0.6
is installed (`CS_ARCH_PPC`, `CS_MODE_64 | CS_MODE_BIG_ENDIAN`). `dev/tools/analyze_mgo2.py` has ELF
section parsing and a PPC decoder already written. **Per CLAUDE.md, disassembly work goes to an
Opus sub-agent — never inline.**

**Two PPC64 details that trip people up here.** A "function pointer" is an OPD descriptor
(`{entry, toc}`), not the entry itself — the OPD section is at `0xFFEC90`, so a search for a raw
function address often finds only its descriptor. And the binary carries almost no symbols: 24
`Class::method` strings in total, so naming comes from string references, call graphs and
cross-references, not from a symbol table.

**Tier tags** follow CLAUDE.md's vocabulary. Everything below is read from the binary unless a row
says otherwise.

**Spot-checked 2026-07-28**, so this is not an index taken on trust. Reading the medal table at
`0xE139C0` yields `{1, 001f6b14, 5}`, `{2, …, 10}`, `{3, …, 25}` — the consecutive-kills tiers —
then `{10/11/12, 004a0761, 3/10/30}` for consecutive headshots, terminated by `0xFFFFFFFF` at
`0xE13B94`. The DETAIL display list at `0xE13BDC` is byte-identical to its duplicate at `0xE13C6C`.
All the strings cited below (`Rule_Eng_TSNE`, `MK2_SKILL`, `icon_HSonly`, `MK2 SPARK`, …) are
present. A one-liner to re-check any of it:

```python
import struct; data = open("dev/ref/MGO2 (decrypted).elf","rb").read()
struct.unpack_from(">12I", data, VA - 0x10000)      # file offset = VA - 0x10000
```

---

## The client's record store

A 26-record in-memory property store. Full write-up in [CLIENT_STORE.md](CLIENT_STORE.md); the
entry points are `0x27EF90` (RecordBuffer), `0x27F160` (RecordGet), `0x27F258` (RecordSet) and the
descriptor table at `0x103BC18`.

**Records 1-24 are the per-slot player stat blobs** already documented in section 1 below, reached
through this API rather than being a separate structure. Record 25 is the local player's own
settings, and its key 140 is the hosted-game name at the fixed address `0x161822C` — the value
automatching's elected host puts in `0x4310`, and the reason a host can silently fail to create.


## 1. The round report — `0x4390`

| VA | what it is |
| --- | --- |
| `0xD42178` | **the serializer.** Fully unrolled, 58 identical `lwz`/`sth`/put triples, no logic. One `bl` xref in the whole text section |
| `0x27D5B0` | **its only caller, and where every semantic decision lives.** Computes struct A and struct B from the player's stat blob. Installed as a handler via OPD `0x1008ED0`, dispatch table `0xFB1C20` |
| `0x27D480` | blob reset/seed — zeroes live *and* baseline |
| `0xD5C8A0` / `0xD5C8D4` / `0xD5C9BC` | `put_u8` / `put_u16` / `put_u32`, big-endian into `buf+0x40` |
| `0xD5CF40` / `0xD5C828` / `0xD34CC0` | set command id / finalize / send |
| `0xD42400`–`0xD42408` | the short-form branch (NULL struct-B pointer). **Unreachable from the only caller**, which always passes a stack address |
| `0x27DC44` | `li r7, 0` — the sole source of the trailing word. That one instruction closed the field |
| `0x27DC60`–`0x27DC70` | the rebaseline: `SET(key 0xb2, 152, live)` immediately after the send |
| `0x27DA5C` → `0x27DA90` | b24's raw path — `lhz` then `stw` with **no `subf`**, the one slot that is not a delta |
| `0x27D6D4` / `0x27DCD8` | the b00/b01 store-if-greater, branch-selected on bit 0 of blob key `0x159` |
| `0x27DBCC` | `flag_0x04` computed live as `playerIdx == g_snakeIdx` — which is why it reads 0 on teardown reports |
| `0x26DE10`, `0x27D80C`..`0x27D828` | elapsed ms, then `mulhwu 0x10624DD3` + `srwi 6` to get `seconds_in_game` |

### The stat blob

| VA / formula | what it is |
| --- | --- |
| `0x27EF90` | returns the per-player record object for `slot + 1` |
| `0x27F160` / `0x27F258` | the record `GET` / `SET`. **The "key" IS the byte offset into the blob** (`add r4, r7, r4` at `0x27F244`) |
| `0x103BC34 + i*0x1c` | the 24 per-player descriptor sets |
| `0x103C0C6` | the descriptor array, 115 entries. Rows 4..79 declare live halfword `n` as an addressable u16 at key `0x1a + 2n` |
| **`0x1610568 + slot*0x510 + 0x1a + 2n`** | **live counter `n` for a player slot** — a link-time constant, so this is a usable RPCS3 write watchpoint |
| `+ 0xb2 + 2n` | the baseline shadow of the same counter |

---

## 1a. Skill experience — `0x43a4`

The only route by which skill progression persists. Skills level by *use*, which the server cannot
observe, so the client reports. Identified 2026-07-29 and confirmed live the same day.

| address | what |
| --- | --- |
| `0xD41940` | serializer, `f(ctx, u32 charaId, void *entries, u32 count)`. `li r4,0x43A4` at `0xD419DC`; count cap 127 at `0xD419BC`; **opens wait slot 53 at `0xD41A78`**, so an unanswered report hangs the client |
| `0x27D028` | **its only caller** (`bl` at `0xD41168`), and where the records are built |
| `0x27D0D0` / `0x27D0E8` | `GET(key 392, 256)` live experience and `GET(key 648, 256)` its baseline shadow — 128 x u16 indexed by skill id |
| `0x27D12C` → `0x27D140` | writes the delta, then **overwrites it with `live[id]`**. This is why the reported value is ABSOLUTE, and the single instruction that settles it |
| `0x27D130` | zero delta ⇒ cursor does not advance, so unchanged skills are omitted |
| `0x27D190` | rebaseline, `SET(key 648, 256, live)` — same pattern as `0x4390`'s at `0x27DC60` |
| `0x27DF38` | `SubmitReport(slot, which)`; `which == 1` arms `0x43A4` (arm at `0x27DFC0`) |
| `0x27E780` | `PollReportTasks(slot)` — drives the three tasks **in order**: `0x4390`, `0x43A4`, `0x43A2`. Confirmed live, all three in the same millisecond |
| `0x7083C8`, `0x708800` | the two arming sites; each sweeps slots 0..23, so **the host reports for every player** and attribution must come from the payload's character id |
| `0x6FCA40` | `addi r6,r6,1` — accrual, **one point per use** |
| `0x6FCAD4` | level-up snap to `(level << 13) + 8192`, requirement table at `g + (min(id,17)*4 + level)*2` |
| `0x6FC580` | level = `min(experience >> 13, 3)` |
| `0x93E418` | **`cmpwi cr7,r0,24576; ble+` — zeroes any record above 24576.** A legal maximum, not a display ceiling: over-cap makes the skill vanish |
| `0x8841A8` | announce builder — copies `profile+11444` (stride 12, u32 at +4) to `announce+50` |
| `0x2764E0`, `0x278230` | announce receivers — `SET` that block into **both** key 392 and key 648, so the delta starts at zero on join |

`profile+11444` is written only by the `0x4125` and `0x4129` parsers, so it is entirely
server-authoritative — which is why nothing persisted before: experience accrued in the blob and
was discarded at teardown.

## 1b. The host-rating gate — `0x43c4`

| address | what |
| --- | --- |
| `0xD40E2C` | the vote sender; range guard `cmplwi cr6, arg-1, 4` at `0xD40E44`, `li r4,0x43C4` at `0xD40EA4` |
| `0xA322A8`, `0xA3310C`, `0xA33F70` | its three call sites, in three identical coroutine copies |
| `0x9DCA18` / `0xA135AC` | picker predicate 1 — `0x26E958` must be 0, i.e. **not the host** (bit 0 of `gameObj+3020`). How self-rating is prevented |
| `0x9DCA34` / `0xA135C4` | picker predicate 2 — `screen+344` must be nonzero, or the picker never opens |
| `0x9D7F34`, `0x9DF0B4`, `0x9DFA84`, `0xA0C5D8`, `0xA0F6F8`, `0xA0FEC0` | the six sites that **snapshot** `details+964` into `screen+344` when the end-of-game screen is constructed |
| `0xD44588` | writer 1 of `details+964` — the `0x4313` parser, wire `0x0a7` |
| **`0xD441FC`** | **writer 2 — the `0x4321` join-result parser, wire `0x28`, only when `result == 0`. Lands last and wins.** We sent a hardcoded 0 here, which switched host rating off on every join |
| `0xD44D00` | writer 3 — the `0x4310` create-game sender, a provable zero: the host suppressing its own |
| `0xA31DB0` | where the slot is finally re-read — **after** the player has already chosen a rating, which is why fixing only `0x4313` changed nothing |
| `0xA322BC`, `0xA31DC0` | the post-send latches (`flags |= 0x20`, zero `state+200`). **Client-local and cleared when the picker is re-armed**, so only the server can stop a repeat vote |

Details cache base is `session+0x8EF8` (36600), proven at `0xD3F71C`; `36600 + 964 = 37564`, which
is the `lbz r0,-27972(r9)` after `addis r9,r3,1` seen at each snapshot site.

## 2. Gameplay counter writers

| VA | what it is |
| --- | --- |
| **`0x6A9758`** | **the bump wrapper every counter goes through** — `SET(base, key, len, u16)`. The key is a constant one frame *up*, at the `bl` site, which is why constant-key sweeps of the record API found nothing. 152 call sites |
| `0x6A95A0` / `0x6A9698` | blob base / `blob + 0x1a` helpers used alongside it |
| `0x6A9AC8` / `0x6A9790` / `0x6A9560` | sibling wrappers — they target object 0, object `0x19`, and nothing. **Not** player blobs |
| **`0x6ED650`** | the **host-only player-event dispatcher**, `f(eventId, playerSlot)`. 15 events, 32 callers, jump table `0x6ED6E0`, **shared increment tail `0x6ED760`** |
| `0x6EFF98` | a second shared tail, in the CQC handler, carrying keys `0x5c`/`0x62`/`0x64`/`0xa0` |
| `0x6EDC90` | the stun/knockout handler. Switches on a `hitClass` argument: `==1` writes the stun-headshot pair, `==2` writes the lock-on stun pair |
| `0x6EEAF0` | the kill handler. Same enum in the same argument position — `==1` headshot, `==2` lock-on. Four confirmed labels pin the enum |
| `0x6EF620` | b02's own streak store, from blob key `0x15c` (b00/b01 use `0x15a`) |
| `0x6ED088` | the melee/spot handler; branches to the TSNE arm on `cmpwi 7` |
| `0x6FB8A0` / `0x70F460` | TSNE spot writer / Snake spot writer — the same HUD byte, different mode |
| `0x706A10` / `0x706BB8` / `0x706FB8`, `0x708410` | Rescue+TSNE objective methods: goal reached / picked up / carry accumulators. Each has a `cmpwi 2` Rescue arm beside a `cmpwi 7` TSNE arm |
| `0x6A9A38` | returns the current round's mode id |

> **Both shared tails caused wrong readings.** A trace that concludes "X or Y, never both" should be
> checked live by producing exactly one triggering event and seeing whether both counters move — that
> is what refuted the b41/b29 partition. See OBSERVED.md.

---

## 3. Scoring

| VA | what it is |
| --- | --- |
| **`0x6FA408`** | **`ComputeScore(rule, playerSlot)`** — walks a 37-column × 11-row `s8` table |
| `0x6FA448` | `mulli r25, r3, 37` — the row stride, i.e. the table's shape |
| `0x6FA4C4` | the column jump table: column index → which live counter it reads |
| `*(0xFDE2AC)` = `0x1659F24` | the table itself, in **`.bss`** — not static in the ELF |
| `0x6FA1B8` | the GCX native that fills it, hash `0x0035706D`, registered at `0x10310F4`, OPD `0x1014D40`. Values come from `-rule N -score <37 ints>` in the stage scripts |
| `0x71B470`, `0x71B510`..`0x71B534` | `clamp(raw, 0, 65535)` before the single store into live n03 — the only write to the score field in the binary |
| `0x6EEE4C` | column 9's raw value is the step size for the combo counter |

---

## 4. Sneaking, Snake and the Mk.II

| VA | what it is |
| --- | --- |
| `0x71C7FC` | **the Mk.II player-count gate**, `cmpwi cr7,r28,11` / `ble`. Same literal at `0x71C6CC` in the request handler (refusal writes status `0xFF`) |
| `0x71CA84` | the Snake role's gate in the same function — `cmpwi cr7,r28,1`. Same counter, different literal, which is what makes the comparison meaningful |
| `0x71CBD8`..`0x71CBF8` | the LCG that picks which player becomes the Mk.II (`seed*0x5D588B65 + 1`), mixed with elapsed time |
| `0x71CA0C` | forces the holder to **team 2** — Snake's side |
| `0x6FC254` | the kill-credit path's team test, which is what ties that role to `snake_kills`/`mk2_kills`. **Its enclosing hook `0x6FC228` is NOT Sneaking-only** — it is vtable slot 7 of the rule-3 and rule-5 classes and is called directly from `0x717594`, `0x719310`, `0x7198E4` and `0x71A27C`, i.e. shared by rules 0, 1/6, 2, 3, 4 and 5 |
| `0x7031A4` | **the mode-object factory** — `switch (0x6A9A38())`, 11 cases, jump table at `0x7031D0`. Case 4 (Sneaking) is ctor `0x719B90`, vtable `0xFB5378`. Rule 4 alone also gets a 232-byte object from ctor `0x70F198` at `0x703188` |
| `0x719D40` | **the Sneaking round-end handler** (vtable slot 4 of the rule-4 class), called as `mode->slot4(mode, &reason, &out)` from `0x704FBC` / `0x70773C`. Reasons 2/3 award; **reasons 4/5 — the Snake-axis outcomes — award nothing** |
| `0x6FC140` | `AwardTeamWin(unused, teamId)` — walks slots 0..23 and saturating-increments live counter n15 (blob key 56) for every occupied slot on that team. All 20 call sites are host-guarded by `0x26E958`. The **only** writer of `team_win` |
| `0x6FAEB8` | **Team Sneaking's round-end handler, and the control that proves the omission is deliberate** — same shape as `0x719D40`, but its reason-4 arm *does* call `AwardTeamWin(2)` at `0x6FAFE4` |
| `0x6EB9B0` | returns the Mk.II's slot, or none |
| `0xE1B808` / `0xE1B7F8` | `MK2_SKILL` / `SNAKE_SKILL` — the only two unique-character skill names the ELF references |
| `0x1036BCC` | `MK2 SPARK`, damage-source id `0x72` — the taser, which is what b57 counts |
| `0x1035818` | **the damage-source name table.** Independently re-confirms b17 and b18 |

---

## 5. Headshots-Only and the round flags

| VA | what it is |
| --- | --- |
| `0x6A9948` | reads the third byte of the `[rule, map, flags]` round triple. Only bits `0x2` and `0x4` are ever tested binary-wide |
| `0x778610`–`0x77861C` | the `roundFlags & 0x4` gate |
| `0x77864C` → `0x76C1D0` → `0x76C27C` | the chain that arms the penalty by setting bit 63 of `[chara+0x368]` |
| `0x77B0DC` / `0x77B0E0` | **`li r4,191` — the only entry into player state 191** anywhere in the binary |
| `0x778380` | the death-cause classifier. Raises event 6 on damage-cause 141, event 7 on 65/67, and event 8 (b38) on `player->[0x90] == 191` at `0x7787DC` |
| `0x778D0C` / `0x778D20` | `kill(slot, slot, 0, 0)` then `bl 0x6ED650` with `li r3,8` — the self-kill that b38 counts |
| `0xFE7084/88/8C` | **the labelled lobby menu table** — `obj_4_select_others`, `icon_drebin_point`, `icon_HSonly`. This is what named the flag |
| `0x8AD6B4`..`0x8AD838` | the menu rows, label ordinals 400/402/403, tooltips 409/411/412 |
| `0x8CA2BC`..`0x8CA420` | the `S+0x3A0` bitfield expanded into the `0x4310` settings word — a *different* field from the round flags |
| `0x8CA5E8` | the 48-byte rotation array `SET`, key `0x11` |
| `0x8AA35C` / `0x8AE2A4` / `0x8ADDC8` | the three setters writing flags 2 / 4 / 0 |

---

## 6. Rule selection and feature gates

| VA | what it is |
| --- | --- |
| **`0xD382F8`** | **`featureBit(ctx, n)`** = `(ctx[0x117D0 + n/8] >> (n & 7)) & 1`. Rejects any bit above 5 — six feature flags in one byte |
| `0xD3C120` / `0xD3C348` | the `0x4101` parser, and the **only writer** of `ctx+0x117D0`. Puts the feature byte at payload offset `0x12A` |
| `0x8AFD84` | the create-game menu builder's rule-7 special case: `cmpwi r9,7` → `bl 0xd382f8` → skip the row if the bit is clear |
| `0x8996DC`, `0x89ADB8`, `0x8AD794`, `0x8ADC78` | four further enforcement sites — which is what makes it a real feature flag rather than menu cosmetics |
| `0x8E0A64` | loads the `rule_bit` mask from the lobby stage script, GCX hash `0xAB3201`, OPD `0x101B740` |
| `0x8E0824` | `countSelectableRules()` — returns **7**, because the script's mask is `191` |
| `0x9C2778` / `0x9C2864` | the rule-name function and its jump table: `Rule_Eng_DM`/`_TDM`/`_RESCUE`/`_CAP`/`_SNEAK`/`_BASE`/`_TSNE`/`_COOP`. This is what gave 2 = Rescue and 7 = Team Sneaking by name |
| `0x1030FE0`..`0x1031748` | **the GCX native-command registry** — 237 `{u32 nameHash, u32 opdPtr}` pairs, sorted. TOC anchor at `0xFBC794` |

---

## 7. The stats screens

| VA | what it is |
| --- | --- |
| `0xD3E9AC` / `0xD3E53C` / `0xD3DB1C` | the `0x4103` / `0x4105` / `0x4107` parsers |
| `0xD3E4B0` | completes wait slot `0x16` — why `0x4107` must be sent **last** |
| `0xD3E5E4` | the `0x4105` page gate; anything above 1 bails with `-0x47` and discards the matrix |
| `0xD3E314`, `0xD3E32C`, `0xD3E348` | the `0x4107` tail permutation: wire 64 → mem 71, 65 → mem 72, 66..73 → mem 63..70 |
| `0xE13BDC`, duplicated at `0xE13C6C` | **the DETAIL page display list** — 36 u32 resource hashes, in display order |
| `0xE139C0`..`0xE13B90` | **the medal/award threshold table** — 39 rows of `{u32 id, u32 nameHash, u32 threshold}`, `0xFFFFFFFF` terminated |
| `0xE14EB0` / `0xE152D0` | the title strings — **66 of them, 22 titles × 3 forms** — and the **title** sprite table. Medals have no sprite |
| `0x916E20` | **the medal gate.** Reads the row id, tests the bitfield bit, skips the row if clear. No stat is loaded in `0x916E20`..`0x916FD0`, which is what proves medals are server-driven |
| `0xD5C2A8` | the bit test the gate calls — medal-id-keyed, LSB-first |
| `0x94258C` | the star gauge: `clamp(ceil(2 · numerator / denominator), 0, 10)` half-stars, 11-entry icon table |
| `0xD40E44` | rejects any `0x43c4` host-rating vote outside 1..5 |
| `0xD25D0` | the 24-bit rotate-5-add string hash used for resource names |
| `0x942564` | the 9,999,999 display clamp |
| `0xD3F3A4` / `0xD3F3C0` / `0xD3F3DC` | the medal bitmask and survival fields parsed out of `0x4103`. **The tension is resolved (2026-07-28): medals really are server-driven** and "client-computed" was the wrong reading — see `GATES.md` §5a |
| `0x91B338` | the stats screen reading rating-block entry 4 |

---

## 8. Elsewhere, still load-bearing

| VA | what it is |
| --- | --- |
| `0xD3FEAC` | the sole writer of the round token at session `+0x32F8` — half of the proof that `0x4390` attribution is connection-implicit |
| `0xD47E18` | the `0x4902` lobby-list entry parser (99-byte entries) |
| `0x905A7C` / `0x905A94` | the clan emblem gate on the **lobby-entry** path — byte must equal 3 **and** membership state in `{1,2}`. Its timeout at `0x905B00` (tick counter past 6000) raises the client-side `-160` *"network server error … unable to acquire clan emblem"*; results `-1215`/`-1214` are explicitly tolerated at `0x905B80` |
| `0x9C2C00` | the **in-game** emblem gate, and it is not the same test: `slot+92 == 3` passes unconditionally, `slot+92 == 2` also passes when the mode is 9, and mode 10 always fails |
| `0x9D4500` | the per-frame **emblem manager** — walks all 24 slots and fetches **each peer's** emblem by that peer's clan id. 30-entry cache at `0x166F8F4`, stride 776. Backoff on failure at `0x9D4A34`, 6000 ticks, no dialog |
| `0xA9B3E8` | **the emblem decoder** — `"EMBD"` magic (`0xE1E6A8`, compared at `0xA9B458`), high-bit byte at +4 (`0xA9B470`), 16 RGB palette entries at +5, 512 bytes of packed 4-bit indices at +53 (`0xA9B718`), width asserted 32 at `0xA9B744`. **32x32, 16 colours** |
| `0xD56618` / `0xD56704` / `0xD57838` | the three emblem-fetch senders (`0x4b4c` / `0x4b4a` / `0x4b48`). **All three append a u32 clan id**; `0x9D47C0` picks `0x4b4c` over `0x4b4a` when the mode is 9 |
| `0x88407C` | the **player-announce builder** — copies `profile+6872` verbatim to announce `+4` at `0x88415C`, clan id to `+8` (zeroed unless membership−1 ≤ 1), clan name to `+330`. Serialized to peers at `0x272474`–`0x272684`, applied to the slot by `0x2762A0` (own) / `0x278068` (peers); slot array `gameObj+212`, stride 116, 24 slots |
| `0xD3C9A8` | the **`0x4129` parser** (dispatch `0xD387C8`, `cmpwi 16681` at `0xD388B4`). Writes 13 profile fields at `r27+22488` and clears none — including the emblem flag at `0xD3CC0C`, the **last byte of the payload**. A non-zero `result` skips the whole body |
| `0xD584B0` / `0xAD4724` / `0xD3DA90` | the other writers of the emblem flag: `0x4b47`, the upload commit, and `0x4221` (the last against the *viewed player's* record, not the local profile) |
| `0xAB0074` | the clan coroutine that ands the privilege word and refuses to advance unless it is zero |
| `0xBC2D78` | the ranking scramble |
| `0x305A60` | a per-object 896-bit flag API |
| `0x6FC760` | the objective notifier, `f(id, slot)` |
| `0xDDEE30` | the Scanning skill's S. PLUG item |
| `0x906BE8`–`0x906E10` | the **list-preference nibble accessors** — one getter and setter per 4-bit field of `0x4120`'s trailer. Screens: FILTERING SETTING `0x9084BC`, SORT HOST LIST `0x90C010`, PLAYER SEARCH `0x90E264` |
| `0xE0D548`–`0xE0DBF0` | a **developer name table**, English, naming those screens and fields (`FILTER HOST LIST`, `SORT KEY`, `MATCH CASE`, `PASSWORD LOCK`, …). Better field-naming material than the player-facing disc labels, and worth trying for other subsystems |
| `0x9B9DF0` | the **preset-message (codec) availability predicate** — *not* loadout, corrected 2026-07-29. Walks the catalogue at `0xE1812C` and gates each phrase against `(0x3049 trailer[3] & 1) << 4`. 17 call sites binary-wide, all in `0x9A50D0` (shortcut binding) and `0xA459D0`; **no loadout code calls it** |
| `0x927350` | **the gear ownership gate — gear IS server-controlled**, corrected 2026-07-30. `lbz r8,8(r9)` off `charTable + 9888 + itemId*12`, the byte `0x4124` wrote; zero at `0x92746C` means the item is never appended to the wardrobe list. Five ids are exempt at `0x92735C`-`0x927384` (28, 68, 86, 46, 102 — the "None" entries). No predicate function is involved, which is why a search for one found nothing |
| `0x925538`, `0x92772C` | **the per-item colour gate.** `lwz r0,12(r9)` — the u32 colour mask from `0x4124` — tested `and` against `1 << colourIndex`. Both read; the mask is live |
| `0x9270AC` | the wardrobe's 9-arm category table: `{base id, count, equipped-byte offset, name string-group hash}`. **67 reachable ids, max 116** — head 28-38, upper 11-13, lower 22, chest 68-80, waist 86-97, hands 46-51, feet 57-62, accessories 102-116 |
| `0xE1812C` | the **preset radio-message catalogue**. 6-byte records `{u16 first_string_id, u16 phrase_id, u16 gate}`, loop bound 85 (`(512-2)/6`), **82 populated** — slot 82 is `0xFFFF`, 83..84 padding. Gates: 23 at `0` (always), **32 at `16` — the day-one paid MGO Codec Pack, matched 32/32 to the product list in order**, 27 at `0x80` (Combat Training instructor commands). Phrase text is disc set `[7a133b]`, 19 strings per phrase (9 male / 9 female / 1 unique voice variants); `string id = headerIndex - 1527` |
| `0xE1C6A8`-`0xE1D5B8` | the **chat-macro table**, 16-byte slots grouped `{"PRnn", LONG, SHORT}` — e.g. `PR22 / ONSLAUGHT / OST`. 22 base macros, then `PR22`-`PR53` (the Codec Pack 32), `PR54`, then `CPR01`-`CPR25`. **Not gated** — no flag field, and the predicate never touches it; gating happens once, on the phrase id |
| `0x9C0600` | `roundMode() == 10 && amHost()` — the **Combat Training instructor** test. **Not** an ownership or expansion check: an earlier note describing it that way was wrong, and it reads nothing account-side |
| `0x9C2C90` | the non-training fallback for phrase ids 67..92: player not on team 0/1, carrying item type 17 with a nonzero count. Also not an ownership check |
| **`0xAF3BA0`, `0xAF4B60`, `0xAF4D90`, `0xAF5598`, `0xAF5A08`, `0xAF5ED0`** | **the clan row painters** — where `0x4b12` and `0x4b54` rows are actually rendered, and the reason a scan bounded at `0xAEFFFF` produced three false "no reader" results (see `FIELD_MAPPING.md`, batch 2a-redo). Each is `f(elementDescriptor, container, listNode)`: `lwz rX,0(node)` takes the row pointer and parks it in the descriptor (`+48` for the clan list at `0xAF55CC`, `+0` for the roster at `0xAF5A50`), so **every read of a row is one of a handful of loads inside these six functions**. `0xAF5A08` reads roster `+4`, `+28`/`+30`, `+48`; `0xAF4B60`/`0xAF5ED0` read `+52`/`+56`; `0xAF3BA0`/`0xAF3CC8` read clan-list `+52` into the date formatter `0x8843CC`; `0xAF5598` reads clan-list `+56` bit 0 |
| `0xD54420` / `0xD54458` / `0xD54490` | "give me the clan-list / roster / 96-byte list object" — the **only** route the UI has to those arrays. Seven, three and zero callers. The matching per-row accessors `0xD59FD8` (clan list) and `0xD5A13C` (96-byte list) are `0xD5A0A8`'s siblings; **`0xD59FD8` is a dead accessor** (zero `bl`, OPD `0x102A280` unreferenced, `ET_EXEC`) |
| `0xA8A080`-`0xA8A224` | the only consumer of the 96-byte `0x4b75` records, via `0xD5A13C`. Renders `+0` as a date (`0xDC9358` → `0xDCC7C8`, `"%Y/%m/%d %H:%M:%S"` at `0xE14040`), `+4` and `+0x45` as text, `+0x58`/`+0x5C` as decimals. **Reads `+0` with `ld` — eight bytes — where the parser writes four**; the screen is unreachable and looks unfinished |
| `0xD48D40` | the `0x4991` parser — four 57-byte **tournament entry** records, loop bound hardcoded to four. `rec+0x00` is the slot-occupied test, so all-zero means "no pending entries" |
| `0xD40E2C` | the **sole sender of `0x43c4`**, the host-rating vote — `f(session, stars)`, range-checked 1..5 at `0xD40E44`. Called only from the three star-picker screens |
| `0xA30A38` | initialises the **star picker** and defaults the rating to 3 (`stw r0,204(r3)` at `0xA30A50`). Exactly **four** call sites — `0x9DCB28`, `0x9DCD68`, `0xA12C14`, `0xA13710` — two end-of-game state machines, two states each. **Those four states are the gate that decides whether "rate this host" appears**, and which is which is unresolved |
| `0xA322A8` / `0xA3310C` / `0xA33F70` | the three `bl 0xD40E2C` sites, inside pickers `0xA30BF0` / `0xA327F4` / `0xA3313C`; `0xA33AC4` is the up/down clamp |
| `0xA35F70` / `0xA36050` | the **only** two posters of dialog event `0x150022` ("Choose a rating"), both inside the *combat-training* end-of-session machine at `0xA35788`. The in-game host rating does not use this event — do not reason from one flow to the other |

---

## 9. Server addressing — hostnames, ports, region

Full write-up in [HOSTS.md](HOSTS.md). **The addresses are not in the binary**; these are the
addresses of the code that *fetches* them from disc string resources, and of the override that
replaces them.

| VA | what it is |
| --- | --- |
| `0x7F9310` | the GCX `addrs` native — the whole consumer. Registry entry `0x1031568` = `{hash 0x00CEA915, opd 0x1018CA8}`; called from `lobby/scenerio.gcl` `proc17` as `command [cea915] -addrs $strres:28654` |
| `0x7F9330` | opens `d/testhk` **before** the disc path, with flags `0x80000000` set — the developer override |
| `0x7F9368` | `cmpdi cr7,r3,16` — the **only** validation on the override file. No magic, version, count or checksum |
| `0x7F93A4` | `0xDB178` reads the base strres id as a little-endian s16 out of the script stream — why 28654 appears nowhere as an instruction immediate |
| `0x7F9440` | `r29 <= 1`, the test that gives only slots 0 and 1 a port |
| `0x7F9460` | selects `id + 12` and ORs its integer into the flag word. The 13th record is a **field, not a delimiter** |
| `0x7F95C0` | `lhz r4,112(r1)` — the override file's port is **big-endian**, opposite to the strres path's little-endian reader at `0xDF9A8` |
| `0x7F9504` | `cmpwi cr6,r31,255` — the string loop exits without terminating the buffer, and `0xDCC680` then `strcpy`s it. 255 chars is an overrun boundary, not a truncation |
| `0x28AB00` / `0x28AAB0` | `SetHostString(i, s)` → `0x016188C8 + i*0x100`; `SetPort(i, v)` → `0x016194C8 + i*2`. 12 × 256 = 3072 lands exactly on the port array, which is what **proves** the slot count |
| `0x00FC2F20` | holds the host-table base `0x016188C8` |
| `0x016194CC` | the flag word. Bit 1 read at `0xBB1538`, `0xBB2260`, `0xBB92AC`, `0xBBC9A8`; **bit 0 has no reader** |
| `0x7F4A78` | the `varbuf[4]` region native (hash `0x009BA0AC`, OPD `0x1018958`) — body is `lbz r3,42(r9)` |
| `0x2FB28` / `0x2FBD8` | the `o/di` loader (64 bytes to `0x01698E04`) and its fallback, which writes **byte 42 = 0** → JP. BLUS30109's disc byte 42 is `0x01` → US |
| `0x2EE48` | the path-keyed encrypted-asset opener, reached from `0x280F0` at `0x28154` on flag bit 31. Truncates the path at its **last** `/` to derive the key — `d`, `stage/lobby`, `online` |
| `0x8849E8` / `0x9462C0` | builds the 688-byte network context (gate host `+0xEE`, port `+0x16E`) and the connect that consumes it |
| `0xBB1BB4` / `0xBB6938` | the auth URL copy (`uaccount.cc`, TOC base `0xFFA2B0`) and the version-check URL copy (`uupdate.cc`, `0xFFA350`) |
| `0xFF2338` / `0xFF233C` | the `'https'` / `'http'` scheme strings. **The scheme comes from the stored URL, not from a flag** — there is no code switch to patch |

> **Correction, 2026-07-29.** `0x7A5AA8` was briefly read as the network transport/port selector on
> the strength of `li r0,443` at `0x7A5C18`. It is not: that function is `f(obj, eventCode)`, the
> `li r4,3` beside it is the second argument to the flag API at `0x305A60`, and the arm contains no
> socket call. The 443 is an object field value that happens to equal the HTTPS port.

---

## 10. Gear and appearance — `0x4124` / `0x4133`

The wardrobe subsystem, end to end. Narrative and the colour tables are in `GEAR.md`; this is the
address index. The gear table is at **`charTable + 9888 + id*12`** — 12-byte records, three words at
`+8`, `+12`, `+16`.

### The packet parsers

| address | what |
| --- | --- |
| `0xD3732C` | the `0x3049` parser. `0xD3774C` copies the 32-byte trailer to `ctx+484`; `0xD36C74` returns the ctx (`profile+21968`) |
| `0xD3CF10`, `0xD3CFC0` | `0x4124`'s writers into the gear table |
| `0xD3C85C`, `0xD3C90C` | `0x4133`'s writers — **the same table**, which is why the two packets must agree |
| `0xD3CF00` | `cmplwi r9,128; bgt` — **records with id > 128 are silently dropped**. 29 of our 122 ids die here |
| `0xD3CFBC`-`0xD3CFE4` | the sixteen `{item, bit}` tail pairs: ORs a bit into `+16` **only if already set in `+12`**, so they grant nothing |

### The two gates

| address | what |
| --- | --- |
| **`0x927350`** | **item ownership.** `lbz r8,8(r9)` — an item whose record byte is zero is never appended to the wardrobe list. The gate the server owns |
| **`0x925538`, `0x92772C`** | **colour availability.** `lwz r0,12(r9)` then `and` against `1 << slot` |
| `0x92740C`, `0x927744` | readers of `+16` — a highlight/"new" marker, **not** availability |

### The wardrobe screen

| address | what |
| --- | --- |
| `0x9270AC` | the 9-arm category table: `{base id, count, equipped-byte offset, name group hash}`. 67 reachable ids, max 116 |
| `0x92735C`-`0x927384` | the five hardcoded always-available ids — 28, 46, 68, 86, 102, the "None" of each category that has one |
| `0x927510` | `lwz r0,6604(r9)` — the built list's count, and the fallback's trigger |
| **`0x92751C`-`0x927568`** | **the empty-category fallback.** `stb r23,20416(r11)` at `0x927544` force-equips the category's BASE id and appends one row. **It writes the equipped byte**, so a later outfit commit persists it |
| `0x9274C4` | `cmpwi cr7,r28,0; beq` — skips the name lookup when the arm's group hash is zero |
| `0x9274D4` | `bl 0x240708` — `GetString(groupHash, ordinal)`, the item label |
| `0x9274F0` | `bl 0x94ad8c` — appends the row, **reached whether or not a label was fetched** |
| `0x927138` | the lower-body arm: `li r28,0`, a zero group hash, which is why that category draws one unlabelled row |
| `0x926D6C`, `0x926D74` | `cmpwi r0,35` / `cmpwi r0,38` off the head byte `+0x80` — special-cases Bush Hat and Fleece Cap, the two soft crushable hats. **The anchor that fixes the head category's ordinal order** |
| `0x9A50D0`, `0xA459D0` | the only callers of `0x9B9DF0` — the shortcut-binding screen and one other. **Neither is loadout code**, which is why the codec predicate has nothing to do with gear |

### The colour catalogue

| address | what |
| --- | --- |
| **`0x10506BC`** | the item x colour catalogue: 1044 records of 36 bytes, `{u32 item_id, u32 slot, u32 colour_name_ordinal}`. **The mask indexes `slot`; the name is a separate field reaching 35** — so a bit means a different colour on a different item |
| `0x105998C` | its terminator — a negative first word |
| `0x7E2D98` | the scanner, `f(itemId, slot) -> colourNameOrdinal`. Linear, stride 36 |
| `0x9276F0`, `0x9254FC` | its two call sites. **A miss here skips the swatch BEFORE the mask is consulted**, which is why bits above an item's slot count are unreadable |
| `0x240708` | `GetString(groupHash, index)` — resolves both item names and colour names against the disc |

Disc name group hashes are in `GEAR.md`; they are resource hashes, not ELF addresses.

## 11. Mail, and the personal-info echo

### The compose screen and GM mail

| address | what |
| --- | --- |
| `0xD53F10` | the `0x4800` builder. Field order is wire order; the payload is 967 bytes |
| **`0x8EEAA8`** | `li r0,3; stb r0,272(r24)` — **the only writer of the destination byte** at wire `0x3C5`. Value set is `{0, 3}`; 3 is the Game Master |
| `0x8EE9C8`-`0x8EE9D0` | the send fork on the same flag: set, the builder memsets the recipient-name block and skips the recipient build entirely |
| `0x8E4B30` | `rldicl. r9,r0,46,63` — tests **bit 18** of the compose flags at `screen+372`, which dims the recipient-list row. **Bit 18, not 17**: the rotate tests `64-46`, and two traces read it wrong before the arithmetic was checked |
| `0x8EF098` | sets bit 18 — the **GM menu item**, dispatch case 3 |
| `0x8E6ECC` | the other setter, a screen-entry arm gated on bit 3 |
| `0x8EDF78` | the "View/Edit Address Book" handler. Requires `recipientCount > 0` or it plays deny SE 91 at `0x8EEE84` and returns. The English name is a mistranslation of *view/edit the RECIPIENT list* |
| `0x8E4970` | the To-menu row painter, and the per-row dim conditions — Friend List dims on `byte 20190 == 0`, **recomputed as the friend count on every screen build** |
| `0xD53D1C` | the `0x4801` parser. **Bit 0 of its flags byte must be set** or the client re-sends the whole letter as `0x4860` |

### `0x4131`, the personal-info echo

| address | what |
| --- | --- |
| `0xD3C3DC` | the parser. Last read is the 128-byte comment at `0xD3C6E0`, then straight into READ_END at `0xD3C6F4` — **182 bytes, not 186** |
| `0xD5C858` | READ_END. **Performs no length check**, and the read helpers bound against the 1024-byte receive buffer rather than the payload — which is why over-sending went unnoticed for months |
| `0x88426C` | the only reader of the face-paint byte (`profile+7652`) — the player-announce builder, which broadcasts it verbatim. **A single byte**, which is why a per-colour unlock mask was impossible |

### Codec pack, additions to section 1b's neighbourhood

| address | what |
| --- | --- |
| `0x9B9E30` | `rlwinm r27,r0,4,27,27` — `(trailer[3] & 1) << 4`, the availability threshold |
| `0x9BADA4` | `clrlwi r0,r0,31` — the same bit again, choosing between two list-builders. **Both mask to bit 0, so bit 1 is discarded by the instruction encoding** |
| `0x6FC838`-`0x6FCAEC` | the skill accrual and level-up path, for context on how the preset-message gate sits beside it |

## 12. Auto-patch — `checkver.html` and the update flow (`uupdate.cc`)

Full write-up, including the response grammar and the open questions, is in `OBSERVED.md` under
"Auto-patch — checkver.html and the update flow". This is static analysis only: our server has
always answered `checkver.html` with a single `0x00` byte, so none of the `0x01` branch below has
ever been exercised against a real client. Module TOC base (mini-TOC anchor, `-mminimal-toc`
build) is `r30 = 0xFFA350`, loaded via `lwz r30,-27468(r2)` with real TOC `r2 = 0x010353A8`.

| VA | what it is |
| --- | --- |
| `0xBB7100`-`0xBB72E8` | builds and sends the checkver POST body `%d,%s,%u` = packed client version, `"BLUS30109"`, `rand()*2` nonce |
| `0xBB7340` | reads reply byte 0: `0x00` up to date (`bb734c` → `0xbb709c`), `0x01` parse the rest (`bb7354` → `0xbb7364`), else error state 10 (`bb735c`) |
| `0xBB73C0`/`0xBB73E8` | 255-cap `strncpy` (`0xDCCC28`) of the two base URL strings ("string A" patch base, "string B" HTTP-fallback base) out of the reply |
| `0xBB7418`-`0xBB76B0` | the version-range record loop, 44-byte stride from obj+1588, **≤8 records** (obj+1980 is reused as unrelated scratch) — a parse failure on one record still advances the count and keeps the 31-char name, so a malformed record still gets fetched |
| `0xBB756C`-`0xBB7584` | version packing: `major<<24 \| minor<<16 \| revision`, each component ≤255 |
| `0xBB75A8`/`0xBB76CC` | the gate: client's current version (read at runtime, see below) must be ≥ the record's "from" version, or the record is rejected |
| `0xBB7950`/`0xBB7B9C` | install Blowfish keys from the reply's two trailing 64-byte blobs into keystore slots **7** (payload files) and **8** (`.inf`), via singleton `0xD64498` |
| `0xBB7BF4` | builds `%s/%u.%u.%u/relnote.txt` (string A base) and fetches it — nothing in this TU renders the body; it is fetched and not displayed |
| `0xBB7D48`/`0xBB7DB8` | builds `%s/%u.%u.%u/%sinf` — note **no dot**, the record text must supply its own trailing `.` for the on-disk name to read `...to1.34.0inf` |
| `0xBB7E7C`-`0xBB7F4C` | `.inf` Blowfish-CBC decrypt: keystore slot 8 → stream wrapper `0xBBD880` → decryptor `0xD652E0`, drained 1KB at a time into a reader object (ctor `0xD66CF0`) that carries no attributable strings — **the decrypted plaintext grammar is not recoverable from disassembly**, only that it yields a count at obj+1584 and an array read as 16-byte entries (name ptr +0, flag bits tested `,29,29` at `0xBB9098` and `,30,30` at `0xBB9140`) |
| `0xBB8618`-`0xBB864C` | key-slot-7 decrypt into RAM, structurally identical to the `.inf` path — **not** the code that writes files to disk (see next row) |
| `0xBB8E6C`-`0xBB903C` | **the actual disk install**: `open("dl/p/ar/"+name, device 1, O_RDONLY)`, `open(same path, device 7, O_CREAT\|O_WRONLY, flags@0xFF23F8)`, plain `read`/`write` loop (no cipher in this loop), close both, then `unlink` the device-1 copy. A real cross-device copy-then-delete, not a passive overlay |
| `0xBB9150`-`0xBB9170` | the HTTP-fallback writer: same `dl/p/ar/%s` path, device chosen per-entry by flag bit `,27,27` (7 if set, else 1) |
| `0xBB9BC0`-`0xBBA0D4` | `.torrent`: URL `%s/%u.%u.%u/%s.%u.%u.%uto%u.%u.%u.torrent` (string A base, `"BLUS30109"`, from/to versions) fetched raw (no cipher), then handed unmodified to statically-linked Transmission (`tr_torrentInitData` at `0xD92180`, `tr_init("dl")` at `0xD8B710`) — genuine BitTorrent, bencode parser and tracker announce/scrape strings present at `0xE1D470`-`0xE1F5C8` |
| `0xBB90B0`/`0xBBC7B0` | the plain-HTTP fallback fetch, `%s/%u.%u.%u/%s` from **string B**, `Range: bytes=%d-` resume support, gated by flag bits at obj+1036 |
| `0xBB68A0`/`0xBB6EC0` | the client's "current version" query — `bl 0xD5EDE0` (mount registry) → vtable+24 with `r4=".p"` → result stored at obj+980/obj+992. **A runtime query of the mounted archive, not an ELF constant** |
| `0xFADEA0` | `sys_proc_prx_param`, libstub range `0xDED5A0`-`0xDEDA70` — the complete 28-module/349-function import table. **No `cellGame`, `cellGameExec` or `cellGameUpdate` anywhere in it** — the install above is entirely client-side, no PS3 system update package involved |
| `0xD5EDE0` region | the mount registry; `dl` is registered as a named VFS early in startup (`0x2FD6C`-`0x2FE40`), backed by `dl/p/.p` (package) and `dl/p/.l` (index) — separate from the `dl/p/ar/` download-cache tree |
| `0xBB5150` | version→string formatter (`%d.%02d.%d`, `%d.%02d`) called from the title/network-start screen (`0x95CCF0` etc.) next to a `"popup"` object — the one UI touchpoint found, and it is a version display, not update UI. **No dialog raiser (`0x8858F0`/`0x885A08`), no progress/percentage argument, and no display string for `relnote.txt`'s body exist anywhere in this module** |

Open question, stated precisely because it is the one thing static reading cannot settle: whether a
newly-installed file under `dl/p/ar/` is visible to the archive driver immediately (device 7 is
inferred, not confirmed, to be the live `dl/p` mount) or only after a restart — `0x214E0`'s device
root table is populated at runtime and cannot be resolved statically.

## What actually worked, methodologically

Worth keeping, because three readings were wrong before they were right:

- **Anchor on a single call site.** `0xD42178` had exactly one `bl` xref, and that made its caller
  the whole semantic story. Start from uniqueness where you can find it.
- **Follow control flow into a call; never scan backwards for the nearest `li`.** Two shared
  increment tails (`0x6ED760`, `0x6EFF98`) mis-attributed keys that way, and one of them produced a
  confident negative that was true only by luck.
- **Prove the assumption the search rests on.** The re-audit that settled b14 succeeded because it
  *proved* all 152 `r4` values were in-function constants — the thing the first pass had assumed.
- **Uncommon literals are good anchors.** The `10` of the Base SOP-destabiliser multiplier, the `11`
  of the Mk.II gate, `191`, and `0x5D588B65` all located their functions faster than any string.
- **The disc names things the binary does not.** The Headshots-Only flag, the Mk.II player count and
  every Personal Stats label came from stage scripts and string resources, not the ELF. See
  `ASSETS.md`.
- **A live round beats a confident trace.** Four ELF readings were corrected by rounds played on
  2026-07-27 alone.
