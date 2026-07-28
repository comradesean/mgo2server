# Gates: what the server switches, and what the client refuses

One page for the switches. Two kinds of thing live here:

1. **Gates we control** — bits and bytes the server sends that turn client features on or off.
   Several are currently zero by default, which means we are the ones holding a feature closed.
2. **Refusals** — values the client rejects outright, usually by discarding a whole packet or
   stalling the screen. These are the ones that cost a debugging session when you trip them.

Everything here is read from `MGO2.elf` or the disc unless marked otherwise. Where a value is
**operator policy** rather than protocol it says so — that distinction is the whole point of
CLAUDE.md's three-way classification, and it decides whether you may change something.

---

## 1. Feature flags — `0x4101`, payload byte `0x12A`

Six feature bits in one byte. The client reads them through
`featureBit(ctx, n) = (ctx[0x117D0 + n/8] >> (n & 7)) & 1` at **`0xD382F8`**, which **rejects any
bit above 5**. `ctx+0x117D0` has exactly one writer in the whole binary — `0xD3C348`, a 16-byte raw
read inside the `0x4101` parser (`0xD3C120`) — and walking that parser's reads puts the block at
payload offset **`0x12A`**.

| bit | meaning | we send |
| --- | --- | --- |
| 0 | **Team Sneaking selectable** in Create Game, plus one Sneaking rule option (`ruleopt_bit[4] = 4`) | **0** |
| 1–5 | exist and are read by the same helper; meanings unknown | 0 |

**We are currently suppressing Team Sneaking by sending a zero byte.** The disc-side mask already
permits it: the lobby stage script's `rule_bit` is `191` = `0xBF` = rules {0,1,2,3,4,5,**7**}
(GCX native `0xAB3201` → `0x8E0A64`, from `o/stage/lobby/scenerio.gcx` `proc17`), and
`countSelectableRules()` at `0x8E0824` returns **7**. The rule list is the AND of the two gates, and
only ours refuses. The menu builder special-cases rule 7 against this bit at `0x8AFD84`, and four
further sites enforce it (`0x8996DC`, `0x89ADB8`, `0x8AD794`, `0x8ADC78`), so it is a real feature
flag rather than menu cosmetics.

**A sixth consumer, server-side:** `AutomatchGameController` refuses rule filter 7 in `0x43e0`
because we clear this bit — so a client that somehow offered the Team Sneaking row would be turned
away rather than queued for a rule the lobby cannot run.

**Five more enforcement sites, in the automatching screen** (found 2026-07-28, see
[AUTOMATCH.md](AUTOMATCH.md) §5): `0x93B7D8` drops the Team Sneaking row from the automatch rule
list, `0x93B894` swaps the panel art, and `0x93C9C4`/`0x93CB30`/`0x93CC30` choose between two
background resources. All read the same bit 0. So the release-day automatch rule list has **seven
rows, not eight**, and that already falls out of the zero byte we send — no extra work.

**Where it is in our code:** the byte falls inside the tail that
`CharacterConnectController.getCharacterInfo` zero-fills — `padTo(buffer, BLOCKED_END)` at `0x129`,
then `padTo(buffer, INFO_PAYLOAD_SIZE)` to `0x142`. Setting `0x4101[0x12A] = 0x01` would make a
seventh selector row appear.

**Not enabling it is policy, not limitation** — see CLAUDE.md, "Target version: release day". Team
Sneaking went live 2008-07-04, three weeks after launch. Recording the mechanism is what makes a
later version toggle a one-byte change instead of a research project.

---

## 2. Round flags — `0x4310`, the `[rule, map, flags]` triple

The host pushes one triple per round at payload offset `0xA3 + 3 × round`. The third byte is a
**three-way radio, not a bitfield**, which is why only two values are ever tested binary-wide
(reader: `0x6A9948`):

