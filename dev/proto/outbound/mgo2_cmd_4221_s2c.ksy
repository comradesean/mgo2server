meta:
  id: mgo2_cmd_4221_s2c
  title: "MGO2 0x4221 — player-details card (single reply to 0x4220 {u32 character id})"
  endian: be
  encoding: ISO-8859-1
doc: |
  Single reply (no triple) to the 0x4220 player-details request — the history row's
  "Player Details" context-menu item (observed live 2026-07-23). Sender 0xd3b950, parser
  0xd3d874, subsystem index 0x1c. 201 bytes total: u32 result code, then 197 bytes of
  fields. A nonzero result skips every field read and surfaces via the open screen's error
  dialog (no fixed screen constant in this path). Field POSITIONS and client struct
  destinations are READ from the parser (ELF trace 2026-07-23); labels came from the live
  fingerprint pass the same day (u32s 95xx, u8s 6x, FP-DTL-* strings served), and the card
  has since been filled in with real data (live 2026-07-27).

  The card renders NAME, CLAN, LEVEL, PLAY TIME, COMMENTS, and a square-button "more
  details" that requests the 0x4102 personal-stats burst for this card's character id.
  NAME, CLAN, PLAY TIME and COMMENTS are all confirmed rendering correctly with real data.

  THE RENDERER, read end to end 2026-07-30 (batch 3a). The card's popup builder is
  `0x905818`; its state machine calls `0xD3A0AC` at `0x905BB8` and parks the result in `r25`
  for the whole draw, so **every `N(r25)` in `0x905BB4`-`0x906670` is a read of `T+N`** and
  the destinations this file records can be matched to screen slots one for one. In draw
  order:

  | site | reads | becomes |
  | --- | --- | --- |
  | `0x905E00` | `T+0x124` | `grade_points`, `"%s (%d)"`, gated on feature bit 2 |
  | `0x905F28` | `T+0x120` | `experience` -> `0x6F9260` -> **LEVEL**, `"%d"`, clamped to 99 |
  | `0x90606C` | `T+0x484` | a bare `"%d"`, gated on feature bit 2 |
  | `0x9060EC` | `T+0x494` | `play_time_seconds`, `"%.2d:%.2d:%.2d"` |
  | `0x906270` / `0x906320` | `T+0x1EA5` | `worn_title` sprite and title text |
  | `0x9063F4` / `0x906404` | `T+0x1AA0` / `T+0x1AB5` | clan id and membership state |

  `0xD3A094` returns the LOCAL character block (`ctx+0x57D8`) and `0xD3A0AC` returns this
  packet's viewed-player block (`*(ctx+0x11904)`). **The two have the same layout**, which is
  what licenses the offset bijection used throughout this file: a destination offset named by
  `0x4101`/`0x4103`/`0x4122`/`0x4129` in one block is the same field in the other. That is not
  "the neighbour is called X" — it is two writes provably landing on the same byte of the same
  struct shape.

  FEATURE BIT 2 GATES TWO OF THIS CARD'S SLOTS. `featureBit(ctx, n)` is `0xD382F8`
  (`ctx[0x117D0 + n/8] >> (n&7) & 1`, and it returns 0 for any n > 5). The card calls it with
  n = 2 at `0x905E20` (for `grade_points`) and `0x905FEC` (for `unknown_1e`); when the bit is
  clear both elements are filled with string 3 — a single space — and the icon beside
  `unknown_1e` gets sprite 3 instead of 74. **We send a zero feature byte in `0x4101`, so
  neither of those two slots has ever been on screen.** GATES.md §1 previously listed one
  consumer of bit 2 (the clan-roster column); these are the second and third. Release-day
  scope: do not open it to see what they say.

  THE LEVEL TABLE IS NOT IN THE ELF. `0x6F9260(exp)` counts entries of a 128-entry u32 array
  that are `<= exp`, stopping at the first zero or the first entry greater than `exp`. The
  array lives in .bss at `0x1659D24` and is filled at load by `0x6F9370`, which opens disc
  resource **114** and stores 128 words into it. So the threshold values quoted elsewhere in
  this project (125, 250, 375, 500, 650, ...) are NOT tier 1 — the binary gives the walk, the
  disc gives the numbers.

  RESOLVED 2026-07-27 — the CLAN "---" reading. The 2026-07-23 pass sent FP-DTL-CLAN into
  the 16-byte string at wire 0xab and the card's CLAN slot rendered "---", which was
  recorded here as [CANDIDATE, WEAKENED] with two live alternatives: "either the label is
  wrong or display is gated". The second alternative is correct and the first is falsified.
  Wire 0xa7/0xab/0xbb are a `{u32 id, char name[16], u8 state}` triple — the same shape a
  clan takes everywhere else in this protocol (session record at +0x1AA0, 0x4122's block,
  0x4b47, 0x4b21's head, 0x4103's tail) — and every reader traced so far checks the ID
  first, treating a zero id as "no clan" whatever the name says. Sending only the name was
  never going to render. With the id and state sent alongside it, the clan renders.
