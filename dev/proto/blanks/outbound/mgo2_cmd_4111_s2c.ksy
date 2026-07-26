meta:
  id: mgo2_cmd_4111_s2c
  title: "MGO2 0x4111 — options write-back ack (server -> client)"
  endian: be
doc: |
  Parser 0xd3b20c (GAME dispatcher 0xd38804, trampoline 0xd390c0). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 23, state 2)` at 0xd32e08 followed by `notify(event 23, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  23. Anything after the first four bytes is ignored.

  The ack for `0x4110`. PROTOCOL.md records that the `0x4110` body is acknowledged with
  `0x4111 {u32 0}` and that the ack is required; this is the parser confirming the shape.
doc-ref: dev/docs/PROTOCOL.md "0x4110 — update gameplay options"
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED] Wire 0x00. The whole payload as far as the client is concerned. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
