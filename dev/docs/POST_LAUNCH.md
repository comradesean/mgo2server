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
| **Survival** lobbies | Ver. 1.10 | lobby subtype 4 is named in the disc resources (`LOBBIES.md`); **fully mapped 2026-08-03, enablement checklist below** |
| **Tournament** lobbies | Ver. 1.20 | lobby subtypes 3 and 5 — 5 reads "OFFICIAL CUP LOBBY"; **fully mapped 2026-08-03, enablement evidence below** |
| Interval, Stealth DM, Solo Capture, Race | later | not served |

---

## Survival and Tournament: what a toggle actually has to do — mapped 2026-08-03

The `0x49xx` team family, the `0x4Axx` event subsystem and the `0x4Exx` Survival Match List
are now **fully mapped**: every field named or carrying a control-validated precise negative
(the per-field evidence lives in `dev/proto/`; run `dev/tools/field_scoreboard.py`). All of it
is **tier-1 only** — no available client build exercises these commands, so nothing can reach
tier 2 until a 1.36 client can be driven through them. What follows is the *enablement* map:
every instruction-level gate between a stock client and each mode, in dependency order. This
is the evidence a version toggle needs; it is not a proposal to serve anything.

### The structural picture

There is **no version guard and no feature bit** anywhere in these paths. Every screen and
sender is unconditionally installed; what holds the modes closed is entirely **which lobby
subtype the server lists and what it sends on the team/event commands**. The three dormant
subtypes are 3 = Tournament, 4 = Survival, 5 = Official Tournament (disc strings,
`AUTOMATCH.md` §10; `LOBBIES.md` has the menu scans and title arms). One byte —
`lobby_subtype`, delivered on the team record at `team+0x260` and republished to the app
object's `+0x294` — is the switch the whole client dispatches on: subtype 4 routes to the
Survival screen family (`0x8CB8FC`-`0x8CFF40`, ~20 gates), 3/5 to the in-game round manager
(`0x6EAC90`/`0x6EBFA8`), and the `0x4Axx` packets themselves are shared, subtype-blind
carriers (no 0x4Axx parser branches on subtype — the split is all consumer-side; see
`mgo2_cmd_4a13_s2c.ksy`).

### Survival enablement checklist (each item with its ELF evidence in the named file)

1. **List a subtype-4 lobby** in `0x4902` — the menu row and title exist for it already
   (`LOBBIES.md`). The Survival browser menu row appears only when the app object's `+0x294`
   byte is 4 (`0x8BC208`; strings 806/807 "Survival Match List").
2. **Deliver subtype 4 on the team record** — `team+0x260` is written ONLY by the shared
   parser `0xD4AF34` on `0x4911`/`0x4913`/`0x4987`/`0x49A1`; without it the browser entry
   never appears (`mgo2_cmd_4e00_c2s.ksy`).
3. **Answer `0x4E00` completely and promptly**: `0x4E10` (event record; list magic must be
   0) → `0x4E11` rows → `0x4E12` carrying **result 0**, the only writer of wait slot 90's
   result. The screen sends `0x4E00` unconditionally from its state 1 and raises
   `5521:FFFFFF60` after 6000 ticks; a bare ack does not clear it. This is the one stall in
   the subsystem — `0x4E20`..`0x4E23` consume no request slot and cannot stall.
4. **Echo `event_id`** on `0x4E12` and `0x4E20` (compared against event+0x000, silently
   dropped on mismatch, -1106), and pass the shared `0x4E2x` header validator `0xD49230`
   (team id + the u16 serial at `team+0x29C`, else -1018; bypass when the context word is
   0x4960).
5. **Drive `team_state`** (`team+0x04`) — entirely server-authoritative, no client writer:
   <= 2 shows "Team Standby", 5 is what makes the "Join Game" row exist, 9 flips the screen
   to counted-roster mode and hardens the `0x4918` row gate (`mgo2_cmd_4e20_s2c.ksy`).
6. **Populate the roster before the status columns** — `team+0x17C` is 8 x 28-byte member
   records ({chara id, name[16], ..., member_state at +0x15}); `0x4918` refuses a row whose
   status byte isn't 1 (or 2 when team_state is 9).
