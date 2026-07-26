meta:
  id: mgo2_cmd_4b75_s2c
  title: "MGO2 0x4b75 — clan/GHQ list ITEMS, 93-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD55E40**, which re-checks the id (`cmpwi r0,19317`) before reading anything.

  Middle packet of the 0x4b74 / 0x4b75 / 0x4b76 triple (see mgo2_cmd_4b74.ksy). No request-slot
  update.

  **Count source: size-driven, no count field** (0xD5CEB0 test at 0xD55ED8, loop back at
  0xD55FCC). Records are appended at list+8+n*96 with the count at list+4; the client refuses at
  n > 31, so at most **32** records. List object: session[+0x10000+6404] + 0x20000 + 29724.

  Wire record = 93 bytes; client struct = 96.

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
    doc: "93 wire bytes -> 96-byte client struct."
    seq:
      - id: unknown_00
        type: u4
        doc: "[ELF] struct+0x00. [UNKNOWN]"
      - id: text_04
        size: 64
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x04, 64 bytes fixed (client NULs at +0x44). 64 is comment/message sized. [UNKNOWN]"
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x45, 16 bytes fixed. [UNKNOWN] whose name."
      - id: unknown_56
        type: u1
        doc: "[ELF] struct+0x56. [UNKNOWN]"
      - id: unknown_58
        type: s4
        doc: "[ELF] struct+0x58. Read with the SIGNED accessor 0xD5CC64, so negatives are expected. [UNKNOWN]"
      - id: unknown_5c
        type: u4
        doc: "[ELF] struct+0x5c, last 4 bytes of the record. [UNKNOWN]"
