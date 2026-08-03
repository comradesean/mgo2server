meta:
  id: mgo2_cmd_4a00_s2c
  title: "MGO2 0x4A00 - Tournament/Survival event opened (server -> client)"
  endian: be
doc: |
  THE 0x4Axx SUBSYSTEM IS **TOURNAMENT / SURVIVAL** (identified 2026-08-02, ELF, tier 1).
  Not ranking - COMMANDS.md's 2026-07-27 negative on that reading stands and is not disturbed
  here. The identification runs through the three c2s commands the client can actually send in
  this block and the sentences their callers raise on failure:

    0x4A25 sender 0xD4F620, arms request slot 89; caller 0x8CCD20 raises dialog **5522**
           ("Unable to cancel Survival.") or **5376** ("Unable to cancel Tournament."),
           selected by `lbz r0,660(r3)` == 4 at 0x8CCD8C - i.e. by the lobby subtype at
           team+0x294, where AUTOMATCH.md already records 3 = Tournament, 4 = Survival,
           5 = Official Tournament.
    0x4A40 sender 0xD4F710, arms slot 88; caller 0x8F3E0C raises dialog **5409**
           ("A network server error has occurred. Unable to acquire Tournament list.")
    0x4A30 sender 0xD504A0, arms slot 87; the reply that clears slot 87 is 0x4A31.

  Corroborated from the other end by the screen that renders this subsystem's record. It reads
  the object through the getter 0xD4EA60 and formats it with the lobby string group 0xF914BF
  ("lobby", fetched by 0x8E0C24). The ordinals it passes resolve to:
    742 "The championship match has ended.\nWinning team: %s\nYour reward: %d"
    756 "Not enough teams have joined.\nThe tournament has been canceled."
    771 "The championship match has ended."
    773 "Round %d of the tournament is complete."
    774 "The tournament has been canceled."
    775 "The tournament has ended."
  Resolution method: dev/docs/AUTOMATCH.md section 10, lobby set control base 9789 / text base
  11033.

  TIER. Tournament and Survival are post-launch content (Ver. 1.20 and Ver. 1.10). Nothing in
  any available client build exercises 0x4A00, so **every statement here is tier 1, read from
  MGO2.elf, and cannot be raised to tier 2**. Do not assume a capture backs any of it.
  Mapping is in scope; serving it in v1 is not.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39850,
  parser 0xD50E94.

  DESTINATION - SETTLED 2026-08-02. Three destinations are in play in this family and they are
  not the same struct:
    * 0x4A00's own parse targets go into the **team record at session+0xD928**, returned by the
      getter 0xD491F8 (`addis r3,r3,1; addi r0,r3,-9944`), called at 0xD50F14. That is the same
      record AUTOMATCH.md names when it resolves 0x43F1 - team+0x25C lobby id, team+0x260
      subtype, team+0x261 rule id.
    * 0x4A24 writes **session+0xDBD0** (getter 0xD4EA60), a separate 7296-byte record.
    * 0x4A31 writes **`*(u32*)(session+0x11904) + 0x1A840`**, a third, heap-side instance of the
      same 7296-byte layout (its own getter is 0xD4EA7C, two call sites [2026-08-03]).
  So 0x4A00 does NOT share a destination struct with 0x4A24/0x4A31.

  [ELF 2026-08-03] The tail has a SECOND destination this file omitted: after the event-record
  population, 0xD51280 **clears the 356-byte ladder record** (session+0x11558, the record
  0x4A13/0x43F0/0x43F1/0x4E20 share) and 0xD5129C-0xD512CC **seeds it** — R+0 from team+664
  (0x4A00's `new_id`, which is why 0x4A13's `card_id` must echo it), R+4/8/9 from
  team+604/608/609 (the lobby id/subtype/rule triple), zeroing R+12/16/136/140. So serving
  0x4A00 both opens the event AND stamps the next-match card's identity.

  BUT THE PARSER TAIL DOES, and that is proved to the 0x4905/0x4909 standard - by an identical
  base computation, not by resemblance. 0x4A00's tail computes
  `0xD51060: addis r25,r23,1` / `0xD51068: addi r31,r25,-9264`, which is byte-identical to
  0x4A24's `0xD4FC18: addis r9,r27,1` / `0xD4FC1C: addi r31,r9,-9264`. Both are session+0xDBD0.
  Having parsed its own payload, 0x4A00 then **populates the 0x4A24 record**, and five of its
  wire fields land in the exact slots 0x4A24 fills from the wire:
    obj+0x000  <- team+0x298      (0x4A24's `obj_id`; this is the id 0x4A24 then validates)
    obj+0x004  <- `flags`, expanded bit-for-bit by the same `oris` ladder (0xD5105C..0xD51144
                  vs 0xD4FF60..0xD50044) - the same eight booleans in the same word
    obj+0x005  <- `unknown_last`  (0x4A24's `unknown_after_flags`; 0xD51148 vs 0xD50044)
    obj+0x008  <- `block` , memcpy 204 bytes at 0xD511B0 (0x4A24's `block`; 0xD50060)
    obj+0x1BF0 <- `unknown_after_block`, 64-bit widened (0x4A24's `unknown_0x19`; 0xD5127C
                  vs 0xD4FE44)
  It also copies team+0x25C / +0x260 / +0x261 into obj+0x1BF8 / +0x1BFC / +0x1BFD - the lobby
  id, lobby subtype and rule id 0x4A24 receives on the wire - and ZEROES the record's counters
  (obj+0xD4..0xE0, 0xD51194-0xD511AC), its 128x52-byte team table (obj+0xE8, 6664 bytes,
  0xD5121C) and both round bitmaps (obj+0x1AF0 and obj+0x1B70, 128 bytes each, 0xD51240 /
  0xD5125C).
  Reading in plain terms: **0x4A00 opens an event and resets the detail record; 0x4A24 fills
  that same record in.** So a server must keep the two consistent, and the five fields listed
  above must agree byte for byte between them or the client will validate 0x4A24 against a
  stale id and abort with -1106.

  0x4A00 also writes obj+0x298 of the team record, the value 0x4A02 / 0x4A22 / 0x4A29 later
  validate their echo id against (0xD50FA8 stores it; 0xD4F050 / 0xD514D0 / 0xD50B88 read it
  back) and the value 0x4A24 checks at 0xD4FCFC.
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230 and therefore easy to
  miss when reading this parser alone: u32 then u16. Both are validated against the client's
  currently open object for this subsystem (u32 vs obj+0x000 at 0xD4929C, u16 vs obj+0x29C at
  0xD492D4); a mismatch aborts with -1018 (0xFFFFFC06) before another byte is consumed. For
  command id 0x4960 only, 0xD49230 skips both comparisons and just consumes the six bytes.
  Modelled below as `obj_id` + `obj_serial`; the names describe the check, not a proven meaning.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230."
  - id: new_id
    type: u4
    doc: |
      [ELF] read at 0xD50FA8 and STORED at team+0x298 - **the event record id for the
      Tournament/Survival event this command opens.** It is the value 0x4A02 / 0x4A22 / 0x4A29
      echo-check against (0xD4F050 / 0xD514D0 / 0xD50B88) and, more strictly, the value
      **0x4A24's `obj_id` must equal**: 0xD4FCEC fetches this same team record and 0xD4FCFC
      compares, aborting with -1106 on a mismatch. The parser tail also copies it into the
      detail record at session+0xDBD0+0x000 (0xD51190), i.e. into 0x4A24's `obj_id` slot.
      So it is the key that ties the whole exchange together, and a server must reuse it
      verbatim in every follow-up. Not itself validated here.
  - id: team_state
    type: u1
    doc: |
      [ELF 2026-08-03 — named; was unknown_0x0a] Read at 0xD50FC4 -> **team+0x004**, the team
      record at session+0xD928, not the detail record. `team_state`, the team's
      event-participation state — one field with 0x4A01's same-named byte and the four
      0x4E2x's. The 2026-08-02 "displacement 4 is unsweepable" refusal is superseded by the
      getter-alias walk over all 83 `bl 0xD491F8` sites (plus the cached-pointer channel at
      screen+108): **eleven writers, all from the wire; five readers, all comparing one
      literal** — ==9 at 0x8C3084/0x8C3184 (counted-roster rendering) and 0x8D4A58/0x8D7B70
      (action suppressed), ==5 at 0x8CBCAC (enables the row ending in lobby string 741 —
      "Join Game" per the block-counted labels, see `mgo2_cmd_4e20_s2c.ksy`). Full enum and
      enumerations there. Entirely server-chosen; what 5 and 9 MEAN beyond these behaviours
      still rests on disc strings 718/741.
  - id: blob
    size: 8
    doc: |
      [ELF] eight bytes, byte-at-a-time loop 0xD50FD8-0xD51000. [UNKNOWN] contents.

      **CORRECTED 2026-08-02 from 128 to 8**, and this file was *not* among the three the
      correction batch flagged — a third independent pass found it by sweeping for the cause
      rather than the symptom, which is the only reason it was caught.

      The cause is one letter: the store is **`stdu`**, not `std` — DS-form with low bits `01`,
      the update form, which rewrites its base register. `mr r25,r1` then `stdu r0,120(r25)` at
      0xD50F64-0xD50F70 leaves r25 = **r1+120**, so the loop's exit test `addi r0,r1,128` is an
      **end ADDRESS, not a byte count**. The cursor runs r1+120..r1+128 exclusive: eight
      iterations, eight wire bytes. The old note "bound base+128" read that address as a length.

      **This one was the most damaging of the four.** `blob` is immediately followed by the
      204-byte `block_204`, so a 120-byte overstatement here displaces a sub-record that is
      genuinely served elsewhere — unlike the sibling commands, where the error only ran off the
      end of the packet.

      The class is closed rather than merely fixed: sweeping the whole parser block
      0xD33000-0xD5D000 for `stdu rX,disp(rY)` with `rY != r1` — the only encoding that can
      silently rebase a scratch buffer — returns exactly four sites: `0x4A00`, `0x4A02`,
      `0x4A22`, `0x4A29`. The complementary plain-`std` set contains `0x4A27`, whose declared 8
      was always correct because it forms its cursor explicitly with `addi r29,r1,112`. That
      contrast is the control, and it is also the diagnosis: the earlier reading was right
      wherever the base was written out, and wrong wherever an update-form store moved it.
  - id: block
    type: block_204
    doc: |
      [ELF] the shared 204-byte sub-record, read by 0xD4364C (called at 0xD51014) into
      team+0x0B0, and then **memcpy'd verbatim into the detail record at session+0xDBD0+0x008**
      (0xD511B0, `li r5,204`). That destination is exactly where 0x4A24's `block` field lands
      (0xD50060/0xD5006C), so the two commands' copies of this block are one field.
      In this subsystem it is the event's game settings - rule, rotation and the
      weapon-restriction bitfield the tournament runs under. See mgo2_cmd_4313_s2c.ksy, which
      remains canonical.
  - id: unknown_after_block
    type: u4
    doc: |
      [UNKNOWN] read at 0xD5102C (-> r1+116) and then stored 64-bit-widened into the detail
      record at **session+0xDBD0+0x1BF0** (0xD5127C, `std r0,7152(r29)`).
      [ELF] Cross-packet bijection: that is the same slot 0x4A24/0x4A31 fill from their
      `unknown_0x19`, so this and `unknown_0x19` are one field carried by two commands. The
      64-bit widening is the shape a time_t takes on this target (compare mgo2_cmd_4902.ksy
      open_time) and a scheduled start time would suit an event record, but that stays a guess:
      the field has **no reader**. Swept 0x8C0000-0x900000 (every 0xD4EA60 call site) and
      0xD30000-0xD70000 (the network library) plus a binary-wide backstop for loads at
      displacement 7152 - three stores, zero loads outside stack frames. Control: the same
      sweep found the readers of the neighbouring +0x1BF8/+0x1BFC/+0x1BFD.
  - id: flags
    type: u1
    doc: |
      [ELF] read as a 1-byte RAW (0xD5104C, 0xD5D018 len 1) and then expanded bit by bit with
      `oris` (0xD5105C-0xD51144) - so each bit is a distinct boolean, the same construction as
      mgo2_cmd_4902.ksy's flags byte.
      [ELF] The destination is **session+0xDBD0+0x004**, computed at 0xD51060/0xD51068
      (`addis r25,r23,1` / `addi r31,r25,-9264`) - byte-identical to the base 0x4A24 computes at
      0xD4FC18/0xD4FC1C, which is what proves the two write one struct. All eight bits land in
      that single byte, **bit-reversed**: wire bit 0 becomes bit 7 (`oris` 0x8000), wire bit 7
      becomes bit 0 (`oris` 0x0100); the `ld`/`std` pair leaves +0x000..0x003 (the id) alone.
      0x4A24's `flags` drives the identical ladder into the identical byte, so this and that are
      one field and a server must keep them consistent. No consumer identified for any of the
      eight bits. [UNKNOWN] individually.
  - id: unknown_last
    type: u1
    doc: |
      [UNKNOWN] last byte, read at 0xD51154 into **session+0xDBD0+0x005** (0xD51148,
      `addi r4,r25,-9259` off the same base as `flags`).
      [ELF] Cross-packet bijection: that is 0x4A24/0x4A31's `unknown_after_flags` slot
      (0xD50044/0xD50050). One field, two commands. **No reader** - see the note in
      mgo2_cmd_4a24_s2c.ksy; meaning unestablished.
types:
  block_204:
    doc: |
      [ELF] The 204-byte sub-record read by the shared helper 0xD4364C. That helper has NINE
      call sites, not just this family: 0xD445A4 (0x4313), 0xD48440 (0x4905), 0xD48964 (0x4909),
      0xD4B244 (0x4987), 0xD4CB08 (0x4950), 0xD5006C (the shared 0x4A24/0x4A31 parser),
      0xD51014 (0x4A00), 0xD5AF38 (0x4E10), 0xD5B78C (0x43F1).
      **CANONICAL MODEL: mgo2_cmd_4313_s2c.ksy, type `game_settings`.** That copy is the
      best-evidenced one - same 204 bytes, same reader, but its field names are backed by live
      capture (the 0x4310 push and the 0x4305 reply, OBSERVED.md). This type is a byte-accounting
      mirror; where the two disagree, 0x4313 wins. Enumerated read-by-read from
      0xD4364C-0xD43BC0.

      ## THE BIJECTION IS PROVEN, AND THE NAMES ARE NOW TRANSFERRED (2026-08-02)

      The old caveat here - "whether the game-settings meanings carry over to a 0x4Axx record is
      [UNKNOWN]" - overstated the doubt about *layout* and understated the one about *liveness*.
      Both halves are now stated precisely.

      **Layout: identical by construction, not by analogy.** 0xD4364C is ONE function. Its
      destination base is `r29`, the block pointer, and every field is written at a literal
      displacement off it. Disassembling 0xD4364C-0xD43BC0 gives exactly this displacement list,
      and it is the same list whichever call site supplied `r29`:

          0..47   3x u8 per iteration, 16 iterations   (0xD4368C / 0xD436B0 / 0xD436D0)
          48 u8   49 u8   50 raw16   66 u8   67 u8   68 u32   72 u32   76 u32
          80 u16  82 u16  84 u32     88 u32  92 u16   94 u8    95 u8
          96..164 u32 x18 (unrolled)
          168 raw2  170 u16  172 u32  176 u8  177 raw2  179 u8
          180 u16   182 u16  184 u32  188 u8  189 u8    190 raw14   = 204 total

      `mgo2_cmd_4313_s2c.ksy` type `game_settings` transcribes the same list from the same
      function. So the two types are the same struct at the same offsets with the same widths;
      there is no wire position at which they could disagree. Field ids below are the canonical
      ones wherever the canonical file draws a boundary this type also draws.

      **Names: tier 2 on the struct, never tier 2 on this packet.** The names come from the
      capture-proven 0x4310 push and 0x4305 reply of the SAME 204 bytes (OBSERVED.md, and the 214
      archived payloads in `../samples/4310/captures.psv`). No available client build sends or
      receives a 0x4Axx command, so nothing here can be raised to tier 2 *for this command*. Read
      every name below as: offset and width [ELF]; name [INFERRED] from a capture of the same
      struct carried by a different command.

      **What deliberately does NOT transfer: the "no reader in the image" verdicts.** The
      canonical file's negatives (block +72, +76, +80, +82, +84, +88, +92, +170, +172) were
      established against the **game-details object**, where the block sits at struct +752 and the
      sweep could use marker offsets 802/818/819/846/847/940/941 to tell that object from every
      other. In this family the block lands somewhere else entirely - the team record at
      team+0x0B0 for 0x4A00, and session+0xDBD0+0x008 / `*(u32*)(session+0x11904)+0x1A840+0x008`
      for 0x4A24/0x4A31 - so those displacements are different numbers and the sweep does not
      carry across. **Liveness is a property of the carrier, not of the layout.** No negative is
      claimed here for any field on the strength of the canonical file's negative; where one is
      claimed below it is claimed for this family's own destination.
    seq:
      - id: triples
        type: triple
        repeat: expr
        repeat-expr: 16
        doc: |
          [ELF] 16 iterations of three u8 reads (0xD4368C / 0xD436B0 / 0xD436D0, bound
          `cmpdi r27,16` at 0xD436D8). The three bytes are stored into three SEPARATE 16-byte
          arrays at block+0x00, block+0x10 and block+0x20 - i.e. the wire is interleaved
          (a[i], b[i], c[i]) and the struct is column-major. Getting this backwards would put
          48 bytes of anything in the wrong place while still parsing.
      - id: unknown_0x30
        type: u1
        doc: |
          [UNKNOWN - meaning] 0xD436F4 -> block+0x30 (block +48). Offset and width [ELF].

          **No name exists to transfer** - the canonical `mgo2_cmd_4313_s2c.ksy` carries this
          byte as `unknown_48` too, so this is a field the whole campaign leaves unnamed rather
          than one this mirror has not caught up with. What IS known travels with the byte and is
          recorded here so the gap is explicit rather than blank:

          - **In the game-details carrier it is published and then read by nothing.** `0x8CA460`
            copies struct+800 to a scratch byte and `0x8CA6F0` publishes the scratch as client
            property-store key 86, an 8-byte record of which only bytes 1 and 5 are ever filled
            (this field and `unknown_0x31`). The two ELF-side readers of those bytes, `0x7F4C98`
            and `0x7F4C50`, are **dead code** - no `bl`, and their OPDs are absent from the GCX
            native table while their immediate neighbours' are present. Full working in
            `mgo2_cmd_43f1_s2c.ksy` under `unknown_48`.
          - **Nothing in the create-game UI writes it**, so it is server-authoritative and simply
            round-trips through the client's own 0x4310.
          - **Capture value: 0x00 in all 214 archived 0x4310 payloads** (`../samples/4310`,
            hex chars 423-424). It has never been observed nonzero.

          Whether any of that holds for a Tournament/Survival record is **not claimed** - see the
          liveness note in the type doc above. The pairing with `unknown_0x31` is structural and
          does carry: they are two elements of one array in every carrier.
      - id: unknown_0x31
        type: u1
        doc: |
          [UNKNOWN - meaning] 0xD43710 -> block+0x31 (block +49). Offset and width [ELF].
          Canonical `unknown_49`; no name exists to transfer.

          Element 1 of the pair described under `unknown_0x30` - `0x8CA468` publishes it as key 86
          byte 5, its only ELF reader `0x7F4C50` is uncalled and unregistered, and no UI widget
          writes it. **Capture value: 0x00 in all 214 archived 0x4310 payloads** (hex chars
          425-426). Same carrier caveat as `unknown_0x30`.
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] 16-byte raw read (0xD43730) -> block+0x32. **Not a string.** An earlier
          revision typed this `str text_0x32`, "string role from the width and 0xD5D018's NUL
          behaviour only" - inferred from width alone, against capture evidence that already
          existed. It is the weapon-restriction bitfield: one bit per item, 1 = locked, byte 0
          bit 0 the master enable, confirmed weapon by weapon (nineteen for nineteen) by the
          2026-07-22 single-variable sweep at 0x4310 wire 0xD5..0xE4 (OBSERVED.md). 0x4310's
          copy of this block starts at wire 0xA3 and 0xA3 + 0x32 = 0xD5. See
          mgo2_cmd_4313_s2c.ksy for the full bit map and the corroborating offsets.
      - id: max_players
        type: u1
        doc: |
          [ELF offset+width 0xD43744 -> block+0x42 (66); name INFERRED from capture]
          **Maximum player count.** Renamed from `unknown_0x42` 2026-08-02 by struct-offset
          bijection with `mgo2_cmd_4313_s2c.ksy` `max_players`, which is capture-proven at 0x4310
          wire 0xE5 (0xA3 + 0x42, no omitted field before it). 214 archived payloads read 0x10 =
          16 in 176 of them, 0x02/0x03/0x11 in the other 38 - i.e. a small player count, which is what
          the name says.
      - id: player_count
        type: u1
        doc: |
          [ELF offset+width 0xD43760 -> block+0x43 (67); name INFERRED from capture]
          **Current player count.** Renamed from `unknown_0x43` 2026-08-02.

          The one live-session field in the block, and the identification is a negative that
          happens to be sharp: 0x4305 (saved settings) and 0x4310 (host push) both omit **exactly
          this byte** and nothing else in this region, which is what a "current" field looks like
          in a saved-settings reply. The client validator at `0x883FB4` rejects zero here in the
          game-details carrier. Whether a Tournament/Survival record validates it is not claimed.
      - id: words_0x44
        type: u4
        repeat: expr
        repeat-expr: 3
        doc: |
          [ELF] 0xD4377C / 0xD43790 / 0xD437AC -> block+0x44, +0x48, +0x4C (68, 72, 76), three
          consecutive u32 reads through the same primitive 0xD5CCD8.

          **The array id is kept, but the three elements are individually identified** by
          bijection with `mgo2_cmd_4313_s2c.ksy` - splitting the declaration is not permitted
          here, so the mapping is written out instead:

              words_0x44[0]  block +68  `briefing_time` - capture-proven at 0x4310 wire 0xE6;
                                        the create-game adjuster at 0x8A6D14-0x8A6E74 clamps it
                                        to about [0,30] with a +/-30 jump, and 0x8CA588 publishes
                                        it as property-store key 96.
              words_0x44[1]  block +72  canonical `unknown_72`. **A genuine u32**, not a u8 with
                                        padding: parser 0xD43784 uses the u32 reader and the
                                        0x4310 builder 0xD449C8 the u32 writer. Meaning
                                        [UNKNOWN]. Captures read 0x02000000 in 182 of 214
                                        and 0x00000000 in 32, and that split is exactly the
                                        split of `common_flags_lsb` - the two never disagree.
              words_0x44[2]  block +76  canonical `unknown_76`. [UNKNOWN], and not carried by
                                        0x4310 or 0x4305 at all - this family and 0x4313/0x43F1
                                        are the only ways to set it.
      - id: half_0x50
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD437C8 -> block+0x50 (80). Canonical `unknown_80`; **no name
          exists to transfer**. Width [ELF]: the u16 reader 0xD5CC14, not a u32 half.
          Capture value 0x0000 in all 214 archived 0x4310 payloads.
      - id: half_0x52
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD437E4 -> block+0x52 (82). Canonical `unknown_82`; no name to
          transfer. Width [ELF] **twice**: u16 reader 0xD5CC14 here, and an independent
          compiler-emitted `lhz r3,834(r3)` in the game-details accessor bank at 0x907784 - a
          dead accessor still declares a width. Not carried by 0x4310 or 0x4305.
      - id: word_0x54
        type: u4
        doc: |
          [UNKNOWN - meaning] 0xD43800 -> block+0x54 (84). Canonical `unknown_84`; no name to
          transfer. Width [ELF] u32 reader 0xD5CCD8. Capture value 0x00000000, 214 of 214.
      - id: word_0x58
        type: u4
        doc: |
          [UNKNOWN - meaning] 0xD4381C -> block+0x58 (88). Canonical `unknown_88`; no name to
          transfer. Width [ELF] twice: u32 reader 0xD5CCD8, and `lwz r3,840(r3)` in the dead
          game-details accessor bank at 0x90775C. Not carried by 0x4310 or 0x4305.
      - id: half_0x5c
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD43838 -> block+0x5C (92). Canonical `unknown_92`; no name to
          transfer. Width [ELF] u16 reader 0xD5CC14. Capture value 0x0000, 214 of 214.
      - id: host_stance
        type: u1
        doc: |
          [ELF offset+width 0xD43854 -> block+0x5E (94); name CONFIRMED from the binary's own
          symbol table] **The host stance** - renamed from `unknown_0x5e` 2026-08-02.

          This one is better than an inferred transfer: the client carries a developer name table
          at **0xE1BC48**, nine NUL-padded 20-byte entries reading `HOST_STANCE_EASY`,
          `HOST_STANCE_REAL`, `HOST_STANCE_BEGINNER`, `HOST_STANCE_EVERYONE`, `HOST_STANCE_OTHER`,
          `HOST_STANCE_TRAINING`, `HOST_STANCE_INSTRUCTOR_ENTRY`, `HOST_STANCE_INSTRUCTOR_STARTED`,
          `HOST_STANCE_NONE` - ids 0..8, with the client range-gating the value `cmplwi 9 / bgt`
          at 0xA31230. In the game-details carrier 0x8CA580 publishes it as property-store key 94
          and 0xD49530 copies it into a 0x4302 game-list row at T+0x24, which that spec also calls
          stance. Archived 0x4310 payloads carry 0, 2, 5 and 6.
      - id: level_limit_tolerance
        type: u1
        doc: |
          [ELF offset+width 0xD43868 -> block+0x5F (95); name INFERRED from capture]
          **The level-limit tolerance**, in LEVELS, applied as `base +/- tolerance` around
          `words_0x60[0]`. Renamed from `unknown_0x5f` 2026-08-02.

          Capture-proven at 0x4310 wire 0xF7, immediately before the level-limit base at 0xF8
          (OBSERVED.md 2026-07-22). The game-details carrier corroborates from two directions:
          0x8CA544 publishes it as property-store key 98, right beside key 99 = the base, and the
          game picker at 0x93452C-0x93455C tests a candidate's level against entry+38 as a
          tolerance around entry+40. 211 of 214 archived payloads read 0x16 = 22, the level cap.
      - id: words_0x60
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: |
          [ELF] 18 consecutive u32 reads, 0xD43884 through 0xD43A60 -> block+0x60..+0xA4
          (96..164). Unrolled in the binary, not a loop, so there is no count field.

          **The 1 + 17 split is real and both halves are identified.** The array id is kept
          because splitting a declaration is not permitted here; the mapping is:

              words_0x60[0]   block +96   `level_limit_base`, a u32 in LEVELS. Capture-proven at
                                          0x4310 wire 0xF8 by the 2026-07-22 single-variable
                                          sweep; published as property-store key 99.
              words_0x60[1..17] block +100..+164  the **per-rule timer / round / ticket table**,
                                          in the order SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets,
                                          DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r.

          The ordering is not inherited from a reference server. Two independent sites in this
          binary produce it: 0x8CA470-0x8CA4CC multiplies exactly eight of the seventeen by 60
          before publishing them, and those eight are indices {9,6,4,2,0,11,13,15} - precisely the
          time slots under this ordering, with no count scaled and no time left unscaled; and the
          tournament RULE DETAIL panel at 0x901808 selects the same pairs by an 8-way jump table
          on the record's rule byte and formats them with `%d分` / `%d回` / `%d枚` into widgets
          named `NULL_tournamentrule_time` / `_round` / `_ticket`. That second site reads the
          block through a **0x4909 tournament record**, which is the nearest thing this family has
          to a same-carrier confirmation.

          Note the Sneaking "defeat Snake N times" figure is NOT in this array - it is
          `sneaking_snake_kills` at block+0xBD.
      - id: pair_0xa8
        size: 2
        doc: |
          [ELF] 2-byte raw read (0xD43A80) -> block+0xA8 (168). Read as raw with r5=2, **not** as a
          u16, so the parser draws no boundary between the two bytes; the declaration is kept raw
          for that reason.

          The client itself does split them: in the game-details carrier 0x8CA5C0 and 0x8CA5C8
          load struct+920 and +921 as two separate `lbz` and 0x8CA87C publishes the pair as a
          2-byte property-store record, **key 134**. The canonical file names them
          `unique_red` / `unique_blue`, and that name is **tier 4 and doubtful** - unique
          characters were absent from this build's UI and untestable (OBSERVED.md). The archived
          captures argue against it as a per-team setting: **all 214 read `00 01`**, never any
          other combination, which is a constant rather than a pair of independently chosen team
          values. Meaning [UNKNOWN]; the observed value is not.
      - id: half_0xaa
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD43A9C -> block+0xAA (170). Canonical `unknown_170`; **no name
          exists to transfer**. Width [ELF] twice: u16 reader 0xD5CC14, and `lhz r3,922(r3)` in
          the dead game-details accessor bank at 0x9074B4. That accessor is separate from the
          indexed getter at 0x907174 which walks `920 + idx`, so this halfword is outside the
          `pair_0xa8` pair rather than a third element of it. Not carried by 0x4310 or 0x4305.
      - id: word_0xac
        type: u4
        doc: |
          [UNKNOWN - meaning] 0xD43AB8 -> block+0xAC (172). Canonical `unknown_172`; no name to
          transfer. Width [ELF] twice: u32 reader 0xD5CCD8, and `lwz r3,924(r3)` in the dead
          game-details accessor bank at 0x90748C. Not carried by 0x4310 or 0x4305.
      - id: common_flags_msb
        type: u1
        doc: |
          [ELF offset+width 0xD43AD4 -> block+0xB0 (176); name ELF-derived] The **most
          significant byte of the 32-bit Common Settings flags word**. Renamed from
          `unknown_0xb0` 2026-08-02.

          The word is the big-endian u32 at struct+928 in the game-details carrier, i.e. this byte
          then `common_ab` then `common_flags_lsb`: bits 31..24 here, 23..16 = `common_ab[0]`,
          15..8 = `common_ab[1]`, 7..0 = the lsb byte. 117 sites image-wide do
          `lwz rX,928(rB)` and bit-test the result, and **every tested bit lies in 8..23**, so no
          bit this byte owns is consumed anywhere. The name says what the byte IS; what a set bit
          would mean is [UNKNOWN].

          The bit-extraction arithmetic, since it is easy to get backwards: the tests are
          `rldicl. rX,r0,sh,63`, which selects LSB index `64 - sh` for the `sh` values 41..56 used
          at 0x8CA2BC-0x8CA420 (so those fifteen tests cover bits 8..21 and 23). Control: `sh=49` gives bit 15, and bit 15 is independently the one
          the create-game team-kill row sets and clears with `ori 32768` / `rlwinm 16,1,31` at
          0x8A5FA0-0x8A5FAC.
      - id: common_ab
        size: 2
        doc: |
          [ELF] 2-byte raw read (0xD43AF4) -> block+0xB1 (177). Renamed from `pair_0xb1`
          2026-08-02. **The two live Common Settings toggle bytes**, `common_a` then `common_b` in
          the canonical file - bits 23..16 and 15..8 of the flags word described under
          `common_flags_msb`. Capture-proven at 0x4310 wire 0x142 / 0x143 (the offsets are
          confirmed; the individual bits are not all identified).

          Kept as one raw 2 because that is how the parser reads it, and because the 0x4310
          builder and the 0x4302 row builder both copy the same two bytes as a unit.

          Archived values: `common_a` is 0x24 in 149 payloads, 0x2c in 63, with 0x25 and 0x34 once
          each; `common_b` is 0x00 in 170 and nonzero in 44, the 26 training-lobby captures among
          them. `common_a` bit 0 is the idle-kick enable - the single capture with
          `common_a = 0x25` is also the single capture with a nonzero `half_0xb4`, 214 for 214.
      - id: common_flags_lsb
        type: u1
        doc: |
          [ELF offset+width 0xD43B10 -> block+0xB3 (179); name ELF-derived] The **least
          significant byte** (bits 7..0) of that same 32-bit flags word. Renamed from
          `unknown_0xb3` 2026-08-02.

          It has its own u8 read here, distinct from the raw-2 covering `common_ab`, and the
          0x4310 builder splits the same way - so the four-byte word is three separate wire
          fields, not one. **Bits 0-7 are never tested** by any of the 117 flag-word sites, and
          the only load of struct+931 in the game-details carrier is the dead accessor 0x9072AC.

          Archived captures read 0x20 in 182 payloads and 0x00 in 32, and the split is **exactly**
          the split of `words_0x44[1]` (0x02000000 vs 0x00000000) - 214 for 214, the two fields
          never disagree. All 26 captures from lobby subtypes 7 and 8 (training) are in the zero
          group, plus six from subtypes 0 and 1. So the byte covaries with something about the
          session despite having no reader, which is a reason to echo it rather than invent it.
          Meaning [UNKNOWN].
      - id: idle_kick
        type: u2
        doc: |
          [ELF offset+width 0xD43B2C -> block+0xB4 (180); name INFERRED from capture]
          **The idle-kick threshold, in MINUTES.** Renamed from `half_0xb4` 2026-08-02.

          The unit is read from the binary, not guessed: in the game-details carrier 0x8CA424
          loads struct+932 and 0x8CA458 multiplies it by 60 before 0x8CA63C publishes it as
          property-store key 76. It is gated by `common_ab[0]` bit 0 - and that gate is confirmed
          by capture, 214 for 214: the one archived payload with `common_a = 0x25` is the one with
          a nonzero value here (3), and all 213 with bit 0 clear read 0x0000.
      - id: team_kill_kick
        type: u2
        doc: |
          [ELF offset+width 0xD43B48 -> block+0xB6 (182); name INFERRED from capture]
          **Team kills tolerated before a kick.** Renamed from `half_0xb6` 2026-08-02.

          Published as property-store key 69 at 0x8CA534/0x8CA608 - and note the client truncates
          there, `stb` after an `lhz`, so its own downstream copy cannot exceed 255 even though the
          wire field is 16 bits.

          **A gating claim that the captures REFUTE, recorded so it is not re-derived.** The
          create-game screen keeps flags-word bit 15 in step with this field (0x8A5F90-0x8A5FB0
          sets it when the count is nonzero and clears it when zero), which invites the reading
          that a clear bit 15 makes a nonzero count inert. It does not: 170 of the 214 archived
          0x4310 payloads carry `common_b = 0x00` - bit 15 clear - **with this field = 3**, and
          the publisher at 0x8CA534 copies the value out with no bit test at all. The invariant is
          local to that one screen. The canonical file's "zeroed when commonB bit 7 is clear" is
          therefore too strong; its `idle_kick` counterpart is not.
      - id: host_ping
        type: u4
        doc: |
          [ELF offset+width 0xD43B64 -> block+0xB8 (184); name ELF-derived, unit UNKNOWN]
          Renamed from `word_0xb8` 2026-08-02. **Not carried by 0x4310 or 0x4305**, so this
          family, 0x4313 and 0x43F1 are the only ways to set it and there is no archived capture
          of it.

          In the game-details carrier the hosted-game row synthesiser 0xD493CC does
          `lwz r0,936(r31)` at 0xD49548 and stores it at the row's T+0x20, which
          `mgo2_cmd_4302_s2c.ksy` calls `ping` and which the game picker at 0x934574-0x934590
          buckets against 20 and 80, preferring lower. **What is proven is the destination slot,
          not a unit** - and whether a Tournament/Survival record feeds that synthesiser at all is
          not claimed here.
      - id: capture_extra_time
        type: u1
        doc: |
          [ELF offset+width 0xD43B80 -> block+0xBC (188); name CONFIRMED from disc strings]
          **Capture Mission "EXTRA TIME"** - extend the round until a victor emerges. Renamed from
          `unknown_0xbc` 2026-08-02.

          A plain toggle: handler 0x8A02B4 is `x = x ? 0 : 1`, drawn as disc string 33 "ON" / 34
          "OFF", row label 507 "EXTRA TIME" under header 498 "Capture Mission", help 541
          *"Enabling this adds extra time to the end of the round until a victor emerges."*
          Published as property-store key 132. Archived captures read 0 in 207 and 1 in 7.
      - id: sneaking_snake_kills
        type: u1
        doc: |
          [ELF offset+width 0xD43B9C -> block+0xBD (189); name CONFIRMED from disc strings]
          **Sneaking Mission "SNAKE"** - how many times Snake must be defeated for Red and Blue to
          win. Renamed from `unknown_0xbd` 2026-08-02.

          It is a count, not a side index: 0x89D7B8 renders it as a number and the create-game
          adjuster 0x8A1AC8 clamps it to [1,5], where a side would be 0/1/2 drawn as a name. Disc
          row label 508 "SNAKE", units 520 "times", help 542 *"Set the number of times Snake must
          be defeated (victory condition for Red and Blue Teams)."* Published as property-store
          key 131. Archived captures read 3 in 175 of 214, then 5 (17), 2 (13) and 1 (9).
      - id: unread_tail
        size: 14
        doc: |
          [ELF] 14-byte raw read (0xD43BBC) -> block+0xBE (190..203). Last field; the block ends at
          0xCC = 204. Renamed from `tail_0xbe` 2026-08-02, matching the canonical file.

          **One raw read, so the parser draws no field boundaries in it at all**, and in the
          game-details carrier the client never reads or writes any byte of it: three touch points
          image-wide, the 0x4310 builder emitting it, the 0x4305 parser reading it, and the
          create-game initialiser memsetting it to zero at 0x89B5E8. All 214 archived payloads
          carry it entirely zero.

          PROTOCOL.md's subdivision of this region - byte-sized timers for Stealth DM, Interval,
          Solo Capture and Race - is a reference-server reading naming modes whose strings do not
          exist on this disc, and is **not** adopted. Splitting it needs live divergence testing,
          which no available build can do for a 0x4Axx command.
  triple:
    seq:
      - id: a
        type: u1
        doc: "[UNKNOWN] -> block+0x00+i"
      - id: b
        type: u1
        doc: "[UNKNOWN] -> block+0x10+i"
      - id: c
        type: u1
        doc: "[UNKNOWN] -> block+0x20+i"
