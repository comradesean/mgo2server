# Field-mapping campaign: every unknown field in every packet we use

**Goal: total understanding.** Not "enough to work" — every field named, positioned and explained,
with the evidence in the `.ksy` `doc:` tag so nobody has to re-derive it.

Scope is **packets the server actually uses** — registered handlers and commands we write. The 19
we have never seen are parked separately in `PACKETS_NOT_OBSERVED.md` and are not part of this.

## The number

**34 packets, 122 unknown fields**, as of 2026-07-31 (batches 3b and 3c). Was 44 / 178 at batch 1;
`0x4302`, `0x4129`, `0x4b12`, `0x4b70`, `0x4682`, `0x4841`, `0x4822`, `0x4800`, `0x4582` and
`0x4602` have reached zero (their rows stay in the table, marked
**0**, so the count stays reproducible). Regenerate with the script in this file's
history; the criterion is a `- id:` whose name starts with `unknown` or `unread`.

## Method, and the rules that keep it honest

1. **Tier 1 or nothing.** A field is only renamed when the binary says what it is: an address, an
   instruction, a destination struct offset. `dev/docs/ADDRESSES.md` has the methodology and the
   PPC64/OPD gotchas.
2. **Positions are already evidence and must not move.** Sizes and offsets in these schemas were
   read from parsers and are load-bearing. Renaming a field and documenting it is the work;
   changing a width is a separate, argued decision.
3. **A precise negative is a result.** "No reader anywhere in the image" is worth recording, and
   several fields have turned out to be exactly that. Say which searches established it.
4. **Never infer meaning from a neighbour's name or from a reference server.** Six regressions have
   come from that. Where a value is inherited and unexplained, say so in the `doc:` rather than
   inventing a label.
5. **Disc resources are fair game** — `dev/tools/gcx` and `dev/tools/solideye`, disc at
   `D:\rpcs3-v0.0.41-19598-357b7d44_win64_msvc\games\METAL GEAR SOLID 4 GUNS OF THE PATRIOTS
   [BLUS30109]` (WSL: `/mnt/d/...`). `AUTOMATCH.md` section 10 documents the string-resource method
   that has already resolved skill names, gear names and colour names.

## Work list