7. **In-game, set the ladder record's subtype** so `gameObj+0xBCC` gets bits 8/9/10 — the
   single setter `0x272728` fires for subtype 3..6-excluding-2 and sets all three in one
   `ori`; bit 10 is what lets the client send `0x43B0` (the Survival match report), which
   then needs a 4-byte `0x43B1` result. Subtype reaches that record via `0x43F0`/`0x43F1`
   or copied from the team record by six parsers (`mgo2_cmd_4e00_c2s.ksy`, `AUTOMATCH.md`
   §11).
8. **Serve the match-flow packets**: `0x4A00` opens the event AND seeds the next-match
   card's identity (its `new_id` lands in ladder+0 — `0x4A13`'s `card_id` must echo it or
   the card is dropped, -1106); `0x4A13`/`0x4E20` carry the pairing; `0x4E21`..`0x4E23`
   update the roster column; `0x4E23` tears the event down.

### Tournament (subtypes 3 and 5)

Items 1-2 and 5-8 apply identically with subtype 3; the differences are:

* **Subtype 5 (Official Tournament) has a server-decided row gate**: the hub-list entry's
  byte at `0x06` must equal 3 or the Lobby Select row is never emitted — that is `0x4902`'s
  `subtype5_row_gate`, and it is the only lobby category with a precondition. It is also the
  only category that renders the entry's 64-byte text block.
* The team flow runs through the **TEAM SELECT** screen (`0x4980` → `0x4981/2/3` team list,
  `0x4984` team info, `0x4910` Create Team → `0x4911`, `0x4912` join-with-password) — all
  mapped, with the join gates (capacity 5207, closed 5215, password) on the team-list row
  fields (`mgo2_cmd_4982_s2c.ksy`, `mgo2_cmd_4910_c2s.ksy`).
* The round manager reads the ladder's `series_total`/`series_index` as round total/current
  ("is this the final round"), where Survival's screens read the same two slots as the
  participants' win counts — **the slot pair is subtype-polymorphic, and a server must not
  mix the two writers in one session** (`mgo2_cmd_4a13_s2c.ksy`).
* The `0x49Cx` invitation channel (3-slot inbox/outbox at `session+0x117F8`) is mapped but
  **dead code on this build** — senders, waiters and table accessors all have zero callers —
  so a 1.0 toggle cannot use it; it presumably went live in a later build
  (`mgo2_cmd_49c1_s2c.ksy`).
