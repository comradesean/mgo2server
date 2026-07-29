meta:
  id: mgo2_cmd_4151_s2c
  title: "MGO2 0x4151 — lobby-disconnect ack (server -> client)"
  endian: be
doc: |
  Parser 0xd3879c-fed arm at 0xd3943c (GAME dispatcher 0xd387c8, compare tree at 0xd38804). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 116, state 2)` at 0xd32e08 followed by `notify(event 116, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  116. Anything after the first four bytes is ignored.

  Wait slot 116 (0x74). PROTOCOL.md mentions `0x4150` lobby disconnect as handled; this is its
  reply shape read out of the binary.

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
      [CONFIRMED] Wire 0x00. The whole payload as far as the client is concerned. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
