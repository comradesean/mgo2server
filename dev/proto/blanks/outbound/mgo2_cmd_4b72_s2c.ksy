meta:
  id: mgo2_cmd_4b72_s2c
  title: "MGO2 0x4b72 — clan stat blocks, 580 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD58F3C**, which re-checks the id (`cmpwi r0,19314`) before reading anything.

  Closes pending-request slot **111**. Body present only when result == 0.

  Structure recovered from 0xD59068-0xD5988C: **two** iterations of a body containing exactly
  **72 u4 reads**, contiguous in the destination (verified by emulating the address arithmetic:
  session+0x10000+4404 .. +4688 in steps of 4). The loop counter starts at 2 and exits when the
  pre-increment value is 3 (0xD59834), so the count is a hard 2 — nothing on the wire selects it.
  Between iterations every destination pointer advances by **292** = 72*4 + 4, so each block has
  a 4-byte client-side field that is NOT on the wire.

  Wire size: 4 + 2 * 72 * 4 = **580 bytes**. Destination base is memset over 1168 bytes = 4 * 292
  (0xD58FF8), i.e. four block slots exist but only two are filled here — plausibly the same
  page-pairing as 0x4b71 (personal 0/1, clan 2/3), which is [INFERRED], not read.

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
    doc: "[ELF] 0 = success, blocks follow; non-zero = 4-byte reply. Published to request slot 111."
  - id: blocks
    type: block
    repeat: expr
    repeat-expr: 2
    doc: "[ELF] Exactly 2, from the unrolled loop bound at 0xD59834. No count on the wire."
types:
  block:
    doc: "[ELF] 72 u4 = 288 wire bytes; client stride 292 (one 4-byte non-wire field per block)."
    seq:
      - id: values
        type: u4
        repeat: expr
        repeat-expr: 72
        doc: "[UNKNOWN] All 72. The parser only stores them; nothing in it reveals meaning. 72 is not 18*4, so this is not a second copy of the 0x4b71 / 0x4105 grid."
