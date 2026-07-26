meta:
  id: mgo2_cmd_4905_s2c
  title: "MGO2 0x4905 — game-entry info reply, 822 bytes (server -> client)"
  endian: be
doc: |
  Parser 0xD4812C (338 instructions, ends 0xD48670), reached from dispatcher 0xD38804 via the
  stub at 0xD395C8. COMMANDS.md files 0x4905 under "0x49xx (0x4905–0x49C3) clan / GHQ / roster",
  parsed but never sent; neither PROTOCOL.md nor OBSERVED.md mentions it. Its request is one of
  the 0x4904–0x49C2 send-side gaps.

  This is a LARGE single-record reply — 822 bytes — not a result single. It is also the only id in
  this batch that calls a *shared* sub-record reader, so the layout below is in two parts.

  PRECONDITIONS AND GATES, in parser order:
    * header id check, cmpwi 0x4905 at 0xD4817C;
    * 0xD32E3C is called and its result compared with 1 (0xD48198) — a transaction-state
      precondition, not a wire field;
    * reader open 0xD5C844 (0xD481A4);
    * u32 result (0xD5CC64 at 0xD481B4). NONZERO branches to 0xD48604 and reads nothing more;
    * u32 (0xD5CCD8 at 0xD481D8). If the context object exists, this value must EQUAL the u32 at
      ctx+0x6D04 or the parser bails to 0xD4863C (0xD481FC–0xD4820C) — an echo of an id the
      client already holds, so it cannot be chosen freely by the server;
    * the 912-byte destination struct is memset to 0 (0xD48228) and the u32 above is stored at
      its offset 0 WITHOUT being re-read from the wire.
  On completion: status setter 0xD32E08 and result setter 0xD32E70, both on subsystem index
  0x39 (57) — 0xD48620 and 0xD48634.

  TOTAL WIRE LENGTH 822 BYTES (0x336): 46 before the nested block, 159 in it, 617 after.

  THE 159-BYTE NESTED BLOCK. At wire +0x2E the parser calls 0xD4364C (0xD48440) with a pointer to
  struct+0x40. That function (0xD4364C–0xD43BF4) is a straight-line reader — no loop, no
  back-edge — of 48 fields totalling **159 wire bytes** into a 204-byte struct region. It is a
  separate function rather than inline code, which is what a record shared with other commands
  looks like; which other parsers call it was NOT checked, so treat "shared" as [INFERRED].
  Its fields are enumerated below as `nested_block` so that the offsets of everything after it
  are anchored to something real, but every one of them is [UNKNOWN] in meaning.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CEB0 loop test.
