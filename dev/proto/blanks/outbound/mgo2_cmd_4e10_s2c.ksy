meta:
  id: mgo2_cmd_4e10_s2c
  title: "MGO2 0x4e10 — session/room state push, 236 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD5AD5C**, which re-checks the id (`cmpwi r0,19984`) before reading anything.

  Sets pending-request slot **90** to state **1** (not 2) — i.e. this packet OPENS a request
  rather than closing one — and then immediately builds and sends **0x4E00** back to the server
  (`li r4,19968` into builder 0xD5CF40 at 0xD5B0CC). So a server that sends 0x4e10 must be ready
  to answer 0x4e00; the pair 0x4e11 (items) / 0x4e12 (end, same slot 90) completes the exchange.

  Bulk of the payload is a **204-byte settings block** read by the shared sub-parser
  **0xD4364C**, whose own read sequence was disassembled: a 16-iteration loop of three u1 reads
  (48 bytes, three parallel 16-byte arrays at dest+0/+16/+32), then u1,u1,bytes[16],u1,u1, three
  u4, two u2, two u4, u2, u1,u1, then 18 u4, bytes[2], u2, u4, u1, bytes[2], u1, u2, u2, u4, u1,
  u1, bytes[14] — 204 bytes total, ending at dest+204. That block is NOT expanded here: it is
  shared with other commands and belongs in its own spec once one of them is captured.

  Wire size: 4 + 2 + 1 + 1 + 204 + 4 + 5*4 = **236 bytes**.

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
  - id: unknown_00
    type: u4
    doc: "[ELF] Read to a stack slot; not obviously validated. [UNKNOWN]"
  - id: unknown_04
    type: u2
    doc: "[ELF] [UNKNOWN]"
  - id: flags_byte
    size: 1
    doc: |
      [ELF] Read as a 1-byte block, then all 8 bits are expanded into a 64-bit flag word at
      ctx+0x00 (0xD5AE4C-0xD5AF0C): bit0 -> 0x80000000, bit1 -> 0x40000000, bit2 -> 0x20000000,
      bit3 -> 0x10000000, bit4 -> 0x08000000, bit5 -> 0x04000000, bit6 -> 0x02000000,
      bit7 (sign) -> 0x01000000. All eight bits are used — unlike 0x4b21's flags byte, which uses
      three. [UNKNOWN] meanings.
  - id: unknown_07
    type: u1
    doc: "[ELF] -> ctx+0x05. [UNKNOWN]"
  - id: settings_block
    size: 204
    doc: |
      [ELF] 204 bytes consumed by the shared reader 0xD4364C into ctx+0x08. See the top-level doc
      for its internal read sequence. Deliberately left opaque: the sub-fields are readable from
      the ELF but naming them without a capture would be guessing at semantics, and this block is
      shared with other commands so it wants its own spec. [UNKNOWN]
  - id: unknown_d4
    type: u4
    doc: "[ELF] -> ctx+7268. [UNKNOWN]"
  - id: unknown_d8
    type: s4
    doc: "[ELF] -> ctx+7272. SIGNED accessor. [UNKNOWN]"
  - id: unknown_dc
    type: s4
    doc: "[ELF] -> ctx+7276. SIGNED. [UNKNOWN]"
  - id: unknown_e0
    type: s4
    doc: "[ELF] -> ctx+7280. SIGNED. [UNKNOWN]"
  - id: unknown_e4
    type: s4
    doc: "[ELF] -> ctx+7284. SIGNED. [UNKNOWN]"
  - id: unknown_e8
    type: s4
    doc: "[ELF] -> ctx+7288, last 4 bytes. SIGNED. The five consecutive signed words look like a score/counter row. [UNKNOWN]"
