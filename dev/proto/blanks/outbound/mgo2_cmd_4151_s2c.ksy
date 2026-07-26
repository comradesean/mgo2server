meta:
  id: mgo2_cmd_4151_s2c
  title: "MGO2 0x4151 — lobby-disconnect ack (server -> client)"
  endian: be
doc: |
  Parser 0xd3879c-fed arm at 0xd3943c (GAME dispatcher 0xd38804). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 116, state 2)` at 0xd32e08 followed by `notify(event 116, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  116. Anything after the first four bytes is ignored.

  Wait slot 116 (0x74). PROTOCOL.md mentions `0x4150` lobby disconnect as handled; this is its
  reply shape read out of the binary.
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED] Wire 0x00. The whole payload as far as the client is concerned. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
