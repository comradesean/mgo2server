meta:
  id: mgo2_cmd_4b4b_s2c
  title: "MGO2 0x4b4b — clan/GHQ reply, result + 768-byte block (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD59EBC**, which re-checks the id (`cmpwi r0,19275`) before reading anything.

  Closes pending-request slot **102**. Destination buffer is memset to 0 over 769 bytes first
  (0x300 + 1 for the terminator the block reader writes), then 768 bytes are read with 0xD5D018
  when result == 0. Wire size on success: **772 bytes**; on error, 4.

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
  - id: result
    type: s4
    doc: "[ELF] 0 = success, block follows. Published to request slot 102."
  - id: block
    size: 768
    doc: |
      [ELF] 768 bytes read as one opaque fixed block (0xD5D018, len=0x300); the parser does not
      look inside it, and the client NUL-terminates at +768 — so the 769-byte destination means
      whatever consumes it treats it as a C string or a table of them. Contents [UNKNOWN]:
      nothing in this parser decodes a single byte of it.
