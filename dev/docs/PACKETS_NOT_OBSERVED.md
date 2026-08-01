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
| `0x4904` | c2s | game lobby info request variant (one id) | no |
| `0x4908` | c2s | game lobby info request variant (one byte) | no |
| `0x4912` | c2s | game lobby request with id and optional 16-byte name | no |
| `0x491B` | c2s | game lobby request (u4, u2, u1, u4) | no |
| `0x4920` | c2s | game lobby request (u4, u1) | no |
| `0x4923` | c2s | game lobby request (one byte) | no |
| `0x4940` | c2s | game lobby request (one byte) | no |
| `0x4984` | c2s | game lobby request (one u4) | no |
| `0x4986` | c2s | game lobby request (one u4) | no |
| `0x4992` | c2s | game entry info request (one u4) | no |
| `0x49A0` | c2s | game lobby request (one byte from a struct) | no |
| `0x49B0` | c2s | game lobby request (two u4) | no |
| `0x49C2` | c2s | game-lobby / roster request, u32 + small enum | no |
| `0x49C3` | s2c | unmapped 0x49xx reply | no |
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

## What actually needs attention, and it is not this list

Separately from the unobserved set: **29 ids the client sends that we do not handle**, of which
**two are reachable in ordinary play** and are therefore live `FFFFFF60` candidates —

| id | dir | status |
| --- | --- | --- |
| `0x4210` | c2s | own player card / overview request |
| `0x4348` | c2s | unidentified in-match command |

**Both already have real ELF-derived layouts** in `dev/proto/`, so they are implementable now
rather than blocked on research. They are the opposite of this file's contents: known shape,
unknown handling. See `COMMANDS.md`.

### Two rows removed from that table — 2026-08-01, field-mapping batch 5

`0x4394` and `0x43B0` were listed here as reachable. Both were re-derived from the binary and
neither is:

| id | dir | corrected status |
| --- | --- | --- |
| `0x4394` | c2s | **dead code — cannot be sent by this build.** Its builder `0xD41C90` has zero `bl`, zero `b` and zero `bc` entries over the whole executable range `0x10200`..`0xDEBEEC`, its OPD descriptor `0x10295B0` is referenced by no word in the file, `0xD41C8C` is a `blr` so there is no fall-through, and `li r4,17300` at `0xD41D1C` is the only occurrence of the id `0x4394` as an immediate anywhere. The scan was validated on two known-good controls in the same OPD bank (`0x4390`'s builder -> `0x27DC48`, `0x43B0`'s -> `0x2753EC`). It also turns out to carry the **204-byte game-settings block minus `player_count`** — same struct `0x4313` delivers, same canonical reader `0xD4364C`. A handler is optional hardening, not a stall fix |
| `0x43B0` | c2s | **post-launch content, not ordinary play.** It is the **Survival ladder's match-result report**: its record at `session+0x11558` is rendered by screen `0x8CD260` through disc "lobby" strings 756-778 (`Entry into Survival has been canceled.`, `Match #%d has ended… Your reward: %d`, `Your winning streak ends at %d wins.`). Survival lobbies are Ver. 1.10, so a release-day server never reaches the sender; `0x2751A0` additionally gates it on bit `0x400` of `gameObj+0xBCC`. It **does** open wait slot `0x37` (55) and needs a 4-byte `0x43B1` s32 result whenever it is sent, so the handler is cheap insurance for a later version toggle |

Both files now carry full field maps — `0x4394` at 26 unknowns -> 12, `0x43B0` at 5 -> **0**.

## Caveat on the coverage claim

The inbound status column in `PACKETS.md` was verified against the source — 29 `gap` rows, the same
29 ids, no false `served`. **The outbound side was not**: replies go out through helper methods and
list builders, so a constant-reference scan produces around 74 false negatives. `PACKETS.md`'s
`unsent`/`served` values for server->client commands are therefore *unverified*, not confirmed.
