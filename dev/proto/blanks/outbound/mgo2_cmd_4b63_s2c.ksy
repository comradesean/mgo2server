meta:
  id: mgo2_cmd_4b63_s2c
  title: "MGO2 0x4b63 — clan/GHQ reply, single result code (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven:
  everything here is read out of the client parser.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser **0xD55220**,
  which re-checks the id (`cmpwi r0,19299` = 0x4b63) before reading anything.

  Whole payload is ONE s4. The parser reads it, closes pending-request slot 107
  (0xD32E08 state=2) and publishes the value as that request's result (0xD32E70).
  Nothing else is read; a longer payload would simply be ignored, a shorter one would read
  stale receive-buffer bytes (the readers bound-check the 1023-byte buffer, not the payload
  length — see PROTOCOL.md).

  Read primitives (all confirmed by disassembling the primitive table at 0xD5C844+):
  0xD5CB8C / 0xD5CB54 u1, 0xD5CC14 / 0xD5CBC4 u2, 0xD5CC64 / 0xD5CCD8 u4 (each pair identical
  twins — see the CORRECTION below), 0xD5D018 fixed-size
  byte block of `len` bytes (memcpy + a client-side NUL written at dest[len], so the wire
  consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (returns -1 at end — this is
  what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. An earlier revision added:
  "In each signed/unsigned pair the LOWER address is the signed accessor (proved on the write
  side, where 0xD5C95C uses `sraw` and 0xD5C9BC uses `srw`; and here 0xD5CC64's value is
  reloaded with `lwa`)." **That claim is SUPERSEDED — see the CORRECTION below.** Only the
  `lwa` half of it survives, and it is a fact about the caller, not the primitive.

  CORRECTION (verified 2026-07-26, whole-function compare at every width): that rule is wrong,
  and it is wrong on the READ side at ALL widths, not just at u32. Each "signed/unsigned pair"
  is instruction-for-instruction identical — same bound check, same byte-assembly loop, same
  `extsb` on each byte, same store width:
    * u8:  0xD5CB54 == 0xD5CB8C  (bound `cmpwi 1023`, `lbzx`/`stb`, cursor += 1)
    * u16: 0xD5CBC4 == 0xD5CC14  (bound `cmpwi 1022`, two `lbzx`, `sth`,  cursor += 2)
    * u32: 0xD5CC64 == 0xD5CCD8  (bound `cmpwi 1020`, 4-iteration loop, `stw`, cursor += 4)
    * u64: 0xD5CD4C == 0xD5CDC0  (bound `cmpwi 1016`, 8-iteration loop, `std`, cursor += 8)
  So **no read primitive is a signed accessor at any width**, and "0xD5CBC4 s2" / "0xD5CC64 s4"
  are as unfounded as the u32 claim. Signedness comes from the CALLER — the value being
  reloaded with `lwa`, or being compared against known-negative error constants — never from
  the primitive's address.

  The write side does not rescue the rule either. There are **three** u32 write primitives, not
  a signed/unsigned pair: 0xD5C95C (`sraw`), 0xD5C9BC (`srw`) and 0xD5CA1C (`sraw`). The
  sraw/srw difference is inert because each iteration masks with `and r0,r4,r0` where r0 =
  `slw r7,r10` of 255, and then stores only the low byte with `stbx`: for shifts 16/8/0 the
  masked operand is non-negative in 32 bits so the two shifts agree outright, and for shift 24
  they differ only in bits above bit 7, which `stbx` discards. Identical bytes on the wire.

  Request-slot machinery: 0xD32E08(session, slot, state) writes session+0x160+slot*4+8 and
  0xD32E70(session, slot, value) writes session+0x330+slot*4+12 — the client's pending-request
  table (117 slots). A reply that calls these is the terminator of a request; `value` is the
  s4 the packet carried. 0xD33CD8(session, event, arg) is the UI event dispatch instead.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

seq:
  - id: result
    type: s4
    doc: |
      [ELF] Signed 32-bit result/error code. It is typed s4 because the CALLER reloads it with
      `lwa`, not because of the primitive: 0xD5CC64 is byte-identical to 0xD5CCD8 and is not a
      signed accessor (see the CORRECTION in the top-level doc). Negative values are meaningful (this family's errors are in the
      -0x4xx..-0x5xx range elsewhere in the binary). 0 = success by the convention every other
      traced reply follows. Meaning of non-zero values here: [UNKNOWN].
