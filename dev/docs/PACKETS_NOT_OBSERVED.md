# Packets we have never seen, and cannot yet describe

**Parked deliberately.** These are the commands where we know neither the byte layout nor whether
the client ever sends or receives them. Nothing here is blocking: none is reachable in ordinary
play, so none can stall a client today. Recorded so the set is a known quantity to come back to,
rather than something to re-derive.

Counted 2026-07-30 over `dev/proto/`, cross-checked against `PACKETS.md`, `COMMANDS.md` and the
server source.

## Method, so the number is reproducible

- **"No field mapping"** — the schema's `seq` has at least one field and **every** field name matches
  `^unknown`. That is the repo's own convention (`dev/proto/README.md`: an `[UNKNOWN]` field must be
  named `unknown_<off>`), so it is mechanical rather than a judgement call.
  **`seq: []` is excluded** — that is a *positively established* empty payload, a result rather than
  a blank.
- **"Never observed"** — no `[CONFIRMED]` tag and no positive capture prose in the schema. Beware
  the phrase *"never observed live"*, which a naive `observed live` match counts as a sighting; it
  needs a negative lookbehind.

**32 files** are unmapped; **192 of 315** are unobserved; the intersection is **29**. Three ids are
unmapped but *have* been seen — `0x4112`, `0x43C4`, `0x4B46` — which is why 32 and 29 differ.

Of the 29, ten are explainable, leaving **19 genuine unknowns**.

## The 19 — neither shape nor usage known

| id | dir | what the schema calls it | answered |
| --- | --- | --- | --- |
| `0x2007` | s2c | gate reply, single u32 | no |
| `0x43F0` | s2c | server -> client: in-match subsystem push (UNSOLICITED, no result field) | no |
| `0x4904` | c2s | **event/official-match detail request by id** (`detail_id` u4, echoed at `0x4905+0x04` or the reply is discarded). Sender `0xD47B6C`, in the lobby/entry block — touches no team state | no |
| `0x4908` | c2s | one-byte sibling of `0x4904`, same 912-byte destination. **Dead sender** — `0xD47D9C` has no caller | no |
| `0x4912` | c2s | **join a team**: `team_id` u4 + `password` str[16]. Password sent only when the browsed team's `record+0x94` bit `0x80` ("Password Lock", disc string 665) is set; all-zero otherwise, payload always 20. Gate: already in a team -> **-1004** | no |
| `0x491B` | c2s | **enter play with the current team**: own `team_id` (else **-1018**), team record serial, `entry_mode` (0 = tournament confirm, 1 = reconnect), plus `team_field_0x268` | no |
| `0x4920` | c2s | leader-only team command, u32 + u8, bare-ack reply `0x4921`. **Dead sender** — no caller, so its fields stay unnamed. Candidate but unproven: disc strings 692 "Disband Team" / 693 "Accept Entry" have no matched id | no |
| `0x4923` | c2s | **set/clear the team's clan affiliation**, leader only. `clan_affiliation` u1 hard-gated to 0/1 (else **-24**); setting 1 also needs a non-zero word in the local player object (**-1035**) | no |
| `0x4940` | c2s | **kick a team member by roster slot**, leader only. `member_slot` u1, 0..7; caller resolves the slot by scanning the 8x28-byte roster and never puts 0xFF on the wire. Slot state at `member+0x15` must be 1 or 2 (else **-1012**) | no |
| `0x4984` | c2s | **fetch a team record by id** -> `0x4985` (slot 63). The sent word is stashed at `ctx+0x26CFC` and the reply is rejected unless its leading id echoes it | no |
| `0x4986` | c2s | u4 taken from `record[0]+40` of the `0x4991` table -> `0x4987` (slot 72). **Not** echo-checked, unlike `0x4984`. Also pre-clears slot 86; serve `0x4987` with `+664 == 0` or it arms 86 instead of completing 72 | no |
| `0x4992` | c2s | **withdraw entry by key** -> `0x4993` (slot 71), which zeroes the matching 72-byte record in the 4-record table at `ctx+0x1DAA8`. Sender `0xD479A8` is in the lobby/entry block, not the team block | no |
| `0x49A0` | c2s | one byte = team record `+608` = wire 360 of the shared 420-byte record — the same field `0x4910` sends. Meaning of the field itself still open | no |
| `0x49B0` | c2s | `team_id` (same `ctx+0x26CFC` echo check) + a second u32 that is **unresolved**: swept `0xD4A458`-`0xD4A574`, spilled once and serialised, never compared or stored, and the sender has no caller | no |
| `0x49C2` | c2s | **join team / answer a pending `0x49C1` invitation**: `entry_id` (non-zero enforced) + `answer` range-checked 1..4, over the 3-entry 44-byte table at `session+0x117F8`. Gated on **not** already being in a team (**-1004**) | no |
| `0x49C3` | s2c | reply to `0x49C2` (slot 76). **Leading integer is a RESULT CODE, not a count**, and the match key is the **second** field — the two were previously documented swapped. All three fields are read before the result is tested, so an error reply must still carry all three | no |
| `0x4A03` | s2c | unmapped 0x4Axx reply, word plus four halves | no |
| `0x4A30` | c2s | unidentified subsystem, single u32 | no |
| `0x4A47` | s2c | unmapped 0x4Axx reply, parsed inline in the dispatcher | no |

