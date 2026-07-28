# Address index: where the important findings live in `MGO2.elf`

Every load-bearing conclusion in this project is anchored to an address in the decrypted binary.
Those anchors are the expensive part — a fact can be re-derived from a capture in an evening, but
finding the function again costs a full disassembly pass. This page is the index.

**Binary:** `dev/ref/MGO2 (decrypted).elf` — ELF64, **PowerPC 64, big-endian**.
File offset = VA − `0x10000`. Text section spans roughly `0x10230`..`0xDE9328`.

**Reading it.** `powerpc64-linux-gnu-objdump -D -b elf64-powerpc` is on PATH, and `capstone` 5.0.6
is installed (`CS_ARCH_PPC`, `CS_MODE_64 | CS_MODE_BIG_ENDIAN`). `dev/ref/analyze_mgo2.py` has ELF
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
| `0x6FC254` | the kill-credit path's team test, which is what ties that role to `snake_kills`/`mk2_kills` |
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
| `0xE14EB0` / `0xE152D0` | the 22-title resource table / award sprites |
| `0xD25D0` | the 24-bit rotate-5-add string hash used for resource names |
| `0x942564` | the 9,999,999 display clamp |
| `0xD3F3A4` / `0xD3F3C0` / `0xD3F3DC` | the medal bitmask and survival fields parsed out of `0x4103` — **unresolved** against the "medals are client-computed" finding; possibly survival-lobby specific |
| `0x91B338` | the stats screen reading rating-block entry 4 |

---

## 8. Elsewhere, still load-bearing

| VA | what it is |
| --- | --- |
| `0xD3FEAC` | the sole writer of the round token at session `+0x32F8` — half of the proof that `0x4390` attribution is connection-implicit |
| `0xD47E18` | the `0x4902` lobby-list entry parser (99-byte entries) |
| `0x905A7C` / `0x905A94` | the clan emblem gate — byte must equal 3 **and** membership state in `{1,2}` |
| `0xAB0074` | the clan coroutine that ands the privilege word and refuses to advance unless it is zero |
| `0xBC2D78` | the ranking scramble |
| `0x305A60` | a per-object 896-bit flag API |
| `0x6FC760` | the objective notifier, `f(id, slot)` |
| `0xDDEE30` | the Scanning skill's S. PLUG item |

---

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
