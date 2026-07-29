meta:
  id: mgo2_cmd_4113_s2c
  title: "MGO2 0x4113 — reply to 0x4112 (server -> client)"
  endian: be
doc: |
  Parser 0xd3b148 (GAME dispatcher 0xd38804, trampoline 0xd390d0). Reads **exactly one u32** (primitive 0xd5cc64) and nothing else, then
  `notify(event 24, state 2)` at 0xd32e08 followed by `notify(event 24, value)` at 0xd32e70 —
  i.e. the value is handed straight to the request-status machine as the result of wait slot
  24. Anything after the first four bytes is ignored.

  COMMANDS.md listed `0x4113` under "result singles" that the client parses but we never send,
  and `0x4112` under "reachable in ordinary flow" sendable-but-unanswered gaps. This parser trace
  settled the reply shape: a bare u32 result on wait slot 24 is sufficient, so the `0x4112` gap
  can be closed with a four-byte ack — unlike `0x4133`, which looked like a result single and was
  not.

  **We now send it.** Live 2026-07-27: `0x4112` fires right after a player search and the client
  blocks on wait slot 0x18 (`li r4,24` at `0xD3BEDC`); a four-byte zero result released the
  screen, which is what the parser trace predicted. See `../inbound/mgo2_cmd_4112_c2s.ksy`.
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0x00. The whole payload as far as the client is concerned.
      **Tag history:** downgraded 2026-07-26 from [CONFIRMED] to [ELF], because 0x4113 appeared
      nowhere in OBSERVED.md or PROTOCOL.md's capture record — we had never sent it and never
      seen it, and the layout was read out of the parser alone. Re-confirmed 2026-07-27 by
      sending it: a four-byte zero result released the wait slot the client had armed on
      `0x4112`, so the shape is now capture-proven end to end. 0 on success;
      our error codes are masked `C0FFEE**` values. See PROTOCOL.md for the per-command code
      lists. Signedness is **not** recoverable from the read primitive (it assembles four bytes
      with no sign handling); PROTOCOL.md calls it s32 because the client compares it against
      negative constants downstream.
