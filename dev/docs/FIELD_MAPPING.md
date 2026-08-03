# Field-mapping campaign: every unknown field in every packet

**Goal: total understanding.** Not "enough to work" — every field named, positioned and explained,
with the evidence in the `.ksy` `doc:` tag so nobody has to re-derive it.

**Scope is every packet, not only the ones we serve.** This was originally "packets the server
actually uses", with the never-observed commands parked in `PACKETS_NOT_OBSERVED.md` and out of
scope. That is no longer the rule: *map now, build later* — post-launch content is fully in scope
for mapping today, and only *serving* it waits for v1 to be finished. See `CLAUDE.md`.

## The number

**Regenerate it — do not quote it from memory.** `python3 dev/tools/field_scoreboard.py` derives
every figure in this document from `dev/proto/` directly, which is why the counts below are
reproducible and the hand-maintained ones above them are not.

**1,735 fields across 317 schemas: 1,441 named, 233 unnamed but explained, 61 bare** (2026-08-03).
Bare was **400** at the start of 2026-08-01 and 182 on 2026-08-02. **Of the 206 ids the server
serves, every one is now fully named or explained — zero bare unknowns in served commands**, a
first for the campaign (2026-08-03 batch: the five unserved-but-1.0 commands `0x3041`/`0x2007`/
`0x4212`/`0x43f5`/`0x4802`, the served tail `0x4221`/`0x3101`, and a vocabulary pass over nine
finished-but-unphrased negatives). The remaining 61 bare fields are all in unserved commands,
overwhelmingly the post-launch `0x49xx`/`0x4Axx`/`0x4Exx` families plus the dead-code `0x4394`.

The full breakdown, the served-command table and the blocks identified along the way are in
**"The scoreboard"** further down; the work-list table immediately below is older and its per-row
counts are hand-maintained, so prefer the scoreboard where they disagree.

## Method, and the rules that keep it honest

1. **Tier 1 or nothing.** A field is only renamed when the binary says what it is: an address, an
   instruction, a destination struct offset. `dev/docs/ADDRESSES.md` has the methodology and the
   PPC64/OPD gotchas.