| value | meaning |
| --- | --- |
| `0` | Normal |
| `2` | **Drebin Points enabled** |
| `4` | **Headshots Only** — *"When enabled, if a player is not taken down by a headshot, a penalty will be handed to the shooter."* (the game's own tooltip) |

Recovered from a plain-text-labelled lobby menu table at `0xFE7084/88/8C` — neighbours
`obj_4_select_others`, `icon_drebin_point`, `icon_HSonly` — with rows built at
`0x8AD6B4`..`0x8AD838`, label ordinals 400/402/403 and tooltips 409/411/412.

**This is a per-round option and is NOT one of the `game` table's columns.** Those come from a
different field, the `S+0x3A0` bitfield expanded into the `0x4310` settings word at
`0x8CA2BC`..`0x8CA420`.

**Consequences worth knowing:**

- **Headshots Only is the only way to move `0x4390` struct-B slot 38.** b38 counts deaths caused by
  that penalty; player state 191 is the penalty state, with one entry point in the binary
  (`li r4,191` at `0x77B0DC`) reachable only under this flag. Every archived round carried
  `flags = 0`, which is why b38 has never been nonzero.
- **Free visual tell in the round list:** Headshots-Only rounds draw **light blue** (`0x3BCFFF`) and
  Drebin-Points rounds **pink** (`0xE12682`). Those are RGB colours, not resource hashes.
- The server logs the value: look for `flags=` in `checkHostSettings`.

---

## 3. Rules that no server byte can reach

| rule | name | status |
| --- | --- | --- |
| 0–5 | DM, TDM, Rescue, Capture, Sneaking, Base | live-confirmed by creating one game each and reading the byte |
| 6 | **BOMB Mission** | **hardcoded off** |
| 7 | Team Sneaking | gated by the feature bit above — ours to open |
| 8 | COOP | **hardcoded off** |

All three rule enumerators contain literal `cmpwi 6` / `cmpwi 8` skips **before** the mask is
consulted, and the GCX loader allocates no map or option storage for them. **BOMB and COOP need a
client patch**, which settles the question of whether BOMB arrived server-side. It did not.

---

## 4. Player-count gates

| feature | threshold | notes |
| --- | --- | --- |
| **Snake role** (Sneaking) | 2+ players | `cmpwi cr7,r28,1` / `ble` at `0x71CA84` |
| **Metal Gear Mk.II** (Sneaking) | **12+ players** | `cmpwi cr7,r28,11` / `ble` at `0x71C7FC`, same literal in the request handler at `0x71C6CC` (refusal writes status `0xFF`) |

Both count slots 0..23 whose `team != 0xFE`, using the same counter — which is what makes the
comparison meaningful.

**Note the off-by-one and do not smooth it over:** the code requires **> 11, i.e. 12**, while the
disc's own English rule string says *"If 11 or more characters are playing, one player becomes Metal
Gear Mk.II and can support Snake."* Community sources split the same way (Japanese wikis say 11+,
English say 12+). The code is the authority; plan for 12.

Once the gate passes, the holder is chosen **at random** — an LCG (`seed*0x5D588B65 + 1` at
`0x71CBD8`) mixed with round elapsed time and a profile byte, modulo the pool, drawn from the larger
of team 0/1 — and forcibly moved to **team 2**, Snake's side. An already-seated Mk.II is not demoted
if the count later drops.

**Consequence:** `0x4390` slots b52 (Mk.II kills) and b57 (knockouts dealt as the Mk.II) are
**untestable below 12 players**, which is a different category from "untested".

---

## 5. What the client computes itself — never send it

The server's only job is honest stats. Sending a value for any of these is either ignored or
actively wrong:

| thing | how the client derives it |
| --- | --- |
| ~~Medals and titles~~ | **WRONG — corrected 2026-07-28, see §5a below.** These are SERVER-DRIVEN |
| `0x4105` **OTHER row** | `column − headshots − lockon`, clamped at 0. So columns 0/1/4/5 are **minuends**: send the total and OTHER falls out |
| `0x4105` **ALL row** | sum of the displayed rows |
| `0x4105` **Total page** and the **header play time** | per-column sums over mode rows **0..6** |

**Row 6 is invisible but summed into every Total and the header.** Anything placed there inflates
totals with nothing on screen to explain it. Rows 6 and 7 must be zero.

### 5a. Medals and titles are OURS, not the client's

This page said the opposite until 2026-07-28, and so did `PROTOCOL.md`. Both were wrong, and a live
report is what caught it: a character showed "500 Mk.II destructions" with zero Mk.II kills, and the
award survived every stat being reset to zero.

**Medals are gated only by a 16-byte bitfield at `0x4103` wire 615.** The gate at `0x916E20` reads
the row id, tests the bit (`0xD5C2A8`), and skips the row if it is clear — there is no stat load
anywhere in `0x916E20`..`0x916FD0`. The `threshold` word in the `0xE139C0` table is loaded *after*
the gate and `sprintf`'d into the description as its `%d`, which is why the number reads like a
requirement when it is only text.

