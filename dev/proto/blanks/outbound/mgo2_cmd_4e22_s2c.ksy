meta:
  id: mgo2_cmd_4e22_s2c
  title: "MGO2 0x4e22 — context update, 8 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD5A3F0**, which re-checks the id (`cmpwi r0,20002`) before reading anything.

  Opens with the shared header validator **0xD49230** (u4 + u2, checked against the client's
  current context; mismatch = -1018 and the packet is dropped), then reads just two bytes. No
  request slot; fires **UI event 39** (0xD33CD8) on success, after memsetting a 28-byte scratch
  area and comparing one of the bytes against 7 and -1.

  Wire size: **8 bytes**. 0x4e22 and 0x4e23 have byte-identical layouts (parsers 0xD5A3F0 and
  0xD5A1D0 differ only in the id compared, the UI event fired, and the extra call noted above),
  so they are almost certainly a pair over the same record.

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
  - id: context_id
    type: u4
    doc: "[ELF] Validated against ctx+0x00 by 0xD49230. [UNKNOWN]"
  - id: context_seq
    type: u2
    doc: "[ELF] Validated against ctx+0x29C by 0xD49230. [UNKNOWN]"
  - id: unknown_06
    type: u1
    doc: "[ELF] -> obj+0x04. Later compared against 7 and against -1 before the UI event, so it is an enum/index with a sentinel, not a boolean. [UNKNOWN]"
  - id: unknown_07
    type: u1
    doc: "[ELF] Last byte. [UNKNOWN]"
