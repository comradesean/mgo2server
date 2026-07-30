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
  `0x9B9DF0`, gates the **codec / preset messages** off the `0x3049` trailer (see below — it was
  labelled "loadout items" until a live test disproved that), not appearance bytes.

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

## The two bits that are paid content — index 3, bits 0 and 1

**These are the two we should not be setting by default, and as of 2026-07-29 we do not.**

| bit | what | evidence |
| --- | --- | --- |
| **index 3, bit 0** | the **day-one MGO Codec Pack** — 32 preset-message phrases, a paid Konami-ID item | [ELF + LIVE + DISC] proven three ways: clearing it removed the codec list live, the predicate reads exactly this bit, and the 32 gated rows match the published product list 32/32 in order |
| **index 3, bit 1** | almost certainly the **second codec pack**, and inert on this build | [ELF] no reader — the byte is read at two addresses and both test bit 0. Its referent is inference: it is the other bit of the same inherited constant, in the byte whose bit 0 is a codec pack, and a second pack is known to have existed |

Both came from the same place: `0x03`, copied wholesale from reference servers and filed in
`PROTOCOL.md` under *"fixed constants we emit without knowing why"* since 2026-07-19. Nobody chose
to grant a paid item; it arrived with the transcription.

**Why bit 1 cannot be served anyway.** A second pack had to extend the catalogue at `0xE1812C`,
which has 82 populated rows — and **ten phrase ids are on the disc but absent from it** (27, 34, 35
and 58..64), three with full 19-string voice blocks: *"What's our leader's position?"*,
*"Pass! Pass!"*, *"Shoot!"*. Adding rows means patching the executable, so no server flag can do it.
That is consistent with the second pack requiring a client update, and it means the bit is inert
here rather than dangerous.

### Current policy (2026-07-29)

**Default zero.** `account.entitlements` defaults to `3` in the schema for historical reasons, but
every existing account has been set to `0`, with the codec pack granted individually where wanted.
Serving a paid day-one item to everyone by default is a decision, and it should be made per account
rather than inherited from a constant.

Reversible either way in one statement:

```sql
update account set entitlements = 1 where id = <account>;   -- grant the day-one Codec Pack
update account set entitlements = 0 where id = <account>;   -- withhold it
```

### Still unexamined: index 1's three bits

We send `0x07` at trailer index 1 — three more set bits from the same inherited constant, and
**none has been tested**. The claim that index 1 "has no reader" does not hold up: the search behind
it looked for `lbz r0,487(r3)`, which is **index 3's** offset (`ctx+21968 + 487 = ctx+22455`). Index
1 is `485`. So nobody has actually looked.

It is per-account (`account.entitlements_index1`, V63), so the test is the same shape:

```sql
update account set entitlements_index1 = 0 where id = <account>;   -- then reconnect
```

Left at `7` for now, because zeroing it is an experiment rather than a correction — but on the same
reasoning as the two bits above, an inherited constant nobody can explain should not stay set
forever.

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

## Paid content: what it is, and how it was found

### The MGO Codec Pack — 32 preset messages (resolved live 2026-07-29)

*Policy and the bit layout are under "The two bits that are paid content" above; this
section is the evidence trail.*

`0x3049` carries a 32-byte trailer whose **index 3 bit 0** is the only meaningful bit in it. The
availability predicate `0x9B9DF0` walks an 85-entry table at `0xE1812C` and refuses any entry whose
gate exceeds `(byte & 1) << 4` — 0 or 16 — and exactly 32 entries gate on 16. 23 gate on 0 and are
always available; 27 defer to a separate check.

**What those 32 are was settled by experiment, then confirmed phrase by phrase.** With the bit
cleared on one account and a reconnect:

- **codec / preset messages: MISSING**
- **gear and outfits: completely unchanged**

So the 85-entry table is a **preset-message table**, and the earlier ELF label — "32 of the 91
selectable loadout items" — was wrong. The 32 are almost certainly the **MGO Codec Pack**, a
day-one paid item advertised as *"32 additional voice tracks"* and attached to the **Konami ID**
rather than the character, which matches the entitlement being per-account.

The count that prompted the test was the whole clue: 32 gated entries, 32 phrases in the pack.
Matching counts were not evidence, but they were a reason to look — and looking cost one `UPDATE`.

**Then the table was dumped and matched row by row: 32/32, in the published order**, macros included
(`ONSLAUGHT`, `TAKEFIRE`, … `LAUGH`, `LAUGH2`). Five of the product page's English strings differ
from the disc's — *"Somebody, come quick!"* is *"Somebody!"*, *"Goal!"* is *"Score!"* — because each
phrase has **19 voiced variants** and the page quoted a different one. The two `Laughter` rows carry
no text at all, which is what a pure voice cue looks like.

**Gear has no gate at all**, settled at the same time: the predicate has 17 call sites binary-wide,
none in loadout code, and the trailer byte has no third reader. The original "loadout items" label
was a misread of the table's contents, not a mislabelled gate.