**Titles are gated by a 22-bit mask at wire 563** (rating-block entry 3).

The symptom reproduced byte-exactly: we sent the string `"FP-STR-C"` at wire 615, whose byte 4 is
`'T'` = `0x54`, bit 6 set = medal id 65 = "500 Mk.II destructions". That one string lit 17 medals.
Wire 563 carried `4024`, setting title bits 3–11.

**The layout is medal-id-keyed, not row-indexed** — a hand-written switch with a byte and bit per
id, LSB-first; bits 3 and 7 of each byte and bytes 13–15 are unused.

**Client bug to avoid: never set title bit 22 or above.** The popcount loop runs 23 iterations for
22 titles and reads past the table.

**Consequence — now acted on (2026-07-28).** Because the client gates on nothing but these bits,
*we* decide when each one is set. Both fields are served from real requirements as of V45:

- **Medals** derive at query time (`StatsService.medalBits`) — a medal is earned when the career
  statistic reaches the number the client prints in that medal's own caption, which is the one
  choice that leaves the screen truthful.
- **Titles latch** in `chara_title`, because their requirements are ratios and a ratio falls.
  Wire 563 is the mask of unlocked rows; **wire 541 is computed by us** as the best unlocked title
  by rank — the client has no set-title command, so nothing else could choose it.

Requirements live in `src/main/resources/awards.json`; the reasoning, the sources and the guessed
numbers are in [`AWARDS.md`](AWARDS.md). This page still holds the two client limits that constrain
whatever we set: **never title bit 22+**, and the medal layout is id-keyed, not row-indexed.

---

## 6. Refusals — values that break a screen

These are the ones that cost a session. All are live-confirmed unless noted.

| where | rule | what happens if you get it wrong |
| --- | --- | --- |
| **any command** | must be answered | unanswered → the client stalls, then fails with `FFFFFF60`, prefixed by whatever screen was open. It is never a malformed reply, always a missing one |
| `0x4105` | `page` must be **0 or 1** | anything larger → parser bails with `-0x47` and **silently discards the whole matrix** |
| `0x4105` | send **page 0 before page 1** | receipt of page 0 **zeroes the whole grid region including page 1** |
| `0x4107` | must be **last** in the burst | its parser unconditionally completes wait slot `0x16` (`0xD3E4B0`); anything after it arrives unexpected, and omitting it stalls into `FFFFFF60` |
| `0x4103` | clan privilege word (element 0 of the 12×u16 block) must be **0** | all bits set → a saluting-soldier `!` badge and a hard poll loop at ~73 ms; the clan coroutine `0xAB0074` ands the word and refuses to advance. It is a **notification mask the client drains to zero**, not a permission mask |
| `0x4103` | clan emblem flag must be exactly **3**, and membership state in `{1, 2}` | `0x905A94` tests for equality with 3; anything else means "no emblem" and skips the `0x4b4a` fetch entirely. State 0 wraps under an unsigned compare and also skips |
| `0x4680` / `0x4684` | start and end words are **result codes, must be 0** | a nonzero start aborts the screen with `1032:%08X` (`1034:` for `0x4684`). **Never a count** — sending 5 produced `1032:00000005` |
| `0x4b71` | second word must be **2 or 3**, and send **exactly one** | any other value fails the packet with `-71`; sending two (by analogy with `0x4105`'s pair) completes the slot on the first and stalls with `1931:FFFFFF60` |
| ranking HTTP | returned `N` must not exceed the requested `records` | the client drops the whole reply |
| ranking HTTP | emit at most **15** characters of the 16-byte name | the client `strlen`s an uncleared stack buffer |

---

## 7. Where the detail lives

This page is the index, not the evidence. For the full traces:

- `dev/proto/mgo2_cmd_4390.ksy` — the round report field by field, including b38, b52/b57 and the
  score coefficient table.
- `dev/docs/PROTOCOL.md` — command by command, byte by byte.
- `dev/docs/OBSERVED.md` — the chronological journal, including the readings that turned out wrong.
- `dev/docs/LOBBIES.md` — lobby types and subtypes (Survival and Tournament are **lobbies**, not
  game modes; do not confuse them with the rule byte).
- `dev/docs/ASSETS.md` — opening the disc, which is where the menu labels and tooltips came from.
- `CLAUDE.md`, "Target version: release day" — why several of these gates stay shut.
