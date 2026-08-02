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
      same 7296-byte layout.
  So 0x4A00 does NOT share a destination struct with 0x4A24/0x4A31.

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
  - id: unknown_0x0a
    type: u1
    doc: |
      [UNKNOWN] read at 0xD50FC4 -> team+0x004, i.e. into the team record at session+0xD928 that
      0xD491F8 returns, not into the detail record. **No negative is claimed for this one.** A
      reader would appear as a load at displacement 4 off whatever register holds the team
      record, and displacement 4 is far too common for a displacement sweep to discriminate;
      a sweep that cannot be validated against a known-good hit is worthless, so none is
      reported. Meaning unestablished.
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
      0xD4364C-0xD43BC0. Size is certain; whether the game-settings meanings carry over to a
      0x4Axx record is [UNKNOWN], the byte boundaries are not.
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
        doc: "[UNKNOWN] 0xD436F4 -> block+0x30."
      - id: unknown_0x31
        type: u1
        doc: "[UNKNOWN] 0xD43710 -> block+0x31."
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
      - id: unknown_0x42
        type: u1
        doc: "[UNKNOWN] 0xD43744 -> block+0x42."
      - id: unknown_0x43
        type: u1
        doc: "[UNKNOWN] 0xD43760 -> block+0x43."
      - id: words_0x44
        type: u4
        repeat: expr
        repeat-expr: 3
        doc: "[UNKNOWN] 0xD4377C / 0xD43790 / 0xD437AC -> block+0x44, +0x48, +0x4C."
      - id: half_0x50
        type: u2
        doc: "[UNKNOWN] 0xD437C8 -> block+0x50."
      - id: half_0x52
        type: u2
        doc: "[UNKNOWN] 0xD437E4 -> block+0x52."
      - id: word_0x54
        type: u4
        doc: "[UNKNOWN] 0xD43800 -> block+0x54."
      - id: word_0x58
        type: u4
        doc: "[UNKNOWN] 0xD4381C -> block+0x58."
      - id: half_0x5c
        type: u2
        doc: "[UNKNOWN] 0xD43838 -> block+0x5C."
      - id: unknown_0x5e
        type: u1
        doc: "[UNKNOWN] 0xD43854 -> block+0x5E."
      - id: unknown_0x5f
        type: u1
        doc: "[UNKNOWN] 0xD43868 -> block+0x5F."
      - id: words_0x60
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: "[UNKNOWN] 18 consecutive u32 reads, 0xD43884 through 0xD43A60 -> block+0x60..+0xA4. Unrolled in the binary, not a loop, so there is no count field."
      - id: pair_0xa8
        size: 2
        doc: "[UNKNOWN] 2-byte raw read (0xD43A80) -> block+0xA8. Read as raw, not as u16, so treat as two bytes."
      - id: half_0xaa
        type: u2
        doc: "[UNKNOWN] 0xD43A9C -> block+0xAA."
      - id: word_0xac
        type: u4
        doc: "[UNKNOWN] 0xD43AB8 -> block+0xAC."
      - id: unknown_0xb0
        type: u1
        doc: "[UNKNOWN] 0xD43AD4 -> block+0xB0."
      - id: pair_0xb1
        size: 2
        doc: "[UNKNOWN] 2-byte raw read (0xD43AF4) -> block+0xB1."
      - id: unknown_0xb3
        type: u1
        doc: "[UNKNOWN] 0xD43B10 -> block+0xB3."
      - id: half_0xb4
        type: u2
        doc: "[UNKNOWN] 0xD43B2C -> block+0xB4."
      - id: half_0xb6
        type: u2
        doc: "[UNKNOWN] 0xD43B48 -> block+0xB6."
      - id: word_0xb8
        type: u4
        doc: "[UNKNOWN] 0xD43B64 -> block+0xB8."
      - id: unknown_0xbc
        type: u1
        doc: "[UNKNOWN] 0xD43B80 -> block+0xBC."
      - id: unknown_0xbd
        type: u1
        doc: "[UNKNOWN] 0xD43B9C -> block+0xBD."
      - id: tail_0xbe
        size: 14
        doc: "[UNKNOWN] 14-byte raw read (0xD43BBC) -> block+0xBE. Last field; the block ends at 0xCC = 204."
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