**They are one subsystem, not a scatter.** Every id is in `0x49xx`/`0x4Axx` — the game-lobby /
roster / GHQ family — except `0x2007` and `0x43F0`. Whatever that subsystem is, we have never
modelled any of it, which is consistent with never having seen any of it.

## Ten that are counted but explainable

### Five whose purpose is known, bytes are not — and all are answered

| id | dir | what the schema calls it | answered |
| --- | --- | --- | --- |
| `0x4150` | c2s | lobby disconnect | yes |
| `0x4316` | c2s | create game | yes |
| `0x43A6` | c2s | in-match single-id command | yes |
| `0x4440` | c2s | team / spectator change | yes |
| `0x4B70` | c2s | clan statistics request | yes |

These are served with a bare acknowledgement. The reply is correct; the request's fields are simply
undescribed, which costs nothing until we need to read one.

### Five that are a schema-convention defect, not a gap

| id | dir | what the schema calls it | answered |
| --- | --- | --- | --- |
| `0x2002` | s2c | lobby-list start | n/a |
| `0x2004` | s2c | lobby-list end | n/a |
| `0x43F4` | s2c | unidentified in-match notification, EMPTY payload | n/a |
| `0x43F5` | s2c | unidentified in-match notification, EMPTY payload | n/a |
| `0x4802` | s2c | mail-send notification, EMPTY payload | n/a |

**These are not unmapped.** Each one's prose says the client opens no reader and parses nothing of
the payload — a *positive* ELF result — but the tree had no way to express that, so they use the
all-`unknown_body` form, which reads as the opposite. `PACKETS.md` already gives them their own
`unread` legend entry, and `dev/proto/README.md` now defines the form. Re-tagging them would take
the mechanical count from 29 to 24.

## What actually needs attention — as of batch 6, nothing on this axis

Separately from the unobserved set there are **29 ids the client sends that we do not handle**.
Four of them were listed here as reachable in ordinary play and therefore live `FFFFFF60`
candidates. **All four have now been re-derived from the binary and none of them is reachable.**
Batch 5 removed `0x4394` and `0x43B0`; batch 6 removes the last two.

| id | dir | corrected status |
| --- | --- | --- |
| `0x4210` | c2s | **dead code — cannot be sent by this build [2026-08-01, batch 6].** Sender entry `0xD3A76C` (not `0xD3A7D4`, which is the `li r4,0x4210` inside it) has zero `bl`, zero `b` and zero `bc` entries over every executable byte in the image, OPD `0x10291E0` is referenced by no word and no `addi`/`ori` materialises it, `0xD3A768` is a `blr` so there is no fall-through, and that `li` is the only `li r4,16912` anywhere. **And the reply triple's storage has no reader**: the `T+0x3330` list's three accessors `0xD3A0CC`/`0xD3F514`/`0xD3F568` have zero callers each, against six for the identical `0x4682` bank at `T+0x26d14`. A handler is optional insurance, not a stall fix |
| `0x4348` | c2s | **dead code — cannot be sent by this build [2026-08-01, batch 6].** Sender `0xD4A834`: zero `bl`/`b`/`bc` image-wide, OPD `0x1029B38` unreferenced, `0xD4A830` is a `blr`, and `li r4,0x4348` at `0xD4A89C` is the only one. **`0x4349`'s 680-byte destination struct at `ctx+0x10000-19228` also has no reader** — its sole accessor `0xD490B8` has zero callers and all 150 sites in `.text` with a displacement inside that window belong to unrelated bases or are switch-index normalisations. mgo2-server's "host pass" name stays tier 4 and unadopted; the parser reads a name plus a 128-byte comment, which is not a host-transfer ack |

