meta:
  id: mgo2_cmd_4a01_s2c
  title: "MGO2 0x4A01 - Tournament/Survival event update with per-entrant status array (server -> client)"
  endian: be
params:
  - id: blob_len
    type: u4
    doc: |
      NOT A WIRE FIELD. min(u16 at event record +0x0DA, 128), taken from client state at
      0xD50800. **That u16 is `halves[2]`, the entrant count** (mgo2_cmd_4a24_s2c.ksy), and 128
      is the entrant-table capacity - so the blob is exactly **one byte per entrant**.
      Declared as a parameter so nobody mistakes it for a fixed 128 bytes.
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); mgo2_cmd_4a24_s2c.ksy is canonical for the event record. **0x4A01 is a
  full update of that record** - it writes the same slots 0x4A24 does, plus the one thing
  0x4A24 has no field for: a **per-entrant status byte array**.

  TIER. Post-launch content; no available client build exercises 0x4A01, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  IT IS THE SAME RECORD, AND THAT IS PROVEN, NOT ASSUMED. The base is
  `addis r31,r24,1` / `addi r27,r31,-9264` = **session+0xDBD0** (0xD5067C-0xD50688), byte for
  byte the base computation 0x4A24 and 0x4A00 use. So every offset below is an offset into the
  7296-byte event record and the 0x4A24 names transfer directly.

  **THE BLOB IS THE ENTRANT STATUS COLUMN.** After RD_END the parser walks the entrant table
  and writes byte `i` of the blob to `table + 261 + 52*i` for `i < halves[2]`, capped at 129
  iterations (0xD509F8-0xD50A3C). Table base is +0x0F0 = 240 and 261 - 240 = **0x15**, which is
  exactly the `status` byte of one entrant row - the field 0x4A11 and 0x4A33 set one row at a
  time. So 0x4A01 replaces the whole column in one packet. Cross-packet bijection by struct
  offset; the identical loop is in 0x4A20's parser at 0xD51C5C-0xD51CA0.
  It then fires **event 21** with the record's `phase` byte (+0x0D4) as payload
  (0xD50A40-0xD50A4C), which is the "event state changed" notification.
  For the record: **this is the parser at 0xD50700-0xD50A60**, and it belongs to **0x4A01**,
  not to 0x4A22 or 0x4A29 - `cmpwi r0,0x4A01` at 0xD50608 is the only id compare in the
  function.

  THE BLOB LENGTH IS NOT ON THE WIRE. The byte loop at 0xD507DC-0xD50814 runs while
  `i < u16 at +0x0DA` AND `i < 128` (0xD507F4 / 0xD50800 / 0xD50808), i.e. the count comes from
  client state, from whichever packet last wrote `halves[2]`. Getting this wrong desyncs
  everything after it. The eight u16s this packet reads land in that same +0x0D6..+0x0E4
  array - see `halves` below - so a self-consistent server that sends the correct count in the
  same packet still does not change the bound for THIS parse, because the store happens before
  the blob is read.
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230, not by this parser
  directly: u32 then u16, both validated against the client's currently open object for this
  subsystem (0xD4929C and 0xD492D4); a mismatch aborts with -1018 before another byte is read.
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
    doc: "[ELF] identity header, helper 0xD49230 (0xD49274)."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230 (0xD492B0)."
  - id: event_id
    type: u4
    doc: "[ELF] read at 0xD5066C, compared at 0xD50694 against **event record +0x000** (`lwz r0,0(r23)`, r23 = session+0xDBD0); mismatch aborts with -1106 and nothing further is read. Same id as 0x4A24's `obj_id`, i.e. what 0x4A00 stamped. Not a result code: it is compared against stored state, never sign-extended into 0xD32E70, and this command consumes no request slot."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD506A8 -> the currently open object's +0x004 (0xD491F8's object, i.e. the TEAM record, not the event record - the two are adjacent, session+0xD928 and session+0xDBD0, so keep them apart). No reader traced."
  - id: phase
    type: u1
    doc: |
      [ELF] read at 0xD506C4 -> `addi r4,r31,-9052` = **event record +0x0D4**. This is
      mgo2_cmd_4a24_s2c.ksy's `phase`, named there from 0x8F95D8, which computes
      `(u8)(phase - 2) <= 8` and picks screen state 14 or 26. It is also this parser's event-21
      payload (0xD50A44 re-reads +0x0D4). Struct-offset bijection with 0x4A24 - the previous
      reading of this byte as "a second object's +0x000" was wrong.
      [UNKNOWN] what the individual codes mean; nothing enumerates them.
  - id: halves
    type: u2
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] eight u16, unrolled 0xD506E0-0xD507A4, stored at **event record +0x0D6, +0x0D8,
      +0x0DA, +0x0DC, +0x0DE, +0x0E0, +0x0E2, +0x0E4** (`addi r4,r31,-9050` through `-9036`).
      Same eight slots, same order as 0x4A24's `halves`, so the names carry over verbatim:
      [0] entrant cap, [1] no reader, **[2] entrant count**, **[3] round count**, [4] no
      reader, **[5] current round**, [6] and [7] no reader. See mgo2_cmd_4a24_s2c.ksy for the
      readers and for the sweep behind the four negatives.
      Two of them are also pushed outward by this parser: 0xD509E8-0xD509F4 copies [3] and [5]
      into the object 0xD3F7B0 returns, at its +0x0C and +0x10 - the same two slots 0x4A13
      fills directly.
      **[2] is what bounds this packet's own `blob`**, but from the stored value, not this one.
  - id: unknown_0x1c
    type: u4
    doc: "[UNKNOWN] read at 0xD507BC and widened to 64 bits at event record +0x1BF0 - the same slot and the same widening as 0x4A24's `unknown_0x19` (0xD4FE24) and 0x4A00's `unknown_after_block` (0xD5127C). Three commands write it and **nothing reads it**; 0x4A24 carries the sweep and its control."
  - id: entrant_status
    size: blob_len
    doc: |
      [ELF] byte-at-a-time loop 0xD507DC-0xD50814 into a 128-byte stack buffer (memset at
      0xD50624). Length = min(event record +0x0DA, 128) = **one byte per entrant** - see the
      top-level note.
      **Each byte is one entrant's `status`**: 0xD509F8-0xD50A3C copies byte `i` to
      `table + 261 + 52*i` = entrant row `i`, offset 0x15, the same field 0x4A11/0x4A33 set per
      row. [UNKNOWN] what the status codes mean.
  - id: flags
    type: u1
    doc: "[ELF] 1-byte raw read (0xD5082C) expanded bit by bit by the `oris` ladder at 0xD50840-0xD508FC into the 64-bit word at the record's +0x000, landing bit-reversed in the single byte **event record +0x004** - the identical ladder 0x4A24 (0xD4FF60) and 0x4A00 (0xD5105C) use, so all three must agree on the bit meanings. [UNKNOWN] individually; no consumer identified for any of the eight."
  - id: unknown_after_flags
    type: u1
    doc: "[UNKNOWN] read at 0xD5090C -> **event record +0x005**. Same slot as 0x4A24's `unknown_after_flags` and 0x4A00's `unknown_last`. **No reader** - 0x4A24 carries the sweep (both windows, displacement 5) and its control (the +0x0D4 reader one byte-field away)."
  - id: trailing_words
    type: u4
    repeat: expr
    repeat-expr: 6
    doc: "[ELF] six u32, unrolled 0xD50928-0xD509B4 -> **event record +0x1C64..+0x1C78** - the same six slots 0x4A24/0x4A31 fill. [UNKNOWN] meanings, and **none of the six has a reader**; 0x4A24 carries the sweep and its control (the readers of +0x1C40 and +0x1C60, which bracket this range). Written by two commands, read by none."