doc-ref: dev/docs/PROTOCOL.md "0x4220 — player details"
seq:
  - id: result
    type: u4
    doc: "[CONFIRMED] Wire 0x00. Result code: 0 = success; nonzero skips all fields and raises the error dialog (parser 0xd3d8e8 branch)."
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED-BY-USE] Wire 0x04, character id — dest T+0x000; we echo the requested id. The
      card's square-button "more details" sends 0x4102 with this character (fake 9101 produced
      our not-found status 1, rendered 1036:00000001 — screen 0x1036 = character information).
  - id: name
    type: str
    size: 16
    doc: "[CONFIRMED] Wire 0x08, player name — dest T+0x004. FP-DTL-NAME rendered as NAME; renders the real character name live 2026-07-27."
  - id: experience
    type: u4
    doc: |
      [CONFIRMED 2026-07-30] Wire 0x18 -> dest T+0x120. **Experience, and the source of the
      card's LEVEL** — the card has no experience figure on it, only a Level, and this is the
      number the Level is computed from.

      Reader, tier 1: `0x905F28 lwa r3,288(r25)` -> `bl 0x6F9260` (the level-from-experience
      walker) -> `r29 = min(ret, 99)` (`addi -99`, `sradi 63`, `and`, `addi +99` at
      `0x905F44`-`0x905F5C`) -> `max(r29, 0)` -> `sprintf("%d")` into element `0x00426793`.
      Ungated. The personal-stats header runs the identical pair off the LOCAL block —
      `0x915FE4` and `0x916068`, both `lwa r3,288(r27)` then `bl 0x6F9260` — but WITHOUT the
      99 clamp, so a level above 99 would print in full there and cap here.

      Offset bijection: the same slot is `0x4101` wire `0x01c` (`experience`, "the account's
      main exp"), `0x4103`'s `experience` (parser write `0xD3EAF0 addi r4,r31,288`), and this
      packet's write at `0xD3D92C`. Three parsers, one destination.

      This also upgrades `0x4103`'s "[INFERRED] ... the level is presumably client-derived from
      experience, but that mapping is unverified": the mapping is `0x6F9260`, and it is a
      count of table entries not exceeding the value. See the header note on where that table
      comes from — it is a disc resource, not ELF data.

      Live confirmation (2026-07-27 probe round 2, recorded in `SocialGameController`): 1450
      here and 250 / 130 / 500 in the three neighbours; every card read **Level 10**, which is
      1450's level and no other candidate's. Round 1 had sent 11 / 22 / 33 / 44 and read 0
      everywhere — the same answer unrecognised, since all four were under the first threshold.
  - id: unknown_1c
    type: u1
    doc: |
      [UNKNOWN — but live, with two identified readers] Wire 0x1c -> dest T+0x3328.

      **This is `0x4101`'s `unknown_028` slot** (`profile+13096`, ctx+35584), reached here on
      the viewed-player block instead of the local one. Batch 2c's readers were re-derived
      independently in batch 3a from a whole-image sweep of displacement 13096 — there are
      exactly six instructions in .text at that displacement, and they partition cleanly:

      - `0x8842B4` `lbz r29,13096(r11)` — the join-announcement builder. Low nibble only
        (`clrlwi r29,r29,28`), OR'd with a bit-5 term derived from `0x9066FC` (settings byte 0,
        bits 4-5), stored to **announce +2** at `0x8842D8`. Peers land that on record key 350,
        the 4-bit field CLIENT_STORE.md §3a records.
      - `0x8BA540` `lbz r0,13096(r3); cmpwi cr7,r0,3; beq 0x8BA5D8` — **only the value 3 is
        special**; that arm runs two level walks through `0x6F9260`, so it selects a
        level-comparison display path.
      - `0xD3C288` (`0x4101` parser), `0xD3D948` (this parser), `0xD3EB4C` (`0x4103` parser) —
        writers.
      - `0x4148C0 stw r0,13096(r9)` — rejected on provenance: one store inside an uninterrupted
        run of `stw`s at 12944..13100 stride 4, i.e. a u32 array in an unrelated engine struct,
        which is incompatible with 13096 being an independently addressed byte.

      No name is available at tier 1: nothing in the image says what the nibble counts, and the
      only distinguished value is 3. **The card itself never reads it** — no `(r25)` load at
      displacement 13096 exists in `0x905BB4`-`0x906670`. We send 0.
  - id: beginner_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-30] Wire 0x1d -> dest T+0x3329, which is `profile+13097` — **the same
      slot `0x4101` (wire `0x129`) and `0x4129` (wire `+9`) already name `beginner_flag`**.
      Writers: `0xD3C318` (`0x4101`), `0xD3CA6C` (`0x4129`), `0xD3D964` (here), `0xD3EBDC`
      (`0x4103`).

      Meaning, from the readers of the LOCAL copy (six, every one with its base from
      `bl 0xD3A094`): **zero makes the client refuse to enter a lobby marked "beginners only"**,
      raising error screen 2355 — "You cannot login to this lobby." — with code `-404`
      (`0xFFFFFE6C`). Re-verified here at `0x89224C`, `0x935B34` and `0xAC8270`, each of which
      is the same three instructions with the same two constants (`li r3,2355; li r4,-404;
      bl 0x885A08`), and the polarity is zero-refuses in all three. `0xABCF90` and `0xABDA14`
      are the two non-dialog readers and agree: `((v - 1) >>u 31) + 1` = **2 when zero, 1 when
      non-zero**, stored as a two-state selector.

      **Nothing on this card reads it.** The value arrives on the viewed-player block, and every
      gate above reads the local one, so what we send here cannot affect our own lobby entry.
      It is named by the offset, not by a consumer on this screen. See LOBBIES.md §"nothing
      sets profile+13097" for the live half of the story.
  - id: unknown_1e
    type: u4
    doc: |
      [UNKNOWN — one reader, and it is held closed by a feature bit] Wire 0x1e -> dest T+0x484.

      **Exactly one reader in the whole image.** All 178 instructions in .text
      (`0x10230`-`0xDE9328`) at displacement 1156 were listed and classified in batch 3a — not
      a band, the entire text section. Of those, the only one whose base is a character block
      is `0x90606C lwz r5,1156(r25)`, in this card's own popup builder, with `r25` from
      `bl 0xD3A0AC` at `0x905BB8`. The `0x87CExx`-`0x87EFxx`, `0x4Axxxx` and `0xC9xxxx`
      clusters are `stw`/`lwz` pairs on unrelated objects, and `0xD3D980` is this packet's own
      parser write.

      What that reader does: `0x905FEC` calls `featureBit(session, 2)`. **Bit set** — icon
      element `0x0059602A` gets sprite 74 and element `0x00426795` gets `sprintf("%d", value)`
      into an 11-byte buffer. **Bit clear** — sprite 3 and string 3, which is a single space.
      We send a zero feature byte, so this slot has never been rendered and no live observation
      of it exists or can exist without opening the bit.

      CORRECTION — the claim that this is the card's LEVEL is wrong. OBSERVED.md (2026-07-29,
      "SOLVED: 0x4105 matrix 0 memsets the cell") states *"The card's LEVEL is column 13 of the
      same row (`T+0x484`)"*. The card's LEVEL is computed from `experience` at `T+0x120`
      through `0x6F9260` (see that field); `T+0x484` is printed bare, as `"%d"`, and only when
      feature bit 2 is set. The arithmetic in that note is untouched — `T+0x484` really is
      `0x4105` matrix index 0, memory row 11, column 13 (`312 + 11*72 + 13*4`), and `0x4105`'s
      index-0 memset of `T+0x138`+3456 really does clear it — but the identification is not.
      The server writing the level into that column is mislabelled, not harmful.

      No tier-1 name. Both bit-2-gated numeric slots found so far (this one and `0x4b54 +0x30`
      in the clan roster) are unnamed for the same reason: a quantity that has never been on
      screen cannot be identified from a renderer that only formats it.

      **[2026-08-01] Re-examined and left as is; recording what would actually decide it, because
      the negative here is already as good as a static negative gets.** The 178-instruction
      enumeration is the strongest form of evidence this campaign has produced and there is nothing
      to add to it: one reader, gated, and the gate is closed. What is missing is not analysis, it
      is an observation, and only one experiment can produce it — **open feature bit 2 on a test
      account, then fingerprint `T+0x484` with distinct values across several cards and read the
      slot that appears beside sprite 74.** Two cautions, both from this batch's rules:

      * The value is printed bare with `"%d"` into an **11-byte** buffer, so it has no units and no
        clamp to give it away; the fingerprint must be chosen to be recognisable on its own
        (something like `123456`, not a plausible statistic).
      * Feature bit 2 also opens the clan-roster column `0x4b54 +0x30`. Open it for one experiment
        and both slots change at once, so vary **one** of them per run or the two cannot be told
        apart — this is exactly the "one process emits both" trap FIELD_MAPPING.md records from
        batch 1.

      Bit 2 is a release-day gate we deliberately send closed (`GATES.md` §1). Opening it for a
      test is not a proposal to serve it.
  - id: play_time_seconds
    type: u4
    doc: |
      [CONFIRMED] Wire 0x22, dest T+0x494. Total play time in seconds. Fingerprint 9503
      rendered as PLAY TIME 02:38:23 (= 9503 s).

      DEFINITION (live 2026-07-27): this is the SUM ACROSS GAME MODES, not the raw stored
      aggregate. The client totals the per-mode column itself, so the figure this card shows
      must equal the figure the personal-stats screen shows — the aggregate times the number
      of populated mode rows. Sending the raw stored aggregate here read SIX TIMES SHORT
      against the stats screen, because six mode rows were populated.

      Separate known problem, recorded so the definition is not mistaken for correctness: the
      total is INFLATED. The server stores one play-time number and writes it into every mode
      row because there is no per-mode accounting. Both screens agree with each other; neither
      agrees with reality.
  - id: worn_title
    type: u1
    doc: |
      [CONFIRMED 2026-07-30] Wire 0x26 -> dest T+0x1EA5. **The worn title (animal rank),
      1-based, 0 = none** — the same quantity `0x4122` carries at wire `0xef` and `0x4129`
      re-sends after every round, at the same struct offset.

      Read twice by this card, off `r25` (= `0xD3A0AC`, the viewed-player block):
      `0x906270 lbz r29,7845(r25)` -> if nonzero `0x942948(value, 0)` for the badge sprite,
      else sprite 18 as the "no title" default; then `0x906320 lbz r3,7845(r25)` ->
      `0x943450(value, ctx, x)` for the title text. Those are the same two resolvers the title
      SELECTION screen uses on the local block at `0x915D3C` and `0x916AFC` (the latter
      comparing `+0x1EA5` against its loop index to mark the currently worn row), and
      `0x942948` has only three call sites in the image, all three of them these.

      Only six instructions in .text use displacement 7845: `0x8842A4` (announce +3),
      `0x906270`, `0x906320`, `0x915D3C`, `0x916AFC`, and this parser's write at `0xD3D9B8`.
      So the field's whole life is visible.

      **We send 0, so the card's title badge is blank for every player.** The value is
      available — `0x4122` already carries the real one. PROTOCOL.md's "0x4103 and 0x4221 write
      their own +0x1EA5 into a scratch block, not the local character record" is correct and is
      exactly why this is a separate, still-unfilled slot. Values must be 1..22; the readers'
      match loop runs 21 iterations over a 22-entry table.
  - id: comment
    type: str
    size: 128
    doc: "[CONFIRMED] Wire 0x27, player comment — dest T+0x1e24. FP-DTL-COMMENT-128 rendered as COMMENTS; renders the real database comment live 2026-07-27."
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0xa7 -> dest T+0x1aa0. Clan id, and the FIRST member of
      the `{u32 id, char name[16], u8 state}` clan triple. This is the gate: every reader
      traced so far checks the id before the name, and treats 0 as "no clan" regardless of what
      the name carries. Zero here is why the fingerprint pass rendered CLAN as "---" while
      sending FP-DTL-CLAN in the string below.
  - id: clan_name
    type: str
    size: 16
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0xab -> dest T+0x1aa4. The clan name, second member of
      the clan triple. Renders in the card's CLAN slot when `clan_id` is nonzero.

      Falsified reading kept on the record: this field was tagged [CANDIDATE, WEAKENED] with
      the "---" symptom and two alternatives, "either the label is wrong or display is gated".
      The label was right; display is gated on `clan_id`. Resolved, not deleted — the symptom
      is what a name-only clan write looks like, and it will look identical anywhere else in
      this protocol that carries the same triple.
  - id: clan_state
    type: u1
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0xbb -> dest T+0x1ab5. Clan membership state, third
      member of the clan triple. Same constants the client writes for itself: 0 affiliation
      pending (0xD58740), 1 member (0xD56B68), 2 leader (0xD56B84), 99 not in a clan
      (0xD56B44 / 0xD56C7C / 0xD56D68, each `li r0,99` alongside a zeroed clan id). Readers
      test membership as `state - 1 <= 1`.
  - id: host_rating_numerator
    type: u4
    doc: |
      [CONFIRMED 2026-07-30] Wire 0xbc -> dest T+0x32D8. **The Host Rating star NUMERATOR** —
      the sum of the ratings cast, which over the denominator below gives the average the gauge
      draws.

      Named by offset bijection, not by position: `0x4103`'s `rating_block` is nine u32s at
      `T+0x32C4`..`T+0x32E4`, so its entry **5** is `0x32C4 + 5*4 = 0x32D8` — and entry 5 is
      already [CONFIRMED 2026-07-28] as the Host Rating numerator. Same struct, same byte.

      Reader, and it is the one that settles the pair: `0x91858C lwa r27,13020(r9)` immediately
      followed by `0x918590 lwz r3,13016(r9)`, with `r9 = *(screen+128)`; the two go straight
      into `bl 0x94258C` at `0x9185B0` — the half-star gauge, `clamp(ceil(2*num/den), 0, 10)`.
      The same function three instructions earlier does `0x918450 lwz r3,13040(r9)` /
      `0x91844C lwa r28,13044(r9)` -> the same `0x94258C`, and 13040/13044 are `T+0x32F0` /
      `T+0x32F4`, the already-confirmed **Instructor Score** numerator and denominator. Two
      gauges, identical code shape, one already named — which is what fixes `screen+128` as a
      character block and closes the identification.

      Only six .text instructions use displacement 13016 (`0x414860` an unrelated engine-array
      `stw`, `0x918590`, `0xCB8264`/`0xCB8280` `addi r,0` immediates, and the two parser
      writes), so there is no second consumer.

      **This corrects `SocialGameController`'s "WHAT they count is still unknown".** They count
      host-rating votes. We still send 0, which the gauge reads as "no bar" — a deliberate
      choice, and now a choice about a known quantity rather than an unknown one.
  - id: host_rating_denominator
    type: u4
    doc: |
      [CONFIRMED 2026-07-30] Wire 0xc0 -> dest T+0x32DC. **The Host Rating star DENOMINATOR**,
      the "/ N votes" total. `0x4103`'s `rating_block` entry **6** = `0x32C4 + 6*4 = 0x32DC`,
      already [CONFIRMED 2026-07-28] as that denominator; read as the signed half of the pair
      at `0x91858C` (`lwa`, so it is treated as signed) and passed as `0x94258C`'s second
      argument. See `host_rating_numerator` for the full trace. Six .text instructions use
      displacement 13020 and they mirror 13016 exactly. We send 0; the gauge returns 0 if
      either half is 0.
  - id: clan_emblem_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-30] Wire 0xc4 -> dest T+0x1AD8 (`profile+6872`). **The clan emblem
      flag**, the same byte `0x4122` (its trailing `B+19`, stored at `0xD3CC0C`) and `0x4b47`
      (`0xD584B0`) write on the local block, and `0x4103` writes at wire 631.

      **3 is the value that means "a published emblem exists"**, and it is the only value
      tested anywhere: `0x905A90 lbz r0,6872(r28); cmpwi cr7,r0,3; beq` in this card's own
      state machine, `0x8F9950` in the clan screen, and `0x905B68` when copying the fetched
      state back. On a match the card calls `0xD56704`, which is the **`0x4b4a`** sender
      (`li r4,19274` at `0xD56774`, one u32 payload = the clan id read from `T+0x1AA0` at
      `0x905AB4`) — the emblem display fetch. The test is reached only after `0x905A7C` has
      confirmed `clan_state - 1 <= 1`, i.e. member or leader.

      `0x88415C lbz r0,6872(r29); stb r0,4(r31)` puts it at **announce +4**, beside
      `worn_title` at +3 and the clan id at +8, which is why the emblem draws next to the title
      badge on a scorecard row.

      Sending 0 is not "no picture", it is **"never ask"** — the fetch is skipped and the emblem
      is silently absent. This packet is the only writer of `+0x1AD8` on the Player Details
      path that carries a real value, so the emblem there depends on this byte alone. The
      server already fills it from `ClanService.emblemFlagOf`.
  - id: grade_points
    type: u4
    doc: |
      [CONFIRMED 2026-07-30] Wire 0xc5 -> dest T+0x124 (`profile+292`). **The same slot
      `0x4101` (wire `0x13e`) and `0x4129` (its `B+4`) both name `grade_points`** — a second
      experience-scale quantity, distinct from `experience` at `T+0x120`. Writers: `0xD3C374`
      (`0x4101`), `0xD3CB74` (`0x4129`), `0xD3F46C` (`0x4103`'s trailing `unk_u32_i`, wire
      644), `0xD3DAA0` (here).

      Reader, and this card is one of only two in the image: `0x905E00 lwz r28,292(r25)` ->
      `bl 0x942890` at `0x905E50`, which itself calls `0x6F9260` (the level walker) on the same
      value, clamps the result to 1..23 and indexes a 24-entry resource table; the returned
      string and the raw number are then formatted with `"%s (%d)"` (the literal at `0xE13298`)
      into element `0x00426794`. The stats screen does the identical thing at `0x915F64` ->
      `0x915F70`, with the same format string. So it renders as *a title for its level, then
      the number*.

      **Gated on feature bit 2** — `0x905E10`-`0x905E20` calls `featureBit(session, 2)` and, if
      clear, substitutes string 3 (a single space) for the whole slot. We send a zero feature
      byte, so it has never been on screen here. The stats-screen reader at `0x915F64` is
      ungated, which is the place to look if the quantity ever needs identifying.

      What the quantity IS remains unknown — the 24-entry table holds resource hashes, not
      strings, and the name is inherited from `0x4101` by offset, which is exactly what this
      file's rule 4 permits and no more. We send 0 here while `0x4129` mirrors `experience`
      into it; that inconsistency is worth fixing, and it is a server bug rather than a
      protocol fact.
