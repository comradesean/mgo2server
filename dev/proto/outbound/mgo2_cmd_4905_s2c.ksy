meta:
  id: mgo2_cmd_4905_s2c
  title: "MGO2 0x4905 — game-entry info reply, 867 bytes (server -> client)"
  endian: be
doc: |
  Parser 0xD4812C (338 instructions, ends 0xD48670), reached from the GAME dispatcher 0xD387C8 (compare tree at 0xD38804) via the
  stub at 0xD395C8. COMMANDS.md files 0x4905 under "0x49xx (0x4905–0x49C3) clan / GHQ / roster",
  parsed but never sent; neither PROTOCOL.md nor OBSERVED.md mentions it. Its request is one of
  the 0x4904–0x49C2 send-side gaps.

  This is a LARGE single-record reply — 867 bytes — not a result single. It is also the only id in
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

  TOTAL WIRE LENGTH 867 BYTES (0x363): 46 before the nested block, **204** in it, 617 after.

  **CORRECTION (2026-07-26, re-derived from the ELF).** An earlier revision of this file called
  0xD4364C "a straight-line reader — no loop, no back-edge — of 48 fields totalling 159 wire
  bytes", and gave the total as 822. That was wrong and it was wire-breaking. The reader **does**
  loop: the back-edge is `bne cr6,0xd43678` at **0xD436E4** with bound `cmpdi cr6,r27,16` at
  **0xD436D8**. Sixteen iterations of three u8 reads (0xD4368C / 0xD436B0 / 0xD436D0) consume
  **48** wire bytes, not 3, so the block is **204 wire bytes** — identical to its 204-byte
  destination region, which is the independent check. 867 − 822 = 45 = 48 − 3, and every field
  after wire +0x2E moves 45 bytes later. Their offsets below were re-derived from the parser's
  own destination offsets (0xD4845C..0xD485F4), not obtained by adding 45.

  THE 204-BYTE NESTED BLOCK. At wire +0x2E the parser calls 0xD4364C (0xD48440) with a pointer to
  struct+0x40. That block is **not** private to 0x4905: 0xD4364C has **nine** call sites —
  0xD445A4 (0x4313), 0xD48440 (here), 0xD48964 (0x4909), 0xD4B244 (0x4987), 0xD4CB08 (0x4950),
  0xD5006C (the shared 0x4A24/0x4A31 parser), 0xD51014 (0x4A00), 0xD5AF38 (0x4E10) and
  0xD5B78C (0x43F1). "Shared" is therefore [ELF], not [INFERRED].

  **The block is modelled once, canonically, in `mgo2_cmd_4313_s2c.ksy` as type
  `game_settings`** — the best-evidenced copy, because 0x4313's is the one whose field names are
  backed by live capture (the 0x4310 push and the 0x4305 reply; see OBSERVED.md). It is kept
  opaque here so the two cannot drift. Whether the *semantics* of the game-settings block apply
  to a 0x4905 record is [UNKNOWN]; the 204 wire bytes and their internal boundaries are not.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CEB0 loop test.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: result
    type: u4
    doc: |
      [ELF 0xD481B4] Nonzero → the parser stops here (branch at 0xD481CC), so the packet is
      4 bytes. Zero → the full 867-byte body follows.
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
    size: 204
    doc: |
      [ELF 0xD48440] 204 bytes read by the shared reader 0xD4364C into struct+0x40. Layout is
      modelled once in `mgo2_cmd_4313_s2c.ksy`, type `game_settings`; kept opaque here so the
      copies cannot drift. Note the leading 48 bytes are **interleaved**: 16 wire triples
      {u8 -> block+i, u8 -> block+0x10+i, u8 -> block+0x20+i}, not three contiguous runs.
  - id: unknown_0xfa
    type: u2
    doc: "[UNKNOWN] -> struct+0x10C. [ELF 0xD4845C]"
  - id: unknown_0xfc
    type: u2
    doc: "[UNKNOWN] -> struct+0x10E. [ELF 0xD48478]"
  - id: unknown_0xfe
    type: u2
    doc: "[UNKNOWN] -> struct+0x110. [ELF 0xD48494]"
  - id: unknown_0x100
    type: u2
    doc: "[UNKNOWN] -> struct+0x112. [ELF 0xD484B0]"
  - id: unknown_0x102
    type: u4
    doc: "[UNKNOWN] -> struct+0x114. [ELF 0xD484CC]"
  - id: unknown_0x106
    size: 64
    doc: "[UNKNOWN] 64-byte block (0xD5D018 r5=64) -> struct+0x118. [ELF 0xD484EC]"
  - id: unknown_0x146
    size: 512
    doc: |
      [UNKNOWN] 512-byte block (0xD5D018 r5=512) -> struct+0x159 — note the destination jumps
      one byte past the 64-byte block's NUL at struct+0x158. The single largest field in the
      lobby protocol seen so far; a comment/description block by size, but nothing was traced
      that reads it. [ELF 0xD4850C]
  - id: unknown_0x346
    type: u4
    doc: "[UNKNOWN] -> struct+0x364. [ELF 0xD48528]"
  - id: unknown_0x34a
    type: u4
    doc: "[UNKNOWN] -> struct+0x368. [ELF 0xD48544]"
  - id: unknown_0x34e
    type: u4
    doc: "[UNKNOWN] -> struct+0x36C. [ELF 0xD48560]"
  - id: unknown_0x352
    type: u4
    doc: "[UNKNOWN] -> struct+0x370. [ELF 0xD4857C]"
  - id: unknown_0x356
    type: u4
    doc: "[UNKNOWN] -> struct+0x374. [ELF 0xD48598]"
  - id: unknown_0x35a
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x378 (std at 0xD485CC). [ELF 0xD485B0]"
  - id: unknown_0x35e
    type: u4
    doc: "[UNKNOWN] widened to 64 bits at struct+0x380 (std at 0xD485F0). [ELF 0xD485D0]"
  - id: unknown_0x362
    type: u1
    doc: "[UNKNOWN] last byte of the 867 -> struct+0x388. [ELF 0xD485F4]"
