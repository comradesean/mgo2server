meta:
  id: mgo2_cmd_4a28_s2c
  title: "MGO2 0x4A28 - Tournament/Survival final standings and reward (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); mgo2_cmd_4a24_s2c.ksy is canonical for the event record. **0x4A28
  delivers the result**: the eight standings words and the reward, which together are the two
  substitutions of lobby string **742**, *"The championship match has ended.\nWinning team:
  %s\nYour reward: %d"*.

  TIER. Post-launch content; no available client build exercises 0x4A28, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  Destination is the event record at session+0xDBD0; the fields below land at +0x1C40 and
  +0x1C60, the same slots 0x4A24 fills, so the names transfer by struct-offset bijection.
  0x4A28 is the **only** writer of +0x1C60, which 0x4A24 does not carry a field for at all.
  After parsing it pushes +0x1C60 into the automatch object at that object's +0x8C and fires
  **event 29**.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39990,
  parser 0xD50CDC.
  An echo id then a FIXED eight-word array then one more word. The eight is a hard-coded
  loop bound (`cmpdi r31,8` at 0xD50DE8, stride 4 into obj+0x1C40), not a count on the wire -
  worth stating because most list replies in this range are size-driven and this one is neither.
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
  - id: event_id
    type: u4
    doc: "[ELF] read at 0xD50D90, compared at 0xD50DB8 against **event record +0x000**; mismatch aborts with -1106. Same id as 0x4A24's `obj_id`, i.e. what 0x4A00 stamped. **Not a result code**: compared against stored state, never sign-extended into 0xD32E70, and this command consumes no request slot."
  - id: standings
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] exactly 8 u32, loop 0xD50DC4-0xD50DF4 -> **event record +0x1C40 + 4*i**. Fixed
      count, no wire length.
      **`standings[0]` is the winning team's id**: 0x8CC414 and 0x8CDA2C scan the entrant table
      for the row whose id at +0x00 equals +0x1C40 and print that row's name as the `%s` of
      lobby string 742. See mgo2_cmd_4a24_s2c.ksy, which carries the reader addresses and the
      sweep showing **`standings[1..7]` have no reader** (runner-up placings is the obvious
      reading beside a winner, but nothing in this build displays them, so it stays [INFERRED]).
      0x4A24 is the only other writer of these eight slots.
  - id: reward
    type: u4
    doc: |
      [ELF] read at 0xD50E04 -> **event record +0x1C60**. **The `%d` of lobby string 742,
      \"Your reward: %d\"** - and the same number the other reward sentences use (762 *"Match
      #%d has ended... Your reward: %d"*, 763, 765, 767). 0x4A28 is its only writer: 0x4A24
      stops at +0x1C40..+0x1C5C and resumes at +0x1C64, leaving this slot alone. The parser
      also copies it into the automatch object at +0x8C before firing event 29.
