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

---

## Paid content we currently grant unconditionally

### The 32 loadout items behind the `0x3049` trailer — GRANTED

`0x3049` carries a 32-byte trailer whose **index 3 bit 0** is the only meaningful bit in it. We
send `0x03` there, and that bit unlocks **32 of the 91 selectable loadout items**: the availability
predicate `0x9B9DF0` walks an 85-entry table at `0xE1812C` and refuses any item whose gate exceeds
`(byte & 1) << 4` — 0 or 16 — and exactly 32 entries gate on 16. Clear the bit and those 32
disappear from the loadout screen. 23 entries gate on 0 and are always available; 27 defer to a
separate ownership check.

**This is an entitlement, and we grant it to everyone by default.** That is *operator policy*, not
protocol, and it has never been a deliberate decision — the value was inherited. Whether those 32
are the day-one shop items has not been established. Two positions are defensible and the choice
should be made rather than drifted into:

- **Grant (current).** A private server with no shop cannot sell them, and withholding content the
  player can see referenced elsewhere is its own kind of wrong.
- **Withhold behind a flag.** Closer to release-day fidelity, and the bit is trivially per-account
  once the trailer stops being a constant.

If it becomes a toggle, it is one bit sourced per account, not a new packet.

### Is the entitlement bit the WHOLE shop? — the experiment to run

**Hypothesis, 2026-07-29 (operator's):** the shop may not have several mechanisms, just one. If the
85-entry table at `0xE1812C` is a *mixed* availability table rather than a loadout-only one, then
`0x3049` trailer index 3 bit 0 gates everything the shop sells, and "32 of the 91 selectable
loadout items" is simply the label the first trace reached for.

The number is what makes it worth testing: the bit unlocks **32** gated entries, and the day-one
Codec Pack adds **32** phrases. Matching counts are not evidence — but they are a reason to look,
and the test is one restart.

**How to settle it.** `MGO2SERVER_ENTITLEMENT_BYTE=0`, restart, then check *both* screens:

1. the loadout item list, and
2. Personal Data -> Game Play Options -> **Preset Message Slot**.

| what shrinks | conclusion |
| --- | --- |
| loadout only | the existing label is right; the codec pack is gated somewhere else |
| preset messages only | the label is wrong — the table is the message list, not items |
| **both** | **one bit is the whole shop.** Rename it, and make it per-account |
| neither | the bit does not reach either screen, and the trace needs revisiting |

Restore with `MGO2SERVER_ENTITLEMENT_BYTE=3` or by unsetting it. The default is unchanged, and a
test pins it so the default cannot drift silently.

### The MGO Codec Pack — WHERE IT IS GATED IS UNKNOWN

A day-one paid item on the Konami shop: **32 additional voice phrases** for the preset-message
slots (`Personal Data -> Game Play Options -> Preset Message Slot`, 16 slots settable). Per the
product notes the entitlement attaches to the **Konami ID**, i.e. the account, not the character —
so if it is server-gated at all, the natural carrier is an account-scoped field.

**Not established, and not guessed at here.** What is ruled out:

- **Not the `0x3049` trailer.** Only index 3 bit 0 has readers; indices 0, 2 and 4..31 have none,
  so there is no spare bit there for it.
- **Not the login perks field.** `0xBB16B0` `strtol`s it and *discards the result* — only the
  syntax matters, so it cannot carry an entitlement.

Open questions for whoever picks this up: does the preset-message list builder consult any
availability predicate at all, or are all phrases simply present in this build (as turned out to be
the case for face paint)? The phrase text lives in the disc string resources, so the list itself is
readable — the question is whether anything filters it.

**Caution — a citation that needs checking.** The `0x3049` trailer note cites `0x9C0600` as part of
a "separate ownership/expansion check" for 27 loadout items. A separate investigation of the
host-rating path described `0x9C0600` as returning nonzero only when `roundMode() == 10 &&
amHost()`. Those two descriptions cannot both be right about the same function. One of them is
mis-attributed, and it should be resolved before either is built on.