**Granting it is therefore a live operator-policy decision**, and the only one in this subsystem:
`account.entitlements` bit 0, per account. Every account was set to `0` on 2026-07-29, with the pack
granted individually where wanted.

**This is an entitlement, and we grant it to everyone by default.** That is *operator policy*, not
protocol, and it has never been a deliberate decision — the value was inherited. Whether those 32
are the day-one shop items has not been established. Two positions are defensible and the choice
should be made rather than drifted into:

- **Grant (current).** A private server with no shop cannot sell them, and withholding content the
  player can see referenced elsewhere is its own kind of wrong.
- **Withhold behind a flag.** Closer to release-day fidelity, and the bit is trivially per-account
  once the trailer stops being a constant.

If it becomes a toggle, it is one bit sourced per account, not a new packet.

### The SECOND codec pack — likely post-launch, and possibly bit 1

**The store sold two codec packs.** The first is the day-one item recorded above: 32 phrases, 32
gated entries, proven. The second came later and **reportedly required a client update** — which,
if true, puts it squarely out of scope for v1, because a pack that needs a patch cannot have been
active on release day.

**It is not bit 1, and there is no carrier for it in this build.** The trailer byte is read at
exactly **two addresses binary-wide** — `0x9B9E30` and `0x9BADA4`, both in the preset-message
subsystem — and both test **bit 0 only**. So the `0x03` we send has one live bit and one inert one,
and no flag anywhere grants a second pack.

**What a second pack would have had to change: the catalogue itself.** The phrase table at
`0xE1812C` has a loop bound of 85 and **82 populated rows**. Ten phrase ids are **shipped on the
disc but absent from the table entirely** — 27, 34, 35 and 58..64 — and three of them have full
19-string voice blocks: *"What's our leader's position?"* (string 521), *"Pass! Pass!"* (654),
*"Shoot!"* (673). Voiced, present, unreachable.

That is exactly the shape of content a later patch would switch on, and it explains why the second
pack **needed a client update**: adding phrases means extending a table in the executable, which no
server flag can do. A server-side entitlement can only gate rows that already exist.

**So for v1 there is nothing to withhold and nothing to grant.** The second pack cannot be served,
by us or by anyone, without a patched client. If later versions are ever served behind toggles, the
thing to check first is whether *that* build's catalogue has grown past 82 rows and whether a second
bit acquired a reader.

**Evidence tier:** that a second pack existed and needed an update is community/store knowledge
(tier 4). The inertness of bit 1 and the ten unreferenced ids are [ELF] and [DISC] respectively.

### Is the entitlement bit the WHOLE shop? — the experiment to run

**Hypothesis, 2026-07-29 (operator's), now PARTLY ANSWERED:** the shop may not have several
mechanisms, just one. The test below was run and the answer was **"preset messages only"** — the
bit gates the codec pack and does *not* touch gear. So it is not the whole shop; it is one product.
Whether character slots and any other shop item have their own carriers is still open (slots are
already a per-account count in the `0x3049` header, so that one at least is separate).

The number is what makes it worth testing: the bit unlocks **32** gated entries, and the day-one
Codec Pack adds **32** phrases. Matching counts are not evidence — but they are a reason to look,
and the test is one restart.

**How to settle it.** The byte lives in `account.entitlements` (V62) and is read on every
character-list fetch, so this needs **no restart and affects only the account you pick**:

```sql
update account set entitlements = 0 where id = <account>;   -- then reconnect
```

Then check *both* screens:

1. the loadout item list, and
2. Personal Data -> Game Play Options -> **Preset Message Slot**.

| what shrinks | conclusion | |
| --- | --- | --- |
| loadout only | the existing label is right; the codec pack is gated somewhere else | |
| **preset messages only** | **the label is wrong — the table is the message list** | ← **OBSERVED** |
| both | one bit is the whole shop | |
| neither | the bit does not reach either screen, and the trace needs revisiting | |

Restore with `update account set entitlements = 3 where id = <account>`. The default is unchanged
at 3, and two tests hold the line: one pins the default on the wire, one proves the column reaches
it, so neither the default nor the plumbing can drift silently.

Being per-account also makes the eventual policy cheap: if these turn out to be shop items and we
decide to withhold them, it is a column that already exists rather than new plumbing.

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

**That citation conflict is resolved (2026-07-29).** The trailer note called `0x9C0600` part of a
"separate ownership/expansion check"; the host-rating investigation read it as
`roundMode() == 10 && amHost()`. **The host-rating reading is correct** — `0x9C060C bl 0x6A9A38`,
`cmpwi cr7,r3,10`, then `0x9C0638 bl 0x26E958` for the host test. Mode 10 is Combat Training, so it
means "you are the instructor running this session".

It is not an ownership check of any kind, and neither is its companion `0x9C2C90`, which accepts
phrase ids 67..92 outside training for a player not on team 0/1 who is carrying item type 17.
**Neither reads the trailer, a purchase flag, or any account record.** The 27 entries they gate are
the Combat Training instructor commands, and no server-side field controls them.
