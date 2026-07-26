meta:
  id: mgo2_cmd_4d00_s2c
  title: "MGO2 0x4d00 — 6-byte notification (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD4EC54**, which re-checks the id (`cmpwi r0,19712`) before reading anything.

  The whole payload is read by the SHARED header validator **0xD49230** (39 call sites across the
  lobby parsers), not by inline reads: it reads one u4 and one u2 and validates both against the
  session's current context object, returning -1018 on mismatch. So 0x4d00 carries nothing else —
  it is a pure "this context changed" ping.

  Validation detail (0xD49230): the u4 must equal ctx[+0x00] and the u2 must equal ctx[+0x29C],
  UNLESS the caller's context id is 0x4960, in which case both checks are skipped. A mismatch is
  -1018 and the packet is dropped.

  No request slot. On success it fires **UI event 33** (0xD33CD8) with the context's first word as
  the argument. Wire size: **6 bytes**.

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
    doc: "[ELF] Must equal the client's current context id (ctx+0x00) or the packet is dropped with -1018. [UNKNOWN] which id space — read from the same field the game-lobby/room objects use."
  - id: context_seq
    type: u2
    doc: "[ELF] Must equal ctx+0x29C. [UNKNOWN] — a sub-id or generation counter; the parser only compares it."