2. **Positions are already evidence and must not move.** Sizes and offsets in these schemas were
   read from parsers and are load-bearing. Renaming a field and documenting it is the work;
   changing a width is a separate, argued decision.

   **When a batch believes a declared width is wrong, it flags and does not change.** A third,
   independent reading then adjudicates: it gets both readings, is told which is which, derives the
   length itself, and must be able to return *"both are wrong"*. **The third reading decides** — not
   the newer pass, not the more confident one.

   It must also diagnose *what the incorrect reading mistook for the length*. That is not
   bookkeeping: on 2026-08-02 the diagnosis (`stdu` rewrites its base register, so a loop bound is
   an end address rather than a count) converted four fixes into a **closed class** via one sweep,
   and turned up two more wrong schemas in files nobody had flagged. Eight lengths were corrected;
   the two found by sweeping for the cause included the most damaging of them. Details in
   `ADDRESSES.md`.
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
| `0x4313` | s2c | 52 | **12** | game | batch 2b done — 5 named; batch 4b done — count unchanged, but `unknown_48`/`unknown_49` are now proven a **two-element pair** (key 86 bytes 1 and 5, the rest of the record zeroed) with **no create-game widget writing either**, so the wire-watching experiment is ruled out |
| `0x4b21` | s2c | 28 | **9** | clan | batch 2a **partial** — 2 named: `disband_cooldown_s`, `emblem_display_cooldown_s`. batch 4b — the clan-info popup is mapped element by element (`infoC_st-1`..`-13`); `unknown_1b34` is drawn between `T+0xC68` and `member_count`, a second writer at `0x4129F8` is disproved as a stride-16 engine table, and the deciding experiment is written down |
| `0x4b81` | s2c | 18 | **10** | clan | batch 2a **partial** — no renames; all 10 given precise negatives and tier-1 provenance. batch 4b — `unknown_1b34` cross-referenced to `0x4b21`'s popup map |
| `0x4221` | s2c | 17 | **1** | social | batch 5b (2026-08-03) — `unknown_1e` **NAMED `total_rewards`**: "sprite 74" was actually lobby STRING 74 "TOTAL REWARDS", the slot's own label, and feature bit 2 is the GRADE/REWARDS feature (23 sites incl. the "Reward Shop" menu row). `unknown_1c` stays unnamed but its value 3 is proven to **bypass the host's three join gates** (errors 3604/3605/3606, checker `0x8BA1A0`) — live via `0x4101` wire `0x028`, inert here (readers are local-block). batch 4b re-examined `unknown_1e` and deliberately added nothing to the negative, recording the deciding experiment and its two traps instead. batch 3a done — **7 named**: `experience`, `beginner_flag`, `worn_title`, `host_rating_numerator`, `host_rating_denominator`, `clan_emblem_flag`, `grade_points`. The card's whole renderer (`0x905818`) is mapped slot by slot; OBSERVED.md's "the card's LEVEL is `T+0x484`" corrected |
| `0x4310` | c2s | 31 | **7** | game | batch 2b done — 0x0f7 = level_limit_tolerance; `common_c` renamed `common_flags_lsb`; the four echo-only negatives re-established independently |
| `0x4120` | s2c | 27 | **2** | connect | batch 2c done — 5 named (`dead_settings_05`, `entry_id_0..3`); byte 0 bit 0 proven **load-bearing** |
| `0x4305` | s2c | 33 | **7** | game | batch 2b done — all 7 carry tier-1 provenance; 4 stale tier-4 labels corrected. batch 4b — `unknown_0d6`/`unknown_0d7` shown to be **one two-element publication**, with a complete 15-site census of displacement `+801` proving the only sites that reach this struct are the two parsers, the `0x4310` builder, the publisher and a dead accessor |
| `0x4b54` | s2c | 11 | **2** | clan | batch 2a-redo done — 3 more named (`lobby_name`, `game_id`, `game_name`) and **three false negatives corrected**; `unknown_30` proven live and feature-bit-2 gated; `unknown_18`'s negative re-run on the corrected band |
| `0x4991` | s2c | 14 | **6** | lobby | open |
| `0x4101` | s2c | 13 | **1** | connect | batch 2c done — 4 named. batch 4b — `unknown_028` is a **4-bit enum read by four predicate thunks** (`0x9BEB88`/`0x9BEBE0`/`0x9BFFF0`/`0x9C0050`, all `(blob[350] & 0xF) == 2 or 3`) with 18 call sites in the HUD; nibble 3 shares a branch with the training-instructor predicate. Still unnamed; the deciding experiment is now a four-value fingerprint |
| `0x4582` | s2c | 8 | **0** | social | batch 3b done — **all five named**: `lobby_id`, `lobby_name`, `game_id`, `game_name`, `lobby_type`; the tail is a location block, proven by a consumer-code bijection with `0x4b54`. The `0x4583` filter is real but **inert** — its destination list has no reader anywhere in the image |
| `0x4602` | s2c | 8 | **0** | social | batch 3b done — **all five named**, same block. `SocialGameController`'s open question is **CONFIRMED**: current lobby name and current game name, plus a lobby **id** (not level/rank) and a lobby **type** enum (not a lobby id) |
| `0x4302` | s2c | 21 | **0** | game | batch 2b done — **all four named**: lobby_subtype, round_flags, selector_flags, selector_tiebreak |
| `0x4b12` | s2c | 10 | **0** | clan | batch 2a-redo done — **all four named**: `row_display_flag`, `discarded_29`, `discarded_2a`, `dead_2b`; two are provable parser-level discards |
| `0x4b75` | s2c | 7 | **4** | clan | batch 2a-redo done — consumer screen found. batch 4b — the screen's element table is resolved (5 columns x 4 rows, `STRING_low*`), which **corrects "four columns" to five** and caps the list at 4 rows; the two integers land in `STRING_low_N_3`/`_4`, positional names, so the ELF is exhausted and the caption binding is in the layout file |
| `0x4129` | s2c | 18 | **0** | connect | batch 2c done — **all three named**; `play_time_seconds` drives the MGS4 single-player unlock |
| `0x4105` | s2c | 21 | **2** | stats | batch 1 done — cols 13/15 have **no reader in the image**; both docs now carry the scan that establishes it |
| `0x4122` | s2c | 17 | **2** | connect | batch 2c done — no new tier-1 name available; both negatives independently re-run |
| `0x4902` | s2c | 12 | **0** | lobby | batch 4b done — **both named**: `dead_05` (closed-provenance negative: 6 base computations, 12+3 consumer sites, all enumerated) and `subtype5_row_gate` (one reader, `0x8904F0`, must equal 3 or the Official Tournament row is never emitted) |
| `0x3101` | c2s | 26 | **1** | other | batch 5b (2026-08-03) — **the withheld negative is now stated**: the second writer was found (the create screen's own state machine `0x88CD2C` writes voice/pitch/face; `0x888B28` is a third editor-field writer) and the staging struct's write set is closed with the aliasing hole shut — **nothing writes `createScreen+136`**, so the u32 is a constant zero or uninitialised heap (allocator not statically decidable); log it live. Bonus: `gender` is never written by the create screen either, wire `voice` = menu index + 7 (valid 7..15), and the validator `0x93E008`'s item-id ranges confirm the whole field order a third time. batch 4a — buffer located (`createScreen+136`, 48-byte payload at `screen+108`); the negative was withheld pending the second writer |
| `0x3041` | s2c | 4 | **0** | other | batch 5b (2026-08-03) done — **both named**: `chara_id` and `name` (profile+0/+4, the slots `0x4101` fills; the name confirmed by its one live reader `0x8E1C28`, a UI-text helper). Subsystem identified: **activate character by slot**, and the `0x3040` builder is **dead code** (zero callers, eight controls) — the exchange is unreachable on this build, so the mapping is terminal |
| `0x2007` | s2c | 1 | **1** | other | batch 5b (2026-08-03) done — `unknown_00` fully explained: a nullable u32 in a 64-bit slot at `session+0xDD8`, init −1, **no reader** (sole typed accessor `0xD35FDC` has zero callers; displacement-3544 enumeration closed at 21 lines image-wide). The whole `0x2006`/`0x2007` exchange is dead code; reply pairing (wait slot 11) is tier-1 |
| `0x4130` | c2s | 23 | **0** | other | batch 4a done — `echoed_from_4131_60`: struct is `profile+7648`, written only by the `0x4131` parser (`0xD3F0F4`), and the client's own change detector provably skips it |
| `0x4150` | c2s | 1 | **0** | other | batch 4a done — `always_zero`: **hardcoded 0 at all four callers**, entry set closed by the three-part test. Retires the "lobby subtype" candidate |
| `0x4316` | c2s | 1 | **0** | other | batch 4a done — `lobby_subtype`, by instruction-for-instruction identity with `0x4310`'s. No capture needed after all |
| `0x4344` | c2s | 2 | **0** | other | batch 4a done — `team`, raw roster `entry+1`; can carry 0/2/254 where `0x4440`'s cannot |
| `0x4390` | c2s | 81 | **1** | other | batch 4a — reviewed, nothing to add: `unknown_b14` already carries a complete "identically zero on this build" derivation |
| `0x43a6` | c2s | 1 | **1** | other | batch 4a — reviewed, nothing to add: provenance already PROVED (record field 332 via `0x27F160`) |
| `0x43c0` | c2s | 5 | **0** | other | batch 4a done — `host_stance`: `settings+0x34E` **is** `0x4310`'s `src+846`, and four other fields already pin the struct identity |
| `0x43c4` | c2s | 1 | **1** | other | open |
| `0x43c8` | c2s | 2 | **1** | other | batch 4a — reviewed, nothing to add: `unknown_04` is deliberately unrenamed pending the stated confirming observation |
| `0x4440` | c2s | 1 | **0** | other | batch 4a done — `team` (1-based, only 1 or 2); sole caller `0xCA031C`, from record field 1, whose writers are the auto-balancer `0x6EB4F0` and the `254` sentinel |
| `0x4700` | c2s | 4 | **1** | other | open |
| `0x4800` | c2s | 6 | **0** | other | batch 3c done — `echoed_flag_273` named by struct bijection; the whole compose buffer proved to be a `0x4822` mail record |
| `0x4b10` | c2s | 3 | **0** | other | batch 4a done — `always_one`: the dispatcher's arm is **opcode 8, which no thunk sets**, so the paging path is the only sender and it hardcodes 1 |
| `0x4b46` | c2s | 1 | **0** | other | batch 4a done — `notification_clear_mask`, the `profile+6838` word drained back; **the OPD dead end was wrong** — `0xA7DC48` has 20 `b` tail calls |
| `0x4b70` | c2s | 1 | **0** | other | batch 2a-redo done — `clan_id`, from the binary rather than a capture |
| `0x2002` | s2c | 1 | **0** | other | batch 4b done — `dead_body`: **neither a result code nor a count**, `READ_BEGIN`/`READ_END` back to back with no read primitive between. The contrast case is `0x4901`, which reads one u32 with `lwa` and refuses to open the list when it is nonzero — a result code, provably not a count |
| `0x2004` | s2c | 1 | **0** | other | batch 4b done — `dead_body`, same proof; `0x4903` is its reading sibling |
| `0x3049` | s2c | 14 | **0** | other | batch 4b done — `dead_1e`: no reader, by closed provenance. One base computation for the entry array, five for the header, 11 `bl` on the accessor, 13 on `GetCharaEntry`, all enumerated; `GetSelectedCharaEntry` `0x906E6C` is a **dead accessor** (zero `bl`, unreferenced OPD, `ET_EXEC`) |
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

## What batch 4a established (the client-to-server fields)

**8 of 15 fields named, 7 packets to zero** — `0x4130`, `0x4150`, `0x4316`, `0x4344`, `0x43c0`,
`0x4440`, `0x4b10`, `0x4b46`. Every one of them had survived three earlier batches, and the reason
is a single method error worth stating before the results.

### Every previous batch hunted for READERS. On a c2s field that is the wrong question.

For a server-to-client field, "who consumes this?" is the right question and the whole campaign is
built on it. **For a client-to-server field there is no reader in the image at all — we are the
reader.** The client is the *writer*. So the searches that had been run on these fourteen schemas
could not have succeeded, and their failure was never evidence about the fields.

The question that works is: **what does the builder store, and where did that value come from?**
Find the sender, find the store into the payload offset, walk backwards to a widget, a struct
field, a menu selection or an immediate. And an immediate is a *complete* answer — `0x4150` and
`0x4b10` are finished packets now, and neither field has a meaning.

### The levers, in order of what they bought

| lever | what it bought |
| --- | --- |
| **the sender's callers, with `li rN,K` read off the same basic block** | `0x4150`'s byte is `0` at all four call sites and `0x4440`'s is `(field1 == 1) ? 2 : 1`. Two packets closed by reading four instructions above a `bl` |
| **struct-offset identity across two builders** | `0x43C0`'s `settings+0x34E` is `846`, and `0x4310`'s `host_stance` is `src+846`. Four other fields (name +4, comment +0x15, password flag +150, password +151) already pin the two structs as one, so this is rule 4's legitimate form, not a guess from position |
| **the same computation, instruction for instruction** | `0x4316`'s byte and `0x4310`'s `lobby_subtype` run the identical seven-step sequence — `= 1`, `if (0xD4908C) if ((b = 0xD491F8)) = b[608]`, `if (0xD5BDA0) = 2`. The capture this file asked for could only ever have confirmed what the code forces |
| **the setter, not the getter** | `0x4344`/`0x4440` both carry character-record field 1. Nothing *reads* it usefully; what names it is its three writers — the auto-balance picker `0x6EB4F0` (per-team counters at `game[1360+t*4+8]`, LCG tiebreak), a `li r4,2` third role, and eleven `li r4,254` "no team" sentinels |
| **the accessor bank as a field map** | `0x4112`'s 32-byte `memcpy` body is `profile+6777`, and its first eight bytes have **sixteen getter/setter pairs, one per nibble** (`0x906BE8`-`0x906E24`). The serialiser gave no boundaries; the accessors give sixteen |
| **the client's own change detector** | `0x93E5B4`-`0x93E720` enumerates every offset the personal-info screen can edit and skips `+60`. A field excluded from the editor's equality test is a field the editor does not own — which is what made `0x4130`'s byte a proven echo |

### The correction that matters most: `b` is a call too

`mgo2_cmd_4b10_c2s.ksy` and `mgo2_cmd_4b46_c2s.ksy` both recorded the same dead end — the generic
clan request dispatcher `0xA7DC48` has **no `bl` site**, and its OPD descriptor at `0x10202D8` is
referenced by no data word in an `ET_EXEC` image, so it must be entered by indexing an OPD table.

**The OPD half is right. The conclusion is wrong. `0xA7DC48` is entered by twenty tail calls,
`b 0xa7dc48`, from a thunk bank at `0xA7E9B0`-`0xA7EBC4`**, each setting an opcode as an immediate.
A tail-called function has no `bl` site *by construction*, and a bank of one-line wrappers is the
normal shape that produces one. The bank was three greps away the whole time.

Two results fell straight out:

1. **`0x4b46`'s u16 is `notification_clear_mask`.** Opcode 12's thunk is `0xA7EAD8(x, y)` and `y`
   is the wire value; its call sites pass `li r4,256` (bit 8) literally, or
   `(ctx[100] | *(u16*)(profile+6838)) & ~ctx[104]`. `profile+6838` is exactly where `0x4b47`'s
   privilege word lands, so the client is handing back the notification bits it wants cleared —
   which is the same "drain to zero" behaviour that file's own "the privilege word must be zero"
   section had already characterised from the other end.
2. **`0x4b10`'s byte is `always_one`, now provably.** Its dispatcher arm is opcode **8**, and the
   twenty thunks set 3, 4, 9, 10, 11, 12, 15-24 — never 8. The arm is unreachable, so the paging
   path is the only sender, and it hardcodes 1 at all three branches of its switch.

The same test retires `0x4112`'s dispatcher call site (arm 13, also unset) as dead code.

### The negative that was withheld, and why

`0x3101`'s `unknown_09` got a located buffer (`createScreen+136`) and a complete enumeration of the
appearance editor's write set — offsets 18-23 and 32-45, from all 25 `lwz rX,312(rY)` sites — which
does **not** include it. That looks like a precise negative and was not published as one.

**The check that stopped it: the same sweep also finds no writer for `gender`, `voice` and
`pitch`, three fields in the same buffer that are certainly set.** So a second writer path exists
and has not been found, and a sweep with three known false negatives cannot be trusted on a
fourth. This is batch 2a's band error in a new costume — not a range whose edge fell short, but a
*path* the method could not see — and the cheap defence is the same one: before trusting a
negative, run it against a field in the same struct whose answer you already know.

### Hardcoded constants, i.e. what the server may safely ignore

* **`0x4150` byte 0 — always `0`.** `li r4,0` at `0x891870`, `0x891900`, `0x8981C8`, `0x8BCF44`.
* **`0x4b10` byte 5 — always `1`.** `li r5,1` at `0xAC1C54` and `0xAC2B4C`, all switch arms.
* **`0x4b46` u16 — always `0000` while we send a zero privilege word**, not by hardcoding but
  structurally: the client can only hand back bits we gave it.

The first two are closed by the three-part entry test — zero `bl` sites beyond those enumerated,
an unreferenced OPD descriptor, and `ET_EXEC` with no relocations — plus, new in this batch, a
check for `b <target>` tail calls. **All four, from now on.**

### One width flagged, not changed

`0x4344`'s `team` and `0x4440`'s `team` are the same character-record field and are **not**
interchangeable: `0x4344` sends the raw slot (`lbz r5,1(entry)`, so `0`, `1`, `2` or `254` are all
reachable) while `0x4440` sends `(v == 1) ? 2 : 1`, which is 1-based and collapses everything else
onto `1`. Both widths are correct as written. The trap is that the same admin action — host
Restart — fires both.

## The scoreboard, as of 2026-08-02

Regenerate with `python3 dev/tools/field_scoreboard.py` from the repo root, so the number is
reproducible rather than re-counted by hand. It classifies every `- id:` in `dev/proto/`: named vs
`unknown_*`, and for unnamed fields whether the `doc:` carries a **stated negative** (a swept range,
"no reader", "no live consumer", "dead accessor", "no caller", "moot").

**1,731 fields across 317 schemas.** 1,360 named (78.6%); 189 unnamed but explained; **182 bare** —
down from 400 at the start of 2026-08-01.

| | commands |
| --- | ---: |
| Fully named | 220 |
| Every field named or explained | 24 |
| Empty payload — nothing to map | 23 |
| Still carrying bare unknowns | 48 |

Of the **206 ids the server actually serves**, 179 are fully named or explained and 13 have empty
payloads. **Fourteen carry bare unknowns, 36 fields in total:**

| bare | id |
| ---: | --- |
| 9 | `0x4b21` |
| 7 | `0x4860` |
| 6 | `0x4686` |
| 3 | `0x4b75` |
| 2 | `0x4221` |
| 1 | `0x4b81`, `0x43f4`, `0x43c8`, `0x43a6`, `0x4310`, `0x4131`, `0x4122`, `0x4107`, `0x3101` |

`0x4103` and `0x43f1`, which between them held 27 of the 67 bare fields this list started with, are
now clear.

### What "in scope" means here — map now, build later

**Mapping scope is everything**, post-launch content included; that is the current goal. **Build
scope is v1 only.** The two are separate decisions and only the second is gated on the release-day
rule — see `CLAUDE.md`. A family being Ver. 1.10 / 1.20 content is a reason not to *serve* it, never
a reason not to *map* it.

The one real consequence is evidential, not scoping: **no available client build exercises the
post-launch commands**, so those mappings are tier 1 and cannot reach tier 2. Every schema in the
`0x49xx` and `0x4Axx` families now says so rather than leaving a reader to assume a capture backs
them.

**And a current feature served wrongly is a bug, not deferred work.** When a batch names a field the
server already sends, it checks what we send against what the field now means and states which of
three it is: right (say so, so it is not rechecked), wrong and live (**fix in the same batch**), or
wrong but inert (record the hazard *and* the evidence for why it is inert). That rule has fired once
so far — `0x43F1`'s wire `0x09` had been announcing Deathmatch for every automatch.

### Blocks identified during the campaign

| block | was | is |
| --- | --- | --- |
| `0x49xx` | "clan / GHQ / roster" | **team / tournament / survival** — the 680-byte record at `session+0xD928` is a team; a clan is a separate object it references through one flag bit |
| `0x4Axx` | "a whole unidentified subsystem" | **tournament / survival events** — the 7296-byte record at `session+0xDBD0`, holding a 128-entrant table, per-round bitmaps and standings |
| `0x4905`/`0x4909` | two commands | **one packet**, the tournament detail card, 867 wire bytes into one 912-byte record |

Three adjacent records, and their arithmetic is worth keeping in one place because it is what stops
the next cross-struct inference going wrong:

```
session+0xD598  tournament detail   912 bytes   getter 0xD47478
session+0xD928  team record         680 bytes   getter 0xD491F8     (0xD598 + 912 = 0xD928)
session+0xDBD0  event record       7296 bytes   getter 0xD4EA60     (0xD928 + 0x2A8 = 0xDBD0)
```

Adjacent, disjoint, separately owned. **Check which getter feeds a reader before attributing an
offset** — reading one instance as a different *kind* of object is what produced this campaign's
team-vs-clan misidentification, and "same layout, different instance" has now turned up four times
(`0x4A24`/`0x4A31`, `0x4A11`/`0x4A33`, `0x4985`/`0x49B1`, and the team pair itself).

### Settled 2026-08-01: `session+0xD928` is the TEAM record

Two batches traced this address the same day and gave it different nouns — one calling it the team
record, the other the my-clan cache. Both readings were committed. An adjudication pass settled it:
**it is the team record.** The first batch had the right noun; the second was right about every
mechanical detail and wrong about the label.

**What actually caused the disagreement: one struct type, two instances.** The filler is a shared,
id-dispatched parser at `0xD4AF34(session, cmdId, *out)` which `memset`s 680 bytes and runs the
same field-by-field parse for either destination:

* `0x4911`, `0x4913`, `0x49A1`, `0x4987` → `session + 0xD928` — **my** team. Its getter `0xD491F8`
  has 83 callers across the team screens.
* `0x4985`, `0x49B1` → `[session+0x11904] + 0x1A598` — the team being **viewed or joined**. Its
  getter `0xD491C8` is called only from the browse screens at `0x8C6C`–`0x8C9F`.

So `0x4985` never writes `0xD928`; it writes a second instance of the identical struct. Reading one
instance as a different *kind* of object is the trap, and it is worth remembering as a general
hazard: **two instances of one type look exactly like two types until you find the shared parser.**

Three independent tier-1 lines agree on the noun:

1. **The parser dispatch** above — the same layout, the same memset, four commands filling *my*
   instance.
2. **The client's own sentence.** The gate `0xD4908C` failing yields **−1007**, which `0x8C25C8`
   maps to dialog 5170: *"You have already left the team. / Unable to leave team."*
3. **Disjoint error bands.** Everything this object produces is **−10xx** (−1004, −1006, −1007,
   −1012, −1014, −1018, −1035); `ERRORS.md` shows clan operations use **−12xx** (−1202 "You are not
   a clan member", −1203 "You are not clan leader", −1207, −1230). Clean discriminator, lands on
   team.

The layout is a roster and not a member list: `+0x17C` is 8 × 28 bytes, the loop bound is
`cmpwi cr6,r26,7` — hardcoded 8 — and `0xD4DC18` compares slot 0's id against my own character
record, failing **−1014**. That is inside `0x4940`'s sender, so the leader gate is confirmed.

Teams and clans coexist, and the link is a single bit: `team+0x94` bit `0x40` is the clan
affiliation, read at `0x8C20A8` and passed to the `0x491C` sender, whose replies map the *clan*-band
codes −1230 and −1202. Disc strings 14150 "Set Clan Affiliation" and 14214 "This will affiliate the
team with the team leader’s clan" sit contiguously with 14226 tournament-entry and 14232
Survival-entry confirmations.

**The block is split, but not where the hypothesis put it.** It is not `0x49[0-4]x` versus
`0x49[8-C]x` — both drive the same object, and there is no clan subsystem anywhere in `0x49xx`. The
real boundary is at the **low** end: the senders for `0x4904` (`0xD47B6C`), `0x4908` (`0xD47D9C`)
and `0x4992` (`0xD479A8`) live in the `0xD477xx`–`0xD48Dxx` lobby/entry block, take a single u32,
and touch neither `0xD928` nor any leader gate. The first instruction anywhere forming
`session+0xD928` is at `0xD49208`.

Sweep behind that: every occurrence of `-9944` in the cached disassembly, 26 hits, each checked for
a preceding `addis …,1`; the only two outside `0xD49208`–`0xD4DC0C` are the gate itself
(`0xD490A0`) and an unrelated `sth` at `0xE46AC4`. **Control that succeeded:** the same sweep finds
`0xD49380`, the 680-byte `memset` clear — which any correct sweep must contain.

**Scope consequence, which is the reason this mattered.** The `0x49xx` family is
team/tournament/survival throughout — **Ver. 1.10 / 1.20 content, so not served in v1** under the
target-version rule, though fully in scope for mapping now (see the scope note above). In
particular `0x49C2`/`0x49C3` are **join team**, not a clan operation, so they are not a
ready-to-ship pair as an earlier note claimed — that was a build claim, and it was wrong. Their
layout is nonetheless mapped and stays mapped.

Still open, at medium confidence: that the second instance is specifically the *browse/join target*
rests on caller locality rather than a resolved string. Resolving the disc strings at `0x8C6CD0` and
`0x8C9568` would settle it.