seq:
  - id: result
    type: u4
    doc: |
      [ELF 0xD481B4] Nonzero → the parser stops here (branch at 0xD481CC), so the packet is
      4 bytes. Zero → the full 822-byte body follows.
  - id: echo_id
    type: u4
    doc: |
      [ELF 0xD481D8] Must match the u32 the client holds at ctx+0x6D04 or the whole packet is
      discarded (0xD4820C). [UNKNOWN] which id that is — the check is on identity, not value, so
      the correct server behaviour is to echo whatever the corresponding 0x4904 request carried.
      Stored at struct+0x00.
  - id: unknown_0x08
    type: u1
    doc: "[UNKNOWN] → struct+0x04. [ELF 0xD48244]"
  - id: unknown_0x09
    type: u1
    doc: "[UNKNOWN] → struct+0x05. [ELF 0xD48260]"
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] → struct+0x06. [ELF 0xD4827C]"
  - id: flags
    type: u1
    doc: |
      [UNKNOWN] A bit field: read as a 1-byte block (0xD5D018 r5=1 at 0xD48298) into a temp, then
      all 8 bits are expanded one at a time into a 64-bit word at struct+0x00 by the chain
      0xD482A4–0xD48368 (ori 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, then the sign bit as 0x01).
      Each bit is therefore a distinct boolean, exactly as in the 0x4902 entry. No consumer traced.
  - id: unknown_0x0c
    type: u2
    doc: "[UNKNOWN] → struct+0x08. [ELF 0xD4837C]"
  - id: unknown_0x0e
    size: 16
    doc: "[UNKNOWN] 16-byte block (0xD5D018 r5=16) → struct+0x0A; NUL-terminated on store, so a name-shaped field. [ELF 0xD4839C]"
  - id: unknown_0x1e
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x20 (std at 0xD483D8) — the time_t-shaped widening. [ELF 0xD483BC]"
  - id: unknown_0x22
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x28. [ELF 0xD483DC]"
  - id: unknown_0x26
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x30. [ELF 0xD483FC]"
  - id: unknown_0x2a
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x38. [ELF 0xD4841C]"
  - id: nested_block
    type: nested_block
    doc: |
      [ELF 0xD48440] 159 bytes read by the shared straight-line reader 0xD4364C into
      struct+0x40. See the top-level doc.
  - id: unknown_0xcd
    type: u2
    doc: "[UNKNOWN] → struct+0x10C. [ELF 0xD4845C]"
  - id: unknown_0xcf
    type: u2
    doc: "[UNKNOWN] → struct+0x10E. [ELF 0xD48478]"
  - id: unknown_0xd1
    type: u2
    doc: "[UNKNOWN] → struct+0x110. [ELF 0xD48494]"
  - id: unknown_0xd3
    type: u2
    doc: "[UNKNOWN] → struct+0x112. [ELF 0xD484B0]"
  - id: unknown_0xd5
    type: u4
    doc: "[UNKNOWN] → struct+0x114. [ELF 0xD484CC]"
  - id: unknown_0xd9
    size: 64
    doc: "[UNKNOWN] 64-byte block (0xD5D018 r5=64) → struct+0x118. [ELF 0xD484EC]"
  - id: unknown_0x119
    size: 512
    doc: |
      [UNKNOWN] 512-byte block (0xD5D018 r5=512) → struct+0x159. The single largest field in the
      lobby protocol seen so far; a comment/description block by size, but nothing was traced
      that reads it. [ELF 0xD4850C]
  - id: unknown_0x319
    type: u4
    doc: "[UNKNOWN] → struct+0x364. [ELF 0xD48528]"
  - id: unknown_0x31d
    type: u4
    doc: "[UNKNOWN] → struct+0x368. [ELF 0xD48544]"
  - id: unknown_0x321
    type: u4
    doc: "[UNKNOWN] → struct+0x36C. [ELF 0xD48560]"
  - id: unknown_0x325
    type: u4
    doc: "[UNKNOWN] → struct+0x370. [ELF 0xD4857C]"
  - id: unknown_0x329
    type: u4
    doc: "[UNKNOWN] → struct+0x374. [ELF 0xD48598]"
  - id: unknown_0x32d
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x378 (std at 0xD485CC). [ELF 0xD485B0]"
  - id: unknown_0x331
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x380 (std at 0xD485F0). [ELF 0xD485D0]"
  - id: unknown_0x335
    type: u1
    doc: "[UNKNOWN] last byte of the 822 → struct+0x388. [ELF 0xD485F4]"