* Clan Stats (`0x4b21`'s popup and the CLAN RECORD screen) unlocks only once official-match
  data exists — the screen refuses until "an official match is held" — which is what ties
  feature completeness to subtype 5 actually running.

### What this means for the toggle design

The toggle is **operator policy plus data, not a client patch**: list the subtype, serve the
team/event/list commands, and the client does the rest. The serving surface is sizeable —
the team subsystem (create/join/roster/notifications), the event flow (`0x4A00` family), and
for Survival the `0x4E00` triple with its hard stall — so "enable Survival" is a feature
build, not a flag flip. But every packet it needs is now named, every gate has an address,
and the two stalls in the whole space are known (`0x4E00` unanswered; `0x43B0` unanswered
once bit 10 is set). Per the file's rule: dates and version labels above are community
knowledge; everything else is read from the disc binary.

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

## The trailer, byte by byte

`0x3049` ends with a **32-byte array** — the client's `tail[32]`. It is not one value; each byte is
separate, and only two carry anything:

```
index:  0     1     2     3     4 .......................... 31
        00    07    00    03    00 .......................... 00
              ^           ^
              |           `- account.entitlements_byte3  (displacement 487)
              `------------- account.entitlements_byte1  (displacement 485)
```

Displacement is off the context base returned by `0xD36C74` (`base+21968`), which is how the client
addresses these after the parser at `0xD3732C` copies all 32 bytes in.

| index | we send | status |
| --- | --- | --- |
| 0 | `0x00` | no ctx-derived reader |
| **1** | `0x00` *(was `0x07`)* | **proven dead** — displacement 485 read nowhere; stopped sending it, V66 |
| 2 | `0x00` | no ctx-derived reader |
| **3** | `0x01` for a granted account, else `0x00` | **bit 0 = the day-one paid Codec Pack.** Bit 1 is discarded by the instruction encoding |
| 4..31 | `0x00` | no ctx-derived reader |

**Settled 2026-07-30.** Displacements 484..515 are read at exactly **two addresses in the whole
binary** — `0x9B9E30` and `0x9BADA4` — both reading index 3, and both masking to bit 0 via
`rlwinm r27,r0,4,27,27` and `clrlwi r0,r0,31`. So **bit 1 is not merely unread, it is discarded in
the opcode**, and 31 of the 32 bytes are inert.

That negative is worth trusting because of how it was reached, unlike the earlier one it replaces
(which tested displacement 487 — index 3's own offset — and then generalised). Four searches, each
naming its displacement: every D-form access at 485 for any register and width; a raw
instruction-word scan of the text section; the profile-relative displacement 22453 and its
`addis`-adjusted band; and `addi rX,rY,485`, i.e. any pointer to the byte ever being formed. Then a
chain-of-custody check that also covers indexed access: the ctx pointer has **16 origination sites**
binary-wide, and the complete set of offsets any of them touches is **0, 1, 2, 4+60·i, and 487**.

Columns are named `entitlements_byte1` / `entitlements_byte3` (V65) after the byte each carries; the
earlier `entitlements` / `entitlements_index1` pair read as a value and a variant of it.

> **Caveat for any future trailer change.** The parser's 480-byte memset covers `ctx+4..483` only,
> so the trailer is **never cleared** before a `0x3049`. Harmless while we always write all 32
> bytes, but a short-trailer variant would inherit stale bytes rather than zeros.

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

**Default zero, in the schema as well as in the data.** Every existing account was set to `0` on
2026-07-29, and **V64 changes the column default to `0`** so new accounts match without anyone
remembering to run an `UPDATE`. Serving a paid day-one item to everyone is a decision, and it is now
made per account rather than inherited from a constant.

`entitlements_byte1` deliberately still defaults to `7` — see below; zeroing it would be an
experiment, not a correction.

Reversible either way in one statement:

```sql
update account set entitlements_byte3 = 1 where id = <account>;   -- grant the day-one Codec Pack
update account set entitlements_byte3 = 0 where id = <account>;   -- withhold it
```

### Index 1: zeroed for 1.0 — possible expansion/patch territory

**Status: proven inert on this build, and deliberately not sent.**

We shipped `0x07` here for months — three set bits inherited verbatim from the reference servers,
never derived from anything. On 2026-07-30 the byte was searched properly and **displacement 485 is
read nowhere in the binary**, so V66 stopped sending it.

**Why it belongs in this file rather than just being deleted.** "No reader in *this* build" is not
"no meaning". The reference servers that supplied the constant targeted **different client builds**,
and the value did not come from nowhere — somebody's server sent `0x07` because something,
somewhere, read it. The plausible readings are:

- a **later patch** gave that byte a reader, exactly as the second codec pack required a client
  update to extend a table; or
- it belongs to the **expansion**, which the lobby model already knows about
  (`lobby.expansion_required`), and this build simply never consults it; or
- it is genuinely meaningless cargo that propagated between servers by copying.

We cannot distinguish those from our artifacts, and the release-day rule settles what to do anyway:
**a byte we cannot explain is not sent.** If a later version is ever served behind toggles, this is
one of the first things to re-test against *that* binary — the column
(`account.entitlements_byte1`) was kept rather than dropped precisely so it can be, with one
`UPDATE` and no migration.

Same reasoning applies to index 3 **bit 1**, which is discarded by the instruction encoding here and
is the natural carrier for the second codec pack.

### Index 1: the evidence

We sent `0x07` here — three more set bits from the same inherited constant — until the search gap
was closed properly on 2026-07-30. **Displacement 485 is read nowhere in the binary**, so the bits
were dead, and V66 stops sending them and defaults the column to 0.

The column stays rather than being dropped, so a later build can be tested against it without a
migration. Sending `0x07` again is a one-line `UPDATE` if a future version ever gives that byte a
reader.

---

# Inventory: what we send that does nothing

**Every value below is emitted by this server and read by nothing on this client.** Kept in one
place because the pattern repeats: each arrived as an inherited constant, each looked like an
unlock, and each turned out to be inert — sometimes provably so, sometimes only by luck.

Two reasons this list matters rather than being trivia. First, an inert value is a *latent* one: it
does nothing **on this build**, and several of these sit exactly where a later version would put
something. Second, a value that looks like an unlock will eventually be trusted as one — that is
how a paid item ended up granted to everyone.

| what | where | why it does nothing | status |
| --- | --- | --- | --- |
| **Trailer byte 1** (`0x07`) | `0x3049` trailer index 1 | displacement 485 is read **nowhere** in the binary | **stopped sending**, V66 |
| **Trailer byte 3, bit 1** | `0x3049` trailer index 3 | the two readers mask to bit 0 — `rlwinm r27,r0,4,27,27` and `clrlwi r0,r0,31` — so it is **discarded in the opcode** | not sent |
| **Trailer bytes 0, 2, 4..31** | `0x3049` trailer | no ctx-derived reader at displacements 484, 486, 488..515 | sent as zero |
| **`FACE_PAINT_UNLOCKED`** (`0xffffffff`) | `0x4131` wire `0xb6` | the parser stops at 182 bytes and never reaches it; face paint is a **single byte**, so a per-colour mask had no axis | **removed**, reply now 182 bytes |
| **The sixteen `{item, bit}` pairs** | `0x4124` / `0x4133` tail, 32 bytes | the parser ORs a pair into record `+16` **only if the bit is already set** in the mask at `+12`, so it can only ever produce a subset of what we already sent — and `+16` drives a wardrobe *highlight*, not availability | filler `0xff`, which the parser skips (item 255 > its 128-entry bound) |
| **`chara_gear.colours` bits above each item's own count** | `0x4124` / `0x4133` record `+12` | the mask indexes a **per-item slot**, so the legal width is per item — 21 bits for most, but 1 for the six glove ids and the four single-colour accessories. A slot with no catalogue record is skipped **before** the mask is consulted (`0x9276F0`, `0x9254FC`). No item exceeds 24 | still sent as `0xFFFFFFFF` — see below |
| **55 of the 122 gear ids** | `0x4124` / `0x4133` records | 29 exceed the parser's 128-entry bound (`cmplwi r9,128; bgt` at `0xD3CF00`); 26 fall in gaps no category window covers **and none has a colour-catalogue record** — padding, not future items | still sent — see below |
| **Gear ids 28, 68, 86, 102** | `0x4124` / `0x4133` records | the "None" entries — unconditionally owned by a hardcoded id comparison at `0x92735C`-`0x927384`, and absent from the colour catalogue, so no mask bit can ever be read for them | still sent, harmlessly |
| **`0x600000` per-skill experience** | `0x4122` / `0x4131` | `0x6000 << 8`, i.e. 256x the client's legal maximum of 24576; survived because `>> 13` clamps to 3 | **fixed** — both now send stored values |

## The two that are still sent, and why they are on the to-do list

**`chara_gear.colours` = `0xFFFFFFFF`** on all 732 live rows. The top 8 bits cannot mean anything,
and for the ten single-colour items 31 of the 32 cannot. Every item's colour set is a contiguous
`0..n-1` run, so the legal value is exactly `(1 << n) - 1` and there are only seven distinct masks
across the 67 real items. Narrowing it is generated work, not hand-written — an agent is dumping
the per-item counts from the catalogue at `0x10506BC`.

**The 55 phantom gear ids.** Inert today, but not harmless in one specific way: **every character's
`chara_gear` currently asserts ownership of 55 items that do not exist**, so any future locking
policy written against the inherited list would be locking imaginary items. The 26 in-range ones
are the interesting group — they land in the trailing headroom of *every* category:

| category | this build enumerates | we also send |
| --- | --- | --- |
| upper body | 11-13 | 14-19 |
| head | 28-38 | 40-44 |
| hands | 46-51 | 52-53 |
| feet | 57-62 | 63-64 |
| chest | 68-80 | 81-83 |
| waist | 86-97 | 98-100 |
| accessories | 102-116 | 117-119 |

That distribution *looked* like expansion headroom — bump a `li r25,N` count immediate, take the
next free id — and this file said so. **Tested 2026-07-30, and it does not hold: none of the 26
appears in the client's colour catalogue at `0x10506BC`. Zero rows, all twenty-six.** Every real
gear item has colour records; these have none, so they are **padding in an inherited list, not
later-build items**.

The one apparent exception is **id 4**, which is catalogued with 11 colours — but it sits in the
`0..7` run, and those eight share a colour vocabulary (ids 0-11) no gear category uses.
`o/slotdat/slot_online_face.slot` holds exactly eight models (`mgo_faceM01_whiteA` …
`mgo_faceM08_latinoB`), and the 9-arm switch has **no arm for face**, so 0-7 are face ids with their
skin/hair palette, handled outside this path. Id 4 is inert in `0x4124` either way.

So the honest reading is duller than the one it replaces: we inherited a longer list than this
client has, and there is no evidence the surplus was ever anything. Deleting the 55 is safe on the
client's side and loses nothing.

# What the unlocks mean for v1

For contrast, the complete list of things we send that **do** control content on this build:

| unlock | carrier | gate |
| --- | --- | --- |
| **character slots** | `0x3049` header | a per-account count |
| **MGO Codec Pack** (32 preset messages) | `0x3049` trailer index 3, **bit 0** | `0x9B9DF0` refuses any phrase whose gate exceeds `(byte & 1) << 4`; 32 catalogue rows gate on 16. **Paid day-one item** — granted per account, default off |
| **gear item ownership** | `0x4124` / `0x4133` record `+8` | `0x927350` — an item absent from the packet is **never listed** in the wardrobe. Five "None" ids are exempt |
| **gear colour availability** | `0x4124` / `0x4133` record `+12`, bits 0..23 | `0x925538` / `0x92772C` — `mask & (1 << colourIndex)` per swatch |
| **per-skill experience** | `0x4122` / `0x4131`, and `0x43a4` inbound | not an unlock as such, but the same shape: stored values, legal maximum 24576, and the client **zeroes** any record above it |

Four items, and only the first two are entitlements in the shop sense. Everything else on the wire
that looked like an unlock is in the table above it.

## Lower body: one item, and the client cannot show it

Not post-launch content, but the same species of finding — a category that exists on the wire and
does nothing on screen.

The lower-body arm covers **exactly one id (22) with no "None" entry**, and the arm at `0x927138`
loads `r28 = 0` where every other arm loads a real 24-bit group hash — so the shared enumerator
branches around the label lookup (`cmpwi cr7,r28,0 / beq` at `0x9274C4`) and no text is ever
fetched.

**Precisely: the category is not skipped and the row IS appended** (`0x9274F0`), with a null label
pointer. The client draws **one blank row**. The empty-list fallback at `0x92751C`-`0x927568`
behaves identically, so owning id 22 or not changes nothing observable — it is effectively always
worn and never selectable. An operator reported the category as offering nothing, which is exactly
what one unlabelled, unswappable row looks like.

The **colour** is still reachable, though: id 22 carries the full 21-colour camo mask, and camo
selection runs through its own screen ("Select Lower Body Camouflage"). Trousers are colourable but
not swappable.

The disc record is broken too, independently: id 22's header at sid 1115 points its EN ordinal at a
JP string reading *"trousers (provisional name)"*, with a stray `Aucun` in the neighbouring slot.
So `gear_item.name` is **NULL** for 22 — a defect in the data, not a gap in ours.

Worth recording because a later build with more than one lower-body item would need that arm to
carry a real group hash. If a future version is ever served, this is a cheap tell for whether its
wardrobe grew.

## The gear reward system — post-launch, and the reason v1 grants nothing

**A character owns only what it chose at creation.** On the original service the sole route to any
further item or colour was a **reward system added after launch**.

That makes generosity here a release-day violation rather than a matter of taste, which is why v1
has **no unlock mechanism at all**: no drops, no achievements, no purchases, nothing that writes a
`chara_gear` row after creation. A character keeps its creation choices permanently, and that is
correct for the target version.

We got this wrong twice in the permissive direction — granting the whole catalogue (V44 and
earlier), then an invented 28-item starter set (V70) — before it was corrected in V71. Both were
plausible and neither was what the game did.

**Evidence tier:** operator knowledge of the original service. The client cannot settle it — it
never checks ownership against anything, it renders whatever the two gear writers agree on — so no
amount of ELF work would have produced this, and it is recorded as testimony rather than dressed up
as a finding.

**When a later version is served**, the reward system is the thing to design, and the shape is
already in place: rewards write `chara_gear` rows, ORing colour bits into the existing mask. What
they should be granted *for* is unknown and is not in our artifacts.

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

~~**Gear has no gate at all**~~ — **withdrawn 2026-07-30, it overreached.** What the experiment
established stands: clearing the codec bit does not affect gear, and `0x9B9DF0` has no loadout call
site. What does *not* follow is "therefore nothing gates gear". **Gear is gated** — by the `0x4124`
table itself at `0x927350`, with no predicate function involved, which is exactly why looking for
one found nothing. Varying the codec bit could not have tested gear either way, so it was never an
elimination. See `CLAUDE.md`, "Before crossing something off".

**Granting it is therefore a live operator-policy decision**, and the only one in this subsystem:
`account.entitlements_byte3` bit 0, per account. Every account was set to `0` on 2026-07-29, with the pack
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

**How to settle it.** The byte lives in `account.entitlements_byte3` (V62, renamed V65) and is read on every
character-list fetch, so this needs **no restart and affects only the account you pick**:

```sql
update account set entitlements_byte3 = 0 where id = <account>;   -- then reconnect
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

Restore with `update account set entitlements_byte3 = 3 where id = <account>`. The default is unchanged
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

## Fields the client WRITES but never READS — a real idea, and the trap that guards it

**Raised by the operator 2026-08-01**, and the principle is sound: a field marked *"no reader
anywhere in the image"* is not finished. **A value that travels the wire was used for something**,
and if nothing in *this* binary consumes it, the consumer is another build. That would make such
fields the best-evidenced candidates for a version toggle — better than anything read out of a
string table, because the client itself produced the value.

The first attempt to act on it produced a **false positive**, and the reason is important enough
that it is written up before any list.

### THE CIRCULARITY TRAP — read this before mining captures

Our archived captures are a real `BLUS30109` client talking to **our own server**. So for any field
**the server sends**, a non-zero value in a capture proves nothing at all: the client received it
from us and echoed it back. The capture confirms our own cargo.

This was hit immediately. `0x4310` struct `+824` carries `0x02000000` in **182 of 214** captures,
co-varying exactly with `+931` — both zero in every Basic/Combat Training capture, both set in every
other. It looks like textbook evidence of a lobby-dependent feature this build no longer reads.

**It is not.** `HostSettingsReply.java` had already caught it: the `0x02` is inherited cargo, Create
Game entry memcpys the whole saved object into the screen, and the `0x4310` builder re-emits it — so
*"the 0x02 coming back was our own byte completing a round trip."* The correlation with training
lobbies is a fact about which saved object was in play, not about the game.

This is precisely the failure `CLAUDE.md` opens with: **faithful copying of a source that does not
apply looks exactly like diligence**, and here it also looked like fresh evidence.

### So the check has three gates, not one

A field is version-toggle evidence only if **all** hold:

1. **The client originates it.** If the server sends the field at all, captures against our server
   are circular and cannot be used. Check the writer before the capture.
2. **It is non-zero in captures**, read at its **schema-declared width**. Reading four bytes at
   `0x0f4` — declared `u2` — swallowed `host_stance` and `level_limit_tolerance` and made a
   constant-zero field look like a varying one. `0x0ee`, `0x0f0` and `0x0f4` are zero in all 214
   captures and are genuinely dead.
3. **No reader in this build**, established by a scan whose range is stated and whose edges are
   justified.

### And "no reader" is not even meaningful for c2s

For client→server traffic *we* are the reader; there is no reader in the client image **by
construction**. Marking a c2s field inert on that basis is a category error, and it has probably
mislabelled part of the campaign's inert set. Those fields need the builder-side question instead:
what does the client's sender put there, and where does the value come from?

### Current status: no confirmed instance

After the above, **no field currently qualifies.** The captures we hold cover only `0x4310` (214)
and `0x4390` (566), and `0x4310` is dominated by fields we author.

What would make the idea productive is **captures of client-originated commands** — the `0x43xx`
in-match reports especially, where the client is reporting its own state and nothing we send can
contaminate the value. That is a live-capture task, not a disassembly one.

