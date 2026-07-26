meta:
  id: mgo2_cmd_4b81_s2c
  title: "MGO2 0x4b81 — clan/GHQ profile partial update, 217 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD58C74**, which re-checks the id (`cmpwi r0,19329`) before reading anything.

  Closes pending-request slot **113**. Writes into the SAME struct as 0x4b21
  (T = session + 0x10000 - 1968) but does NOT memset it first and touches only a subset of the
  fields — so this is an update, and any field 0x4b21 set that this packet omits keeps its old
  value. Overlapping destinations with mgo2_cmd_4b21.ksy: T+0x00, +0x04, +0x18, +0x1c, +0x378,
  +0x67A, +0x58, +0x1B34.

  Wire size on success: **217 bytes**; on error (result != 0) 4.

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
    doc: "[ELF] 0 = success, body follows. Published to request slot 113."
  - id: subject_id
    type: u4
    doc: "[ELF] T+0x00 — same slot as 0x4b21's subject_id, but NOT cross-checked here. [UNKNOWN]"
  - id: name_a
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x04, 16 bytes. Same slot as 0x4b21 name_a. [UNKNOWN]"
  - id: unknown_18
    type: u4
    doc: "[ELF] T+0x18. [UNKNOWN]"
  - id: name_b
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x1c, 16 bytes. Same slot as 0x4b21 name_b. [UNKNOWN]"
  - id: unknown_378
    type: u1
    doc: "[ELF] T+0x378. [UNKNOWN]"
  - id: text_67a
    size: 128
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x67A, 128 bytes. Same slot as 0x4b21 text_67a. [UNKNOWN]"
  - id: unknown_1b34
    type: u4
    doc: "[ELF] T+0x1B34. [UNKNOWN]"
  - id: unknown_58
    type: u4
    doc: "[ELF] T+0x58. [UNKNOWN]"
  - id: unknown_1328
    type: u4
    doc: "[ELF] T+0x1328 — outside anything 0x4b21 writes. [UNKNOWN]"
  - id: unknown_1978
    type: u4
    doc: "[ELF] T+0x1978. [UNKNOWN]"
  - id: unknown_197c
    type: u4
    doc: "[ELF] T+0x197C. [UNKNOWN]"
  - id: unknown_1980
    type: u4
    doc: "[ELF] T+0x1980. [UNKNOWN]"
  - id: unknown_1984
    type: u4
    doc: "[ELF] T+0x1984. [UNKNOWN]"
  - id: unknown_1988
    type: u4
    doc: "[ELF] T+0x1988. [UNKNOWN]"
  - id: unknown_198c
    type: u4
    doc: "[ELF] T+0x198C. [UNKNOWN]"
  - id: unknown_1990
    type: u4
    doc: "[ELF] T+0x1990. [UNKNOWN]"
  - id: unknown_1994
    type: u4
    doc: "[ELF] T+0x1994, last 4 bytes of the payload. The eight u4 at T+0x1978..0x1994 are consecutive and read in order — a small counter/stat array. [UNKNOWN]"
