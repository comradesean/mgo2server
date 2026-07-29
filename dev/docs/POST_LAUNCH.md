# Post-launch content, and candidates for version toggles

**This file is for things we deliberately do not serve, because they were not active on release
day — plus findings that only make sense as later-version features.** It is not a to-do list;
`BACKLOG.md` holds deferred *work*. This holds deferred *content*, and the evidence needed to
switch each piece on behind a toggle when the time comes.

## The rule this file exists to enforce

From `CLAUDE.md`: **the first release of `mgo2server` serves RELEASE-DAY MGO2 only.**

*Shipped on the disc* and *active on release day* are different questions, and **only the first is
readable from our artifacts.** The disc tells you what content exists; it cannot tell you what
Konami had enabled. So a mode's or a field's presence in the binary is never on its own a reason to
serve it.

Researching any of this is encouraged — knowing *how* something is gated is what makes a toggle
designable. Enabling it is the part that waits.

### How to record an entry here

Each entry should answer four questions, and say plainly which of them it cannot:

1. **What is it**, in the player's terms.
2. **Where is the gate** — the ELF address, wire field or disc resource that decides.
3. **Is it ours to open?** Some gates are server-supplied (we send a byte); some are client-local
   and no server can reach them; some do not exist in this build at all.
4. **What is the evidence tier** for "post-launch"? Dates from community/patch-note knowledge are
   tier-4-ish and should say so. The binary can rarely settle it.

---

## Known post-launch modes

Carried from `CLAUDE.md`. Dates are community/patch-note knowledge — **not read from the binary**,
so the boundary itself carries that tier.

| content | when | status |
| --- | --- | --- |
| **Team Sneaking** (rule 7) | 2008-07-04, three weeks after the 2008-06-12 launch, reportedly by server-side maintenance | fully present on the disc; deliberately not served. The feature bit is ours to open — see `GATES.md` |
| **BOMB Mission** | roughly 2009-01-27 | not served |
| **Survival** lobbies | Ver. 1.10 | lobby subtype 4 is named in the disc resources (`LOBBIES.md`) |
| **Tournament** lobbies | Ver. 1.20 | lobby subtypes 3 and 5 — 5 reads "OFFICIAL CUP LOBBY" |
| Interval, Stealth DM, Solo Capture, Race | later | not served |

---

## Face-paint colour unlocks

**Status: no such mechanism exists in this build. Recorded here because it plausibly arrived in a
later version, and because the field we were sending will look like an invitation to someone
later.**

### What we were doing

Our `0x4131` reply (the wardrobe/appearance echo) carried a trailing `u32` of `0xffffffff` at wire
`0xb6`, named `FACE_PAINT_UNLOCKED` and described as a "face-paint colour unlock bitmask, one bit
per colour". Both the name and the value were inherited from a reference server, on the note *"both
references send all-ones, so every colour is offered; no source of a narrower value has been
found"* — i.e. tier 4, the category that has cost this project six regressions.

Removed 2026-07-29. The reply is now 182 bytes.

### What the binary actually says [ELF]

- **The field is never read.** Parser `0xD3C3DC`; its last read is the 128-byte comment at
  `0xD3C6E0`, and it falls straight into READ_END at `0xD3C6F4` with no read in between. Total
  consumed is `4 + 19 + 5 + 5 + 20 + 1 + 128 = 182`. No instruction anywhere in the text span
  touches the struct slots those four bytes would occupy.
- **Over-sending was harmless**, which is why it survived unnoticed: READ_END (`0xD5C858`) performs
  no length check, and the read helpers bound the cursor against the 1024-byte receive buffer
  rather than the payload. The parser never knows how long a packet was.
- **The name was impossible, not merely unevidenced.** Face paint is a **single byte** at
  appearance struct `+4` (`profile+7652`), sitting between "lower" (+3) and "upper colour" (+5). A
  one-bit-per-colour mask has no colour axis to apply to. That byte has exactly one reader in the
  binary — the player-announce builder at `0x88426C` — which broadcasts it to peers verbatim,
  unfiltered and unvalidated.
- **No unlock machinery reachable from it.** The server-supplied bit-test helper `0xD5C2A8` has
  three call sites (`0x916E54`, `0x91C07C`, `0x91C910`), all in the stats screens — none in the
  wardrobe or character creation. The only appearance-adjacent availability predicate found,
  `0x9B9DF0`, gates **loadout items** off the `0x3049` trailer, not appearance bytes.

**Stated limit of that negative:** the wardrobe screen's own 200-byte working copy
(`0x9D0F28`–`0x9D0F3C`, into `screenObj+468`) was not exhaustively audited, so "this client has no
appearance-unlock logic anywhere" is not proven. What *is* proven is narrower and sufficient: **no
such logic can be driven by this field, because the field is never parsed.**

### Why it belongs in this file

If a later version (1.36 was suggested) added progressively unlocked face-paint colours, it would
need:

- a **wider or repurposed appearance byte**, or a parallel array — the single byte at `+4` selects
  a paint, and nothing in this build enumerates colours separately; and
- a **server-supplied availability field the client actually parses**, which `0x4131` wire `0xb6`
  is not, because the parse stops before it.

So a future toggle cannot simply be "start sending the mask again". Whoever implements it must
first establish, against **that version's** binary, where the availability lives and whether the
parse length changed. The value `0xffffffff` carries no information and should not be treated as a
starting point.

**Release-day scope is not at risk from this**, which is the practically important conclusion: we
were sending four bytes into the void, not handing out unreleased content.

---

## Mailbox tabs 2 and 3

Not post-launch content as far as anyone knows, but unresolved and adjacent, so noted here to keep
it from being re-derived.

The mailbox has **four categories (0..3)** plus a flat view (4) aliasing 0 with a limit of 64 —
four arrays of 16 records, 280-byte stride, at `mailBlock+0x1E268`. Category **0 is Inbox** and
**1 is Sent**, both confirmed live 2026-07-26. **2 and 3 are unidentified**; category 2 has no UI
reference at all and may be unreachable in this build.

The labels live in the language resource, not the binary, so the ELF cannot settle them. The
one-shot experiment is written down in `MessageGameController`: four letters, categories 0/1/2/3,
each with a distinct subject, then read the tabs. `MGO2SERVER_MAIL_CATEGORY_*` exists to run it in
one restart.
