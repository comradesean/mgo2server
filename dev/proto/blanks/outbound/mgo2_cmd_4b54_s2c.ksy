meta:
  id: mgo2_cmd_4b54_s2c
  title: "MGO2 0x4b54 — clan/GHQ list ITEMS, 68-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD57E10**, which re-checks the id (`cmpwi r0,19284`) before reading anything.

  Middle packet of the 0x4b53 / 0x4b54 / 0x4b55 triple (see mgo2_cmd_4b53.ksy). Sends NO request
  slot update at all — it only appends records, which is why the start and end packets exist.

  **Count source: size-driven, no count field.** The loop (0xD57E7C-0xD5800C) calls 0xD5CEB0
  before each record and stops when the read cursor reaches the payload length. Records are
  APPENDED at list+8+n*76 with the running count at list+4; the client refuses at n > 63, so at
  most **64** records fit — a 65th record is a hard parse failure (-71), not a truncation.
  List object: session[+0x10000+6404] + 0x20000 + 16360.

  Wire record = 68 bytes; client struct = 76 bytes (8 bytes of padding/derived fields never on
  the wire). A payload whose length is not 4 + a multiple of 68 will desync — the readers
  bound-check the 1023-byte receive buffer, not the payload (PROTOCOL.md).

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 s4, 0xD5CCD8 u4, 0xD5D018 fixed byte block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. In each
  signed/unsigned pair the LOWER address is the signed accessor (write-side proof: 0xD5C95C uses
  `sraw`, 0xD5C9BC uses `srw`). Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare): that rule holds on the WRITE side
  only. The READ pair 0xD5CC64 / 0xD5CCD8 is instruction-for-instruction identical — same
  `cmpwi 1020` bound check, same byte-assembly loop — so neither is a signed accessor. Where a
  field below is typed s4, the evidence is the CALLER reloading the value with `lwa` (or the
  field being a known-negative error code), never the primitive's address.

seq:
  - id: records
    type: record
    repeat: eos
    doc: "[ELF] Size-driven; see the top-level doc. No leading count."
types:
  record:
    doc: "68 wire bytes -> 76-byte client struct."
    seq:
      - id: unknown_00
        type: u4
        doc: "[ELF] struct+0x00. [UNKNOWN]"
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x04, 16 bytes fixed. [UNKNOWN] whose name."
      - id: unknown_15
        type: u1
        doc: "[ELF] struct+0x15. [UNKNOWN]"
      - id: unknown_18
        type: u4
        doc: "[ELF] struct+0x18. [UNKNOWN]"
      - id: unknown_30
        type: u4
        doc: "[ELF] struct+0x30 — read here, out of struct order. [UNKNOWN]"
      - id: unknown_1c
        type: u2
        doc: "[ELF] struct+0x1c. [UNKNOWN]"
      - id: name_2
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x1e, 16 bytes fixed. [UNKNOWN]"
      - id: unknown_34
        type: u4
        doc: "[ELF] struct+0x34. [UNKNOWN]"
      - id: name_3
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x38, 16 bytes fixed. [UNKNOWN]"
      - id: unknown_49
        type: u1
        doc: "[ELF] struct+0x49, last byte of the record. [UNKNOWN]"
