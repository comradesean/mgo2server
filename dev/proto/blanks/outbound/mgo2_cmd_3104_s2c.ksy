meta:
  id: mgo2_cmd_3104_s2c
  title: "MGO2 0x3104 — select-character result (server -> client)"
  endian: be
doc: |
  Parser arm 0xd37234 (ACCOUNT dispatcher 0xd37074). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 16, state 2)` at 0xd32e08 followed by `notify(event 16, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  16. Anything after the first four bytes is ignored.

doc-ref: dev/docs/PROTOCOL.md "0x3103 — select character"
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED] Wire 0x00. The whole payload as far as the client is concerned. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
