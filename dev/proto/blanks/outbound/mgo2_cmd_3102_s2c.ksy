meta:
  id: mgo2_cmd_3102_s2c
  title: "MGO2 0x3102 — create-character result (server -> client)"
  endian: be
doc: |
  Parser arm 0xd371cc (ACCOUNT dispatcher 0xd37074). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 15, state 2)` at 0xd32e08 followed by `notify(event 15, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  15. Anything after the first four bytes is ignored.

  **The new character id PROTOCOL.md documents at wire 0x04 is genuinely never read** — the arm
  stops after the first u32. Confirmed here from the parser, as PROTOCOL.md already states.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x3102"
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED] Wire 0x00. The whole payload as far as the client is concerned. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
