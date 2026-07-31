meta:
  id: mgo2_cmd_4211_s2c
  title: "MGO2 0x4211 — list start for the 0x4210 triple (server -> client)"
  endian: be
doc: |
  Parser **0xd3b01c** (GAME dispatcher 0xd38804, trampoline 0xd39170), wait slot 32 (0x20).
  Start packet of the `0x4211` / `0x4212` / `0x4213` triple, which COMMANDS.md lists entirely
  under "parsed but never sent" — `0x4210` is a sendable-but-unanswered gap "reachable in ordinary
  flow" (the connect-family card).

  Reads exactly one u32 (0xd5cc64 at 0xd3b09c), then branches on it. Guard first:
  `lwz r0,0(r28); cmpwi r0,0; bne -> bail(-73)` where `r28 = *(ctx+0x10000+6404) + 13104` — the
  list marker must already be 0.

    * **value == 0** (0xd3b100): `notify(32, 0)`, then `marker = -1`, `count = 0`. This opens the
      list; `0x4213` refuses to run unless the marker is non-zero.
    * value != 0 (0xd3b0d8): `notify(32, state 2)` and `notify(32, value)` — the value goes to the
      UI as a result and the list is **not** opened.

  Same design as `0x2009` and unlike `0x2002`: this start packet does read its four bytes and the
  value must be zero. Closing the `0x4210` gap means sending `0x4211{u32 0}`, the `0x4212`
  records, then `0x4213`.
seq:
  - id: result
    type: u4
    doc: "[ELF] Wire 0x00. **Must be 0** to open the list (0xd3b0c4). Non-zero is forwarded to the UI as an error and no list is opened."
