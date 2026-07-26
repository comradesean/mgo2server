meta:
  id: mgo2_cmd_4b92_s2c
  title: "MGO2 0x4b92 — clan/GHQ list ITEMS, 44-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD55B04**, which re-checks the id (`cmpwi r0,19346`) before reading anything.

  Middle packet of the 0x4b91 / 0x4b92 / 0x4b93 triple (see mgo2_cmd_4b91.ksy). No request-slot
  update. Additional precondition: the list object pointer session[+0x10000+6404] must be
  non-NULL and its first word non-zero — i.e. **0x4b91 must have armed the gate first**, or this
  packet is rejected with -73.

  **Count source: size-driven, no count field** (0xD5CEB0 at 0xD55BB0, loop back at 0xD55C90).
  Records appended at list+16+n*60 with the count at list+4; refused at n > 99, so at most
  **100** records. List object: session[+0x10000+6404] + 0x20000 + 10344.

  Wire record = 44 bytes; client struct = 60 (copied as 32 + 28 bytes by the `lswi/stswi` pair at
  0xD55C78).

  The paired REQUEST builder sits right after this parser at 0xD55CE4 and emits **0x4b90**
  (`li r4,19344` at 0xD55D94) with {u8, u8, bytes[16]}, then sets slot 114 to state 1 — that is
  the client->server side of this triple, recorded here because it is the only place it appears.

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
    doc: "[ELF] Size-driven; no leading count."
types:
  record:
    doc: "44 wire bytes -> 60-byte client struct."
    seq:
      - id: unknown_00
        type: u4
        doc: "[ELF] struct+0x00. [UNKNOWN]"
      - id: name_a
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x04, 16 bytes fixed. [UNKNOWN]"
      - id: unknown_18
        type: u4
        doc: "[ELF] struct+0x18. [UNKNOWN]"
      - id: name_b
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x1c, 16 bytes fixed. [UNKNOWN]"
      - id: unknown_30
        type: u4
        doc: "[ELF] struct+0x30, last 4 bytes of the record. [UNKNOWN]"
