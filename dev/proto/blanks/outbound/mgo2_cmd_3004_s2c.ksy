meta:
  id: mgo2_cmd_3004_s2c
  title: "MGO2 0x3004 — check-session result (server -> client)"
  endian: be
doc: |
  Parser arm 0xd370ec (ACCOUNT dispatcher 0xd37074). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 5, state 2)` at 0xd32e08 followed by `notify(event 5, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  5. Anything after the first four bytes is ignored.

  The client maps this straight onto an error screen; from the binary: 0 advances, -0xF0 -> 0x924,
  -0x192 -> 0xA50, -0x193/-0x194 -> 0x933, everything else -> 0x925. Our masked `C0FFEE02` falls
  in "everything else", so a rejected session shows as 0x925.

  Note `0x3004` is **also** registered in the GAME dispatcher (0xd38804, arm 0xd39010 ->
  0xd39e54); that arm is the GAME-lobby check-session and is the one collision between the
  Channel A and Channel B id spaces (COMMANDS.md). This spec describes the ACCOUNT arm; both
  read a single u32.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x3004 — 4 bytes"
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED] Wire 0x00. The whole payload as far as the client is concerned. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