types:
  nested_block:
    doc: |
      159 bytes, read by 0xD4364C (0xD4364C–0xD43BF4): 48 straight-line primitive calls, no loop
      and no back-edge, into a 204-byte struct region. Wire offsets below are relative to the
      start of the block (absolute wire +0x2E). "block struct+" is the offset inside the 204-byte
      region, which drifts ahead of the wire because 0xD5D018 NUL-terminates and the scalars
      re-align. Every field is [UNKNOWN] in meaning — the block's identity was not established.
    seq:
      - id: unknown_0x00
        type: u1
        doc: "[UNKNOWN] wire +0x00 -> block struct+0x00. [ELF 0xD4368C]"
      - id: unknown_0x01
        type: u1
        doc: "[UNKNOWN] wire +0x01 -> block struct+0x10. [ELF 0xD436B0]"
      - id: unknown_0x02
        type: u1
        doc: "[UNKNOWN] wire +0x02 -> block struct+0x20. [ELF 0xD436D0]"
      - id: unknown_0x03
        type: u1
        doc: "[UNKNOWN] wire +0x03 -> block struct+0x30. [ELF 0xD436F4]"
      - id: unknown_0x04
        type: u1
        doc: "[UNKNOWN] wire +0x04 -> block struct+0x31. [ELF 0xD43710]"
      - id: unknown_0x05
        size: 16
        doc: "[UNKNOWN] wire +0x05, 16 bytes (0xD5D018 r5=16) -> block struct+0x32. [ELF 0xD43730]"
      - id: unknown_0x15
        type: u1
        doc: "[UNKNOWN] wire +0x15 -> block struct+0x42. [ELF 0xD43744]"
      - id: unknown_0x16
        type: u1
        doc: "[UNKNOWN] wire +0x16 -> block struct+0x43. [ELF 0xD43760]"
      - id: unknown_0x17
        type: u4
        doc: "[UNKNOWN] wire +0x17 -> block struct+0x44. [ELF 0xD4377C]"
      - id: unknown_0x1b
        type: u4
        doc: "[UNKNOWN] wire +0x1b -> block struct+0x48. [ELF 0xD43790]"
      - id: unknown_0x1f
        type: u4
        doc: "[UNKNOWN] wire +0x1f -> block struct+0x4c. [ELF 0xD437AC]"
      - id: unknown_0x23
        type: u2
        doc: "[UNKNOWN] wire +0x23 -> block struct+0x50. [ELF 0xD437C8]"
      - id: unknown_0x25
        type: u2
        doc: "[UNKNOWN] wire +0x25 -> block struct+0x52. [ELF 0xD437E4]"
      - id: unknown_0x27
        type: u4
        doc: "[UNKNOWN] wire +0x27 -> block struct+0x54. [ELF 0xD43800]"
      - id: unknown_0x2b
        type: u4
        doc: "[UNKNOWN] wire +0x2b -> block struct+0x58. [ELF 0xD4381C]"
      - id: unknown_0x2f
        type: u2
        doc: "[UNKNOWN] wire +0x2f -> block struct+0x5c. [ELF 0xD43838]"
      - id: unknown_0x31
        type: u1
        doc: "[UNKNOWN] wire +0x31 -> block struct+0x5e. [ELF 0xD43854]"
      - id: unknown_0x32
        type: u1
        doc: "[UNKNOWN] wire +0x32 -> block struct+0x5f. [ELF 0xD43868]"
      - id: unknown_0x33
        type: u4
        doc: "[UNKNOWN] wire +0x33 -> block struct+0x60. [ELF 0xD43884]"
      - id: unknown_0x37
        type: u4
        doc: "[UNKNOWN] wire +0x37 -> block struct+0x64. [ELF 0xD438A0]"
      - id: unknown_0x3b
        type: u4
        doc: "[UNKNOWN] wire +0x3b -> block struct+0x68. [ELF 0xD438BC]"
      - id: unknown_0x3f
        type: u4
        doc: "[UNKNOWN] wire +0x3f -> block struct+0x6c. [ELF 0xD438D8]"
      - id: unknown_0x43
        type: u4
        doc: "[UNKNOWN] wire +0x43 -> block struct+0x70. [ELF 0xD438F4]"
      - id: unknown_0x47
        type: u4
        doc: "[UNKNOWN] wire +0x47 -> block struct+0x74. [ELF 0xD43910]"
      - id: unknown_0x4b
        type: u4
        doc: "[UNKNOWN] wire +0x4b -> block struct+0x78. [ELF 0xD4392C]"
      - id: unknown_0x4f
        type: u4
        doc: "[UNKNOWN] wire +0x4f -> block struct+0x7c. [ELF 0xD43948]"
      - id: unknown_0x53
        type: u4
        doc: "[UNKNOWN] wire +0x53 -> block struct+0x80. [ELF 0xD43964]"
      - id: unknown_0x57
        type: u4
        doc: "[UNKNOWN] wire +0x57 -> block struct+0x84. [ELF 0xD43980]"
      - id: unknown_0x5b
        type: u4
        doc: "[UNKNOWN] wire +0x5b -> block struct+0x88. [ELF 0xD4399C]"
      - id: unknown_0x5f
        type: u4
        doc: "[UNKNOWN] wire +0x5f -> block struct+0x8c. [ELF 0xD439B8]"
      - id: unknown_0x63
        type: u4
        doc: "[UNKNOWN] wire +0x63 -> block struct+0x90. [ELF 0xD439D4]"
      - id: unknown_0x67
        type: u4
        doc: "[UNKNOWN] wire +0x67 -> block struct+0x94. [ELF 0xD439F0]"
      - id: unknown_0x6b
        type: u4
        doc: "[UNKNOWN] wire +0x6b -> block struct+0x98. [ELF 0xD43A0C]"
      - id: unknown_0x6f
        type: u4
        doc: "[UNKNOWN] wire +0x6f -> block struct+0x9c. [ELF 0xD43A28]"
      - id: unknown_0x73
        type: u4
        doc: "[UNKNOWN] wire +0x73 -> block struct+0xa0. [ELF 0xD43A44]"
      - id: unknown_0x77
        type: u4
        doc: "[UNKNOWN] wire +0x77 -> block struct+0xa4. [ELF 0xD43A60]"
      - id: unknown_0x7b
        size: 2
        doc: "[UNKNOWN] wire +0x7b, 2 bytes (0xD5D018 r5=2) -> block struct+0xa8. [ELF 0xD43A80]"
      - id: unknown_0x7d
        type: u2
        doc: "[UNKNOWN] wire +0x7d -> block struct+0xaa. [ELF 0xD43A9C]"
      - id: unknown_0x7f
        type: u4
        doc: "[UNKNOWN] wire +0x7f -> block struct+0xac. [ELF 0xD43AB8]"
      - id: unknown_0x83
        type: u1
        doc: "[UNKNOWN] wire +0x83 -> block struct+0xb0. [ELF 0xD43AD4]"
      - id: unknown_0x84
        size: 2
        doc: "[UNKNOWN] wire +0x84, 2 bytes (0xD5D018 r5=2) -> block struct+0xb1. [ELF 0xD43AF0]"
      - id: unknown_0x86
        type: u1
        doc: "[UNKNOWN] wire +0x86 -> block struct+0xb3. [ELF 0xD43B0C]"
      - id: unknown_0x87
        type: u2
        doc: "[UNKNOWN] wire +0x87 -> block struct+0xb4. [ELF 0xD43B28]"
      - id: unknown_0x89
        type: u2
        doc: "[UNKNOWN] wire +0x89 -> block struct+0xb6. [ELF 0xD43B44]"
      - id: unknown_0x8b
        type: u4
        doc: "[UNKNOWN] wire +0x8b -> block struct+0xb8. [ELF 0xD43B60]"
      - id: unknown_0x8f
        type: u1
        doc: "[UNKNOWN] wire +0x8f -> block struct+0xbc. [ELF 0xD43B7C]"
      - id: unknown_0x90
        type: u1
        doc: "[UNKNOWN] wire +0x90 -> block struct+0xbd. [ELF 0xD43B98]"
      - id: unknown_0x91
        size: 14
        doc: "[UNKNOWN] wire +0x91, 14 bytes (0xD5D018 r5=14) -> block struct+0xbe. [ELF 0xD43BB4]"
