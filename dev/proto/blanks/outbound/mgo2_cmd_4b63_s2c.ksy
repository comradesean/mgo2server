meta:
  id: mgo2_cmd_4b63_s2c
  title: "MGO2 0x4b63 — clan/GHQ reply, single result code (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven:
  everything here is read out of the client parser.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx compare chain) -> thunk -> parser **0xD55220**,
  which re-checks the id (`cmpwi r0,19299` = 0x4b63) before reading anything.

  Whole payload is ONE s4. The parser reads it, closes pending-request slot 107
  (0xD32E08 state=2) and publishes the value as that request's result (0xD32E70).
  Nothing else is read; a longer payload would simply be ignored, a shorter one would read
  stale receive-buffer bytes (the readers bound-check the 1023-byte buffer, not the payload
  length — see PROTOCOL.md).

  Read primitives (all confirmed by disassembling the primitive table at 0xD5C844+):
  0xD5CB8C u1, 0xD5CBC4 s2, 0xD5CC14 u2, 0xD5CC64 s4, 0xD5CCD8 u4, 0xD5D018 fixed-size
  byte block of `len` bytes (memcpy + a client-side NUL written at dest[len], so the wire
  consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (returns -1 at end — this is
  what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. In each signed/unsigned
  pair the LOWER address is the signed accessor (proved on the write side, where 0xD5C95C uses
  `sraw` and 0xD5C9BC uses `srw`; and here 0xD5CC64's value is reloaded with `lwa`).

  CORRECTION (verified 2026-07-26, whole-function compare): that rule holds on the WRITE side
  only. The READ pair 0xD5CC64 / 0xD5CCD8 is instruction-for-instruction identical — same
  `cmpwi 1020` bound check, same byte-assembly loop — so neither is a signed accessor. Where a
  field below is typed s4, the evidence is the CALLER reloading the value with `lwa` (or the
  field being a known-negative error code), never the primitive's address.

  Request-slot machinery: 0xD32E08(session, slot, state) writes session+0x160+slot*4+8 and
  0xD32E70(session, slot, value) writes session+0x330+slot*4+12 — the client's pending-request
  table (117 slots). A reply that calls these is the terminator of a request; `value` is the
  s4 the packet carried. 0xD33CD8(session, event, arg) is the UI event dispatch instead.

seq:
  - id: result
    type: s4
    doc: |
      [ELF] Signed 32-bit result/error code, read with the signed u32 accessor 0xD5CC64 and
      reloaded with `lwa`, so negative values are meaningful (this family's errors are in the
      -0x4xx..-0x5xx range elsewhere in the binary). 0 = success by the convention every other
      traced reply follows. Meaning of non-zero values here: [UNKNOWN].
