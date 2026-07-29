meta:
  id: mgo2_cmd_4212_s2c
  title: "MGO2 0x4212 — list records for the 0x4210 triple (server -> client)"
  endian: be
doc: |
  Parser **0xd3b2d0** (GAME dispatcher 0xd38804, trampoline 0xd39180). Middle packet of the
  `0x4211`/`0x4212`/`0x4213` triple; fires no notification of its own.

  **Record count is size-driven**, like `0x2003` and `0x200a`: the loop head at 0xd3b338 zeroes a
  28-byte scratch (`vxor`/`stvx` plus two stores) and calls `MORE_DATA?` (0xd5ceb0 at 0xd3b358);
  when the cursor reaches the payload length it exits to `READ_END`. Records are `memcpy`d
  (`lswi`/`stswi`, 28 bytes) into `list + 8 + n*28` and the persistent count at `4(r31)` is
  incremented, so records accumulate across packets.

  **Client capacity is 1000 records**: `lwz r4,4(r31); cmpwi r4,999; bgt -> bail(-71)` at
  0xd3b3c0-0xd3b3cc; the compare itself is at **0xd3b3c4**. That is a far larger cap than any other list in the protocol (`0x2003` allows 32,
  `0x200a` 10), which suggests a history or roster rather than a menu.

  Read primitives in order: u32 (0xd3b370), fixed[16] (0xd3b390), u32 (0xd3b3ac) = **24 wire
  bytes**, 28 bytes per record in the client struct.

  Semantics unknown. PROTOCOL.md's `0x4102` section notes that `T+0x3330` "turned out to be match
  history list storage for `0x4682`/`0x4212` records", which pairs this command with the met-players
  history record `0x4682` (25 wire bytes: see dev/proto/outbound/mgo2_cmd_4682_s2c.ksy) — a comparable
  `{id, 16-byte name, extra}` shape. Treat that as a lead, not an identification.
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats" (the T+0x3330 note)
seq:
  - id: records
    type: list_record
    repeat: eos
    doc: "[ELF] Size-driven repeat (MORE_DATA? at 0xd5ceb0). Max 1000 across all 0x4212 packets."
types:
  list_record:
    doc: "24 wire bytes -> 28-byte client struct record."
    seq:
      - id: unknown_00
        type: u4
        doc: "[UNKNOWN] Wire +0 -> record +0. Position exact. By shape (leading u32 before a 16-byte name) this is an id in every other list in the protocol, but nothing here confirms it."
      - id: unknown_04
        size: 16
        doc: "[UNKNOWN] Wire +4 -> record +4, fixed 16 bytes (NUL written at +20). A 16-byte field is a character or lobby name everywhere else in the protocol; unconfirmed here."
      - id: unknown_14
        type: u4
        doc: "[UNKNOWN] Wire +0x14 -> record +24."
