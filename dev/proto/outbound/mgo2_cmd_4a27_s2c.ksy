meta:
  id: mgo2_cmd_4a27_s2c
  title: "MGO2 0x4A27 - Tournament/Survival team roster status update, no id echo (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1). **0x4A27 is the same eight-member roster update as 0x4A02** - see
  mgo2_cmd_4a02_s2c.ksy for the full write-up. The post-RD_END walk is at 0xD4EE5C
  (`addi r29,r26,380` = team+0x17C, eight 28-byte slots), the same code as 0x4A02's at
  0xD4F0D4.

  TIER. Post-launch content; no available client build exercises 0x4A27, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  **THE DIFFERENCE FROM 0x4A02/0x4A22/0x4A29 is that 0x4A27 has no id echo at all.** Its only
  validation is the 6-byte identity header the shared helper 0xD49230 checks; there is no
  fourth-word compare against the event record id. And uniquely in that family its blob buffer
  really is 8 bytes as declared - `addi r29,r1,112` (0xD4EE28) to `addi r0,r1,120` (0xD4EE44) -
  so the size hazard recorded in the three sibling schemas does not apply here.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39980,
  parser 0xD4ED40.
  The shortest bodied reply in this family: no echo id at all, just one byte and eight more.
  The eight are read one at a time (loop 0xD4EE2C-0xD4EE58, base r1+112, bound r1+120 -
  eight iterations, NOT the 128 that the neighbouring 0x4A02/0x4A22/0x4A29 loops read; the
  loops look identical in shape and differ only in their bound, which is exactly the kind of
  detail that produces a silent desync if copied across ids).
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
  - id: unknown_0x06
    type: u1
    doc: "[UNKNOWN] read at 0xD4EE18 -> **team record +0x004** (`addi r4,r26,4`, r26 = 0xD491F8's object at session+0xD928 - not the event record at session+0xDBD0). No reader traced."
  - id: member_status
    size: 8
    doc: |
      [ELF] exactly 8 bytes, byte-at-a-time loop 0xD4EE28-0xD4EE54 into r1+112..r1+119, and the
      size here is correct as declared.
      **One byte per team member slot.** Byte `i` is the status of member slot `i` of the eight
      28-byte slots at team+0x17C: 0 clears the slot (`memset(slot,0,28)`), non-zero is stored
      at slot+0x15, and the parser fires event 20 with slot+0x11 once it finds the local
      player's own slot. Full semantics in mgo2_cmd_4a02_s2c.ksy. [UNKNOWN] what the codes mean.
