meta:
  id: mgo2_cmd_0004_s2c
  title: "MGO2 0x0004 — disconnect acknowledgement (server -> client)"
  endian: be
doc: |
  Reply to the client's `0x0003` disconnect. Registered in **all three** lobby dispatchers, each of
  which is a two-instruction trampoline into the same shared handler **0xd35b68**:

    * GATE    dispatcher 0xd361a4 (compare tree 0xd361e8), arm 0xd3624c -> `bl 0xd35b68` with `r4 = 0`
    * ACCOUNT dispatcher 0xd37024 (compare tree at 0xd37074), arm 0xd370d8 -> `bl 0xd35b68` with `r4 = 1`
    * GAME    dispatcher 0xd387c8 (compare tree 0xd38804), arm 0xd38ffc -> `bl 0xd35b68` with `r4 = 2`

  `r4` is a **lobby-kind selector**, not a wire field: 0xd35b68 range-checks it (`cmplwi r4,2;
  bgt -> bail(-24)`) and passes it to the per-lobby packet fetch at 0xd3589c, which is where the
  id is re-verified (`cmpwi r0,4`).

  The handler reads exactly one u32 (0xd5cc64 at 0xd35bcc), then `notify(event 0, state 2)` at
  0xd32e08 and `notify(event 0, value)` at 0xd32e70. **Wait slot 0** — a literal, not derived from
  the lobby kind, unlike `0x0005` which uses `r4 + 7`.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: result
    type: u4
    doc: |
      [ELF] Wire 0x00. The whole payload; anything after it is ignored. Handed to the
      request-status machine as the result of wait slot 0. The parser makes no comparison against
      any constant, so any value completes the wait.