| id | dir | fields | unknown | family | status |
| --- | --- | --- | --- | --- | --- |
| `0x4107` | s2c | 76 | **35** | stats | batch 1 done — 2 resolved (slots 33/34 = Team Sneaking), remaining 35 have **no reader in the image** |
| `0x4313` | s2c | 52 | **12** | game | batch 2b done — 5 named (0x098 password_enabled, 0x099 dedicated, +176/+179 the flags word's two unread bytes, +184 host_ping); remaining 12 all carry precise negatives |
| `0x4b21` | s2c | 28 | **9** | clan | batch 2a **partial** (agent lost to quota) — 2 named: `disband_cooldown_s`, `emblem_display_cooldown_s`; docs upgraded throughout. Not revisited by 2a-redo |
| `0x4b81` | s2c | 18 | **10** | clan | batch 2a **partial** — no renames; all 10 given precise negatives and tier-1 provenance |
| `0x4221` | s2c | 17 | **2** | social | batch 3a done — **7 named**: `experience`, `beginner_flag`, `worn_title`, `host_rating_numerator`, `host_rating_denominator`, `clan_emblem_flag`, `grade_points`. The card's whole renderer (`0x905818`) is mapped slot by slot; two more consumers of feature bit 2 found; OBSERVED.md's "the card's LEVEL is `T+0x484`" corrected |
| `0x4310` | c2s | 31 | **7** | game | batch 2b done — 0x0f7 = level_limit_tolerance; `common_c` renamed `common_flags_lsb`; the four echo-only negatives re-established independently |
| `0x4120` | s2c | 27 | **2** | connect | batch 2c done — 5 named (`dead_settings_05`, `entry_id_0..3`); byte 0 bit 0 proven **load-bearing** |
| `0x4305` | s2c | 33 | **7** | game | batch 2b done — count unchanged, but all 7 now carry tier-1 provenance; 4 stale tier-4 labels corrected (stance, tolerance, max_players, rule_timers) |
| `0x4b54` | s2c | 11 | **2** | clan | batch 2a-redo done — 3 more named (`lobby_name`, `game_id`, `game_name`) and **three false negatives corrected**; `unknown_30` proven live and feature-bit-2 gated; `unknown_18`'s negative re-run on the corrected band |
| `0x4991` | s2c | 14 | **6** | lobby | open |
| `0x4101` | s2c | 13 | **1** | connect | batch 2c done — 4 named: `beginner_flag`, `feature_flags`, `grade_points`, `dead_13100` |
| `0x4582` | s2c | 8 | **0** | social | batch 3b done — **all five named**: `lobby_id`, `lobby_name`, `game_id`, `game_name`, `lobby_type`; the tail is a location block, proven by a consumer-code bijection with `0x4b54`. The `0x4583` filter is real but **inert** — its destination list has no reader anywhere in the image |
| `0x4602` | s2c | 8 | **0** | social | batch 3b done — **all five named**, same block. `SocialGameController`'s open question is **CONFIRMED**: current lobby name and current game name, plus a lobby **id** (not level/rank) and a lobby **type** enum (not a lobby id) |
| `0x4302` | s2c | 21 | **0** | game | batch 2b done — **all four named**: lobby_subtype, round_flags, selector_flags, selector_tiebreak |
| `0x4b12` | s2c | 10 | **0** | clan | batch 2a-redo done — **all four named**: `row_display_flag`, `discarded_29`, `discarded_2a`, `dead_2b`; two are provable parser-level discards |
| `0x4b75` | s2c | 7 | **4** | clan | batch 2a-redo done — count unchanged, but the consumer screen (0xA8A080) is found: two of the four are displayed integers, one is a precise negative, and `unknown_00` exposes a client width bug |
| `0x4129` | s2c | 18 | **0** | connect | batch 2c done — **all three named**; `play_time_seconds` drives the MGS4 single-player unlock |
| `0x4105` | s2c | 21 | **2** | stats | batch 1 done — cols 13/15 have **no reader in the image**; both docs now carry the scan that establishes it |
| `0x4122` | s2c | 17 | **2** | connect | batch 2c done — no new tier-1 name available; both negatives independently re-run |
| `0x4902` | s2c | 12 | **2** | lobby | open |
| `0x3101` | c2s | 26 | **1** | other | open |
| `0x4112` | c2s | 1 | **1** | other | open |
| `0x4130` | c2s | 23 | **1** | other | open |
| `0x4150` | c2s | 1 | **1** | other | open |
| `0x4316` | c2s | 1 | **1** | other | open |
| `0x4344` | c2s | 2 | **1** | other | open |
| `0x4390` | c2s | 81 | **1** | other | open |
| `0x43a6` | c2s | 1 | **1** | other | open |
| `0x43c0` | c2s | 5 | **1** | other | open |
| `0x43c4` | c2s | 1 | **1** | other | open |
| `0x43c8` | c2s | 2 | **1** | other | open |
| `0x4440` | c2s | 1 | **1** | other | open |
| `0x4700` | c2s | 4 | **1** | other | open |
| `0x4800` | c2s | 6 | **0** | other | batch 3c done — `echoed_flag_273` named by struct bijection; the whole compose buffer proved to be a `0x4822` mail record |
| `0x4b10` | c2s | 3 | **1** | other | batch 2a-redo — meaning still unknown, but the two concrete senders hardcode **1** |
| `0x4b46` | c2s | 1 | **1** | other | batch 2a-redo — traced to the dispatcher's 4th arg; the OPD-table dead end recorded |
| `0x4b70` | c2s | 1 | **0** | other | batch 2a-redo done — `clan_id`, from the binary rather than a capture |
| `0x2002` | s2c | 1 | **1** | other | open |
| `0x2004` | s2c | 1 | **1** | other | open |
| `0x3049` | s2c | 14 | **1** | other | open |
| `0x4131` | s2c | 9 | **1** | other | batch 2c done — negative re-run and recorded with near-misses named |
| `0x4682` | s2c | 5 | **0** | other | batch 3c done — `lobby_type`, a 9-arm jump table; also settles `LOBBIES.md`'s open `0xFE85F0` index question |
| `0x4822` | s2c | 9 | **0** | other | batch 3c done — `name_count` named; **four documented claims corrected** (`comment` is the subject, `message_type` 3 = GM and 1/2 = clan, `important` is read after all, the echo offset was off by one) |
| `0x4841` | s2c | 2 | **0** | other | batch 3c done — `body_text`; the destination address is provably identical to `0x4800`'s `body` source, so the [INFERRED] round-trip is now tier 1 |

## What batch 1 established, and what it changed about the method

**2 of 39 fields got names. That is the honest headline, and it is not the whole result.** The
larger outcome was provenance: 27 slots moved from tier 2 (fingerprint-only — we knew a value
appeared, not where it came from) to tier 1 with an address, an instruction and a destination
offset. And every remaining unknown now carries a *precise negative* — which searches were run and
what would settle it — instead of a blank `[UNKNOWN]`.

That ratio is worth expecting on the rest. Most of these fields have **no reader in the image**;
the work is proving that rather than naming them.

### Lead with the disc, not the disassembler

The string-resource route works for anything the client renders a label for. `gcx` set
`$strres:17779`, group `1ab3b6` (`mgo2_res_myscore`) returned all six known mode-page labels and
all three Snake labels byte-identical, which is what licensed trusting it for two new ones.

**One trap, recorded because it looks plausible when wrong:** strings start at **17943**, not at the
last `1ab3b6` header — twelve later headers belong to other sub-groups. Getting that wrong shifts
every label by twelve files and the result still reads like a sensible list.

### Highest-leverage addresses

| address | why |
| --- | --- |
| `0xD3DB1C` | the `0x4107` parser: a flat run of 73 reads into `T+3768+i*4`, stride 292. Slot ↔ memory index falls straight out |
| `0x917F34`-`0x918B80` | the DETAIL row switch, keyed on a 24-bit resource hash from the 36-entry display list at `0xE13BDC` — a hash→slot table handed over in one function |
| `0x91722C`-`0x9174AC` | the mode-page dispatcher; each arm loads its label as a string literal |

### Four documented claims corrected

1. **`0x4105` wire mode index 6 is TEAM SNEAKING and does have a page.** The schema said "6 HIDDEN
   (no page of its own)". Wire index ≠ memory row: eight wire records land on memory rows
   0,1,2,3,4,5,7,11. The old note's arithmetic was right; only the identity was wrong.
2. **"Text Chase Uses" was a transcription error** for "Text Chat Uses".
3. **Slot 30 is provably not a Rescue stat** — the Rescue arm reads 3876/3880/3888 and steps over
   3884.
4. **`0x4105` col 15's "post-game/ranking views" candidates are unsupported** — nothing outside two
   known ranges addresses that grid at all.

### Flagged, then resolved — it was a stale document, not an open question

The batch reported that the only readers of the `0x4107` store are the two Personal Stats screens,
with **nothing in title/medal evaluation reading it**, and flagged the tension with `OBSERVED.md`'s
"titles and awards are computed by the client from the stat values themselves".

**The finding is right and there is no tension: nothing evaluates titles or medals client-side at
all.** Both are server-driven and arrive as bits in `0x4103` — wire 563 (22-bit title mask), 541
(worn title, 1-based) and 615 (16-byte medal bitfield). `GATES.md` §5a settled this on 2026-07-28
and `AWARDS.md` documents the implemented policy; `OBSERVED.md` simply never got updated. Corrected
2026-07-30 at all three sites.

**Method note, and the reason this is worth recording rather than just fixing.** The original wrong
inference came from watching awards regenerate in step with the stats our own fingerprint sender was
writing — but that sender recomputed the award fields too, so the correlation was with our
arithmetic, not the client's. *A stat and an award moving together cannot say which side derived
which when one process emits both.* Expect more of this: a batch agent finding "no reader for X" is
evidence about the **client**, and when it collides with a doc, check whether the doc's evidence was
ever capable of distinguishing the two sides.

## What batch 2 established

**27 fields resolved, 178 → 151**, across three parallel agents on non-overlapping families. Two
packets reached zero unknowns — `0x4302` and `0x4129`, the first in the campaign to do so.

The naming ratio was far better than batch 1's 2-of-39, and the reason is worth generalising: **the
wins came from finding a second, non-network path to the same struct**, not from grinding parsers.

| lever | what it bought |
| --- | --- |
| `block+X = struct+752+X`, anchored four independent ways | every `0x4310` finding transfers to `0x4313`/`0x4305` *by destination offset*. This is the one legitimate form of the inference rule 4 forbids — it is not "the neighbour is called X", it is "these two writes provably land on the same byte" |
| `0xD493CC` — the client fabricating a `0x4302` row for its **own hosted game**, no packet involved | the scratch buffer starts at `T+0x00`, so every store names a field by its source. Resolved all four `0x4302` unknowns in one function |
| `0x8CA2BC`-`0x8CA900` — the post-create publisher into the property store | ~30 settings pushed with explicit key numbers, which names fields and gives their units |
| dead-accessor detection (OPD present, `bl` count zero, `ET_EXEC` so no relocations) | turns "no reader" from a search result into a *proof*, and distinguishes "unused" from "not found yet" |

### Three findings that were not documentation

1. **`0x4129` `+1172` is play time in seconds and drives MGS4's single-player unlocks.** Its readers
   feed `0x7F6F70`, which divides by 3600 and ORs cumulative bits into the `mgof.sav` flag word at
   0, 10, 20 and 50 hours. It hardcoded `0xffffff` (4,660 h) at every round end, tripping all four
   tiers for everyone; **fixed 2026-07-31** to send `sum(seconds_in_game)` across the six playable
   modes. See `CLIENT_STORE.md` §6 for why that quantity, and for the "the server cannot help"
   caution it turned out not to touch — that was about a different question.
2. **`0x4120` byte 0 bit 0 is an "already initialised" marker**, not the mystery constant
   PROTOCOL.md called it. Clear it and the client memsets 33 list-preference bytes and overwrites
   ~30 settings with defaults.
3. **`0x4313` wire `0x098`/`0x099` are `password_enabled` and `dedicated`**, documented as "zero".
   Checked the server: `HostSettingsReply` already copies the enclosing range, so no live bug.

### An elimination that cannot work, recorded before someone runs it

`PROTOCOL.md`'s BGM-volume / radar / HUD fields at `0x14`-`0x16` have **no accessor and no direct
profile access**. The obvious test — move the slider in game and watch the bytes — **cannot settle
it**, because `0x4110` echoes the raw 48 bytes and they round-trip whether or not the client reads
them. Per CLAUDE.md, an elimination is only valid if the experiment could have produced the
confirming observation. This one could not.

### Batch 2a was lost to a quota limit, and the salvage is the lesson

The clan agent died mid-write on `0x4b54`, leaving valid-looking YAML that **did not parse** — 16
doc lines dedented out of their block scalars. Two files were complete and clean; one needed repair;
two were never started.

**A killed agent's output must be validated before it is trusted, not after it is committed.** The
checks that caught it: `yaml.safe_load` over every schema, a `- id:` count against `HEAD` per file,
and a grep for changed `type:`/`size:`/`repeat:`/`encoding:`/`enum:` lines across the whole diff.
All three should run at the end of every batch regardless of how the agent exited.

## What batch 2a-redo established (the clan family, finished)

**8 fields resolved, 151 → 143**, two more packets at zero — and, more importantly, **three
documented negatives overturned**.

### The band error, which is the transferable lesson

Batch 2a called `0xA70000`-`0xAEFFFF` "the clan UI band" and proved several fields unread by
sweeping it. **The row painters are at `0xAF3BA0`, `0xAF4B60`, `0xAF4D90`, `0xAF5598`, `0xAF5A08`,
`0xAF5ED0` — just past the end.** Three `0x4b54` fields recorded as "PRECISE NEGATIVE, no reader"
are read and rendered on screen every time a roster draws.

Per CLAUDE.md's elimination rule, a sweep is only an elimination if the thing sought could have
been inside the range searched. **A band boundary is an assumption and has to be justified like any
other.** The cheap defence: before trusting a range, find where the packet's *renderer* lives, not
just where its parser's callers live. Here the giveaway was available all along — the roster's
`"----"` placeholder and the `STRING_LOBBY`/`STRING_GAME` element names were both cited in the file
*as support for the negative*, when a placeholder string is evidence that something fills the slot.

### The wins

| lever | what it bought |
| --- | --- |
| the shared row-painter functions above `0xAF0000` | `lobby_name`, `game_id`, `game_name`, and the truth about `0x4b54 +0x30`. Each takes `(elementDescriptor, container, listNode)` and parks the row pointer in the descriptor, so **every read of a row is one of a handful of loads inside four functions** |
| disc string ids reached from the renderer | `GetString(hash("lobby"), 996)` = **"Move to Game"**, which is what named `game_id` — a menu label the gate enables, not a guess from position |
| the parser's *scratch slot* | `0x4b12`'s four trailing bytes all pass through one byte at `r1+112`; two are overwritten before any copy-out, so they are **provably discarded**, not merely unread |
| dead-accessor detection, again | `GetClanListRow` `0xD59FD8`: zero `bl`, OPD `0x102A280` unreferenced, `ET_EXEC`. That closed the clan-list row's escape routes down to one, which is what makes `dead_2b`'s negative a proof |
| chasing a c2s argument to its **callers** | `0x4b70`'s u32 is `clan_id` — `lwz r9,0(node)` then `lwz r4,0(r9)`, i.e. offset 0 of a `0x4b12` row. The file had called this "a guess dressed as a finding"; it never needed a capture, only the call graph |

### Three findings beyond field names

1. **`0x4101` feature bit 2 gates a clan-roster column.** `featureBit(ctx, 2)` at `0xAF5AE8` /
   `0xAF5CF8` chooses between rendering `0x4b54 +0x30` as a decimal and substituting
   `GetString(hash("lobby"), 3)`, which is **a single space**. We send a zero feature byte, so the
   column is blank — which is exactly why "sent as zero, nothing on screen changed" could never
   have settled the field. `GATES.md` §1 lists bits 1-5 as "meanings unknown"; bit 2 now has a
   known consumer. **Do not open it** — release-day scope.
2. **The list slot at `session[+0x10000+6404] + 0x20000 + 29724` is shared.** `0x4b75` writes
   96-byte records into it and `0x4685`/`0x4686`/`0x4687` write 28-byte ones, off the identical
   base computation. These "lists" are reusable slots, not per-command arrays.
3. **`0x4b75`'s consumer screen reads its own record at the wrong width.** `0xA8A0B8` passes the
   row to a localtime helper that does `ld r0,0(r28)` — eight bytes — while the parser writes a u32
   at +0 and a 64-byte text block at +4. The triple is never requested (the client never sends
   `0x4b73`), so this is best read as an unfinished screen. It is also why `unknown_00` was **not**
   renamed: the only reader's behaviour and the parser's layout contradict each other, and a name
   would hide that.

## What batch 3c established (the mail and match-history singles)

**4 of 4 fields named, and four packets to zero** — `0x4800`, `0x4822`, `0x4841`, `0x4682`. That
is the campaign's best ratio so far and none of it came from grinding a parser. The headline count
at the top of this file has *not* been decremented here, because batch 3a/3b/3c landed
concurrently; recompute it once they have all merged.

### The lever, again: a second path to the same struct

Batch 2 said the wins come from finding a non-network writer of the same memory. Here the whole
mail family collapsed onto one observation: **the compose buffer and a mailbox record are the same
280-byte struct**, and there is a literal `memcpy` between them.

| address | what it bought |
| --- | --- |
| **`0xD34728`** `MailRecordCopy(dst, src)` | the canonical field list — `+0`, `+1`, `+2`(128), `+131`(128), `+264`(8), `+272`, `+273`, `+274`. Every `0x4822` field and every `0x4800` field is one of these |
| **`0xD34220`** / **`0xD342A4`** | the clear functions, which give the struct's *shape* for free: `bzero(+2,129)` and `bzero(+131,129)` expose the two NUL slots, `bzero(+288,709)` sizes the body |
| **`0xD5415C`** at `0xd541fc` | the call that joins them: `records[cat] + idx*280` -> `base-8576`. Opening a letter loads the server's bytes into the send buffer |
| **`0x8E2F30`** / **`0x8E8AFC`** | the two mail row painters — the list and OPENmail screens. Between them they read `+1`, `+2`, `+131`, `+264`, `+272`, `+273`, `+274` |
| **`0x91E3AC`** family | the four met-players row painters, each keeping the `0x4682` record in `r27`, which is what exposed the type jump table |

### Developer element names are a naming resource on the level of the disc

`0x8E2F30` and `0x8E8AFC` hash their UI element names out of the module mini-TOC
(`r30 = 0xFEFA80`), and the names are romaji: `NULL_jyusin_NAME_01`..`_08` / `_DATE_` / `_TIME_`,
`NULL_tochu-sousinzumi_*` (受信 received / 送信済み sent — independent confirmation that category 1
is the Sent tab), `NULL_sakusei_TO` / `_SUBJECT` / `_HONBUN_01`..`_05` (作成 compose, 本文 body),
`NULL_OPENmail_SUBJECT` / `_DATE` / `_TIME` / `_01`..`_12`, `CLAN_SUBJECT`. **`NULL_OPENmail_SUBJECT`
is what renamed `0x4822`'s "comment".** This is the same class of material `ADDRESSES.md` already
flags at `0xE0D548` and is worth trying for every screen in the campaign — it is free, it is in the
ELF, and it is the developers' own vocabulary.

### The resource-hash constants are recoverable when the guess is directed

`0x995D80(element, hash)` takes a 24-bit rotate-5-add name hash (`0xD25D0`), not a colour. The
family around it is `ST1_ON` = `0x5A06D9`, `STRING_ST1_ON_SD` = `0xF6EE7C`, both matched against
plain ELF strings. From there `0x5C86D9` = **`ST6_ON`** falls out by arithmetic: changing `1` to
`6` three characters from the end adds `3 << 5*3` = `0x28000`.

**But do not try to invert an unknown hash.** A meet-in-the-middle over six free characters
returns thousands of 24-bit collisions per target and none of them is evidence. The three mail row
states (`0x0CD73E`, `0x989DFB`, `0xF55717`) were left unnamed for exactly that reason: their source
strings live in a disc resource, not the ELF, and a guess that merely hashes right proves nothing.

### Six documented claims corrected

1. **`0x4822`'s `comment` is the SUBJECT line.** `+131` is the `0x4800` `subject` offset and the
   OPENmail screen renders it into `NULL_OPENmail_SUBJECT`.
2. **`0x4822`'s `message_type` 3 is the GAME MASTER**, previously "[UNKNOWN] … the obvious guess
   and is NOT evidenced". `0x8EA154` sets compose-flags **bit 18** on `== 3` — the same bit the GM
   menu item sets. Values **1 and 2 are clan mail**, selecting the element `CLAN_SUBJECT`.
3. **`0x4822`'s `important` is read.** "No client-side predicate reads it anywhere in the mailbox
   module" was wrong: `0x8e3934` reads it with `read` and `message_type` and picks one of three row
   display states. It is server-authoritative — no client code writes it.
4. **The echo offset was off by one.** `0x4822`'s doc said `important` is echoed at `0x4800`
   struct `+0x110`; `+0x110` is 272, `destination`. It is `+0x111`.
5. **`0x4841`'s body has no header**, and its address is provably `0x4800`'s `body` source. What we
   already send was right; the caveat it carried is retired.
6. **`LOBBIES.md`'s `0xFE85F0` array is not indexed `subtype - 1`.** `0x4682`'s jump table reaches
   that array and pins each pointer to a value: 1, **9**, 3, 4, 5, 6 — `TYPE_COOP` is 9.

### One negative worth keeping

`0x4682`'s trailing byte had been fingerprinted live with `40 + row` and produced nothing on
screen. That was a true observation and a useless one: the jump table rejects anything outside
1..9, so every value tested took the blank default. Per CLAUDE.md's elimination rule, the
experiment could not have produced the confirming observation — **a fingerprint value must be
inside the field's plausible domain before "nothing rendered" means anything.**

## What batch 3b established (the two roster/search records, finished)

**10 fields resolved, both packets to zero**, and the answer `SocialGameController` has been
waiting on since 2026-07-26 is now settled. `0x4582`'s and `0x4602`'s five-field tail is one
**location block** — `lobby_id` u16, `lobby_name` 16B, `game_id` u32, `game_name` 16B,
`lobby_type` u8 — "where is this player right now".

### The levers, in order of how much they bought

| lever | what it bought |
| --- | --- |
| **`0x9351AC`, a six-argument call** | `0x8F6D78`-`0x8F6D88` (friend list) and `0x90D6F8`-`0x90D710` (player search) load six row fields and pass them together to `f(kind, charaId, name, gameId, gameName, lobbyId, lobbyType)`. **An argument list is a struct definition someone else already wrote down.** Both flows make the same call; the black list makes it with four of the six hardcoded to zero, which is itself a divergence |
| **consumer-code bijection with `0x4b54`** | not merely the same field order and widths as the clan roster's named tail, but the *same instructions in the consumer*: `cmpwi 1` / `cmpwi 8` on the enum, then `game_id != 0`, then `0xD4908C(session) == 0`, then the "Move to Game" entry; and `lobby_id` → `0xD47CE0` → `0x27EF90(25)` + RecordSet key 254. This is rule 4's legitimate form — not "the neighbour is called X" but "these two fields are consumed by the same code" |
| **the module TOC, read as data** | `lwz r30,-N(r2)` gives a mini-TOC whose slots are element-name string pointers. Dumping 0xFEFE38 and 0xFEFEE8 printed `l_shib_y02_03_bg_friend_list`, `STRING_F_LIST_NAME`, `STRING_F_LIST_LOBBY`, `l_shib_y02_04_bg_black_list`, `STRING_B_LIST_NAME`, `STRING_B_LIST_HOST` — **the screens name their own columns**. Cheaper than any disassembly and it works wherever a screen sets element text by hash |
| **a small jump table over `GetString`** | `0x8E1110` turns the trailing u8 into 1 = Free Battle, 2 = Automatching, 3 = Tournament, 4 = Survival, 5/6 = Official Tournament, 7/8 = Training, else `"----"`. Batch 3c found the same shape at `0x4682`. **A jump table whose arms differ only in a string id is a free enum decode** |
| **closed provenance instead of a band sweep** | `0x4602` rows come from `0xD473F4`, which has **exactly one `bl` site in the whole text section**. `0x4582` rows come from `0xD464F8`/`0xD464D8`, six sites. Nothing had to be bounded by an address range at all — see the caution below |

### Three findings beyond field names

1. **`0x4583`'s filter is real and inert.** It copies survivors into `list(x, -1)` and **nothing
   reads that buffer**: the six `which = -1` thunks have zero `bl` sites text-wide and their OPD
   descriptors are unreferenced in an `ET_EXEC` image. PROTOCOL.md's *"serving zeros yields an
   empty roster"* is corrected. Note PROTOCOL.md had already tagged that whole table "traced from
   the ELF, single-source, none confirmed by a capture" — **the caveat was doing its job and was
   still worth re-testing.**
2. **The `0x4583` / `0x4603` asymmetry has a structural cause, not a policy one.** `0x4582` writes
   four arrays (2 lists × 2 buffers, `0xD33508`); the search flow has one. There is no second
   buffer for `0x4603` to compact into.
3. **The same bytes carry two captions.** `lobby_name` is `STRING_F_LIST_LOBBY` on the Friend List
   and `STRING_B_LIST_HOST` on the Black List. The value is settled independently, so the second
   caption is a layout misnomer — but it is exactly the kind of thing that would have "confirmed"
   a wrong reading if a caption had been the only evidence.

### The negative-space caution, restated

Batch 2a's band error is still the cheapest mistake available. This batch avoided ranges entirely:
**find the accessor the UI must go through, count its `bl` sites, and the provenance closes
itself.** Where a thunk really is unused, the proof is `bl` count zero **plus** an unreferenced OPD
descriptor **plus** `ET_EXEC` — all three, because any one alone is only a search result.

And the placeholder rule fired again, in the direction batch 2a should have read it: `"----"`
(disc `"lobby"` string 18) appears in both row painters. A placeholder is always evidence that
something fills the slot.