The batch-6 scan is validated the way batch 5's was, but broader: it was run over the **whole
command-id sender bank** at `0xD38000`-`0xD60000` — 116 `li r4,<id>` sites walked back to their
function entries — and it resolves callers for **105** of them, including the immediate
neighbours of both dead functions (`0x4132`'s `0xD3A844`, `0x4220`'s `0xD3B950`, `0x4914`'s
`0xD4A75C`, `0x4986`'s `0xD4A90C`). A sweep that finds 105 and misses these is evidence. The `bc`
decoder was separately validated against two known in-function branch targets.

**All four still have real ELF-derived layouts** in `dev/proto/`, so handlers remain cheap to
write if a later version toggle ever reaches a sender. None of them is a release-day stall.

### Two more leave the sendable set — 2026-08-03: `0x3040` and `0x2006` (29 becomes 27)

Same failure mode as `0x4394`/`0x4210`/`0x4348`: a builder body that exists was read as "can be
sent". Both scans follow the batch-5/6 method and were control-validated in their own OPD banks.

| id | dir | corrected status |
| --- | --- | --- |
| `0x3040` | c2s | **dead code — cannot be sent by this build [2026-08-03].** Sender entry `0xD37B00` (not `0xD37B6C`, the `li r4,0x3040` inside it): zero `bl`/`b`/`bc` image-wide, OPD `0x1029008` referenced by no word, no constant formation of either address; eight live controls in the same bank resolve (0x3105 -> 1, 0x3103 -> 1, 0x3048 -> 3, 0x3107 -> 1, 0x3101 -> 1, plus 0xD36FF8 -> 8, 0xD37024 -> 1, 0xD378EC -> 7). Independently, wait slot 13 is armed at exactly one site in the image — inside the dead builder. The command is now identified anyway: **activate character by slot (0..7)**, reply `0x3041` = `{result; chara_id; name[16]}` into the live profile — both reply fields are now tier-1 named. See both `.ksy` files |
| `0x2006` | c2s | **dead code — cannot be sent by this build [2026-08-03].** Sender `0xD36900` (the unique `li r4,8198` site): zero callers, against exactly one each for its byte-identical siblings `0x2005` (`0xD369D0`, from `0x94633C`) and `0x2008` (`0xD3681C`, from `0x90F044`). The slot-11 waiter `0xD360F4` also has zero callers while its slot-10/12 neighbours have one each, and the reply value's only typed reader `0xD35FDC` is equally dead. Reply pairing is settled tier-1 regardless: `0x2006` opens wait slot 11, `0x2007`'s parser arm is its unique closer |

`0x4394` and `0x43B0` were listed here as reachable. Both were re-derived from the binary and
neither is:

| id | dir | corrected status |
| --- | --- | --- |
| `0x4394` | c2s | **dead code — cannot be sent by this build.** Its builder `0xD41C90` has zero `bl`, zero `b` and zero `bc` entries over the whole executable range `0x10200`..`0xDEBEEC`, its OPD descriptor `0x10295B0` is referenced by no word in the file, `0xD41C8C` is a `blr` so there is no fall-through, and `li r4,17300` at `0xD41D1C` is the only occurrence of the id `0x4394` as an immediate anywhere. The scan was validated on two known-good controls in the same OPD bank (`0x4390`'s builder -> `0x27DC48`, `0x43B0`'s -> `0x2753EC`). It also turns out to carry the **204-byte game-settings block minus `player_count`** — same struct `0x4313` delivers, same canonical reader `0xD4364C`. A handler is optional hardening, not a stall fix |
| `0x43B0` | c2s | **post-launch content, not ordinary play.** It is the **Survival ladder's match-result report**: its record at `session+0x11558` is rendered by screen `0x8CD260` through disc "lobby" strings 756-778 (`Entry into Survival has been canceled.`, `Match #%d has ended… Your reward: %d`, `Your winning streak ends at %d wins.`). Survival lobbies are Ver. 1.10, so a release-day server never reaches the sender; `0x2751A0` additionally gates it on bit `0x400` of `gameObj+0xBCC` — and [2026-08-03] that gate is **not Survival-specific**: the single setter `0x272728` fires for lobby subtype 3..6 (excluding 2, automatching) and sets bits 8, 9 and 10 in one `ori r0,r0,1792`, so bit 10 (`0x43B0`'s gate) and bit 9 (`0x43F0`'s gate) are inseparable. It **does** open wait slot `0x37` (55) and needs a 4-byte `0x43B1` s32 result whenever it is sent, so the handler is cheap insurance for a later version toggle |

Both files now carry full field maps — `0x4394` at 26 unknowns -> 12, `0x43B0` at 5 -> **0**.

## Caveat on the coverage claim

The inbound status column in `PACKETS.md` was verified against the source — 29 `gap` rows, the same
29 ids, no false `served`. **The outbound side was not**: replies go out through helper methods and
list builders, so a constant-reference scan produces around 74 false negatives. `PACKETS.md`'s
`unsent`/`served` values for server->client commands are therefore *unverified*, not confirmed.
