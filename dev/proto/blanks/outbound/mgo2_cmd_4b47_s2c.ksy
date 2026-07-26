meta:
  id: mgo2_cmd_4b47_s2c
  title: "MGO2 0x4b47 — clan/GHQ reply, 28-byte record (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD5835C**, which re-checks the id (`cmpwi r0,19271`) before reading anything.

  Closes pending-request slot **98**. When result == 0 the fields are copied into the object
  returned by 0xD3A094 at +6816 (u4), +6837 (u1), +6838 (u2), +6872 (u1) and +6820 (the 17-byte
  NUL-terminated name), via `lswi/stswi` at 0xD584B4. When result != 0 only the 4-byte result is
  read. Wire size on success: **28 bytes**.

  NOTE the wire order is NOT the struct order — the u2 is read before the second u1 even though
  it lands at a higher offset. Order below is the read order, which is what matters on the wire.

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
    doc: "[ELF] 0 = success, body follows. Published to request slot 98."
  - id: unknown_04
    type: u4
    doc: "[ELF] -> object+6816. [UNKNOWN]"
  - id: unknown_08
    type: u1
    doc: "[ELF] -> object+6837. [UNKNOWN]"
  - id: unknown_09
    type: u2
    doc: "[ELF] -> object+6838. [UNKNOWN]"
  - id: unknown_0b
    type: u1
    doc: "[ELF] -> object+6872. [UNKNOWN]"
  - id: name
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] 16 bytes fixed -> object+6820 (copied as 17 bytes including the NUL). [UNKNOWN] whose name."
