meta:
  id: mgo2_cmd_4102_c2s
  title: "MGO2 0x4102 — get personal stats (client -> server)"
  endian: be
doc: |
  **Four bytes.** Evidence: builder call site `bl 0xd5cf40` at `0xd3bab0` (sender `0xD3BA3C`).
  One write primitive: `bl 0xd5c9bc` (write-u32, big-endian, four `stbx` of one word) at
  `0xd3bac0`, from stack `1416(r1)`. Seal immediately after; wait slot `0x16`. [ELF]

  Confirms PROTOCOL.md: "Payload: one u32 character id ... Sender `0xD3BA3C` (single build
  site `0xd3bab0`), wait slot `0x16`". [CONFIRMED live 2026-07-23]

  The three-packet reply burst (`0x4103`/`0x4105`/`0x4107`) is already specced in
  `dev/proto/` — see `mgo2_cmd_4103.ksy`, `mgo2_cmd_4105.ksy`, `mgo2_cmd_4107.ksy`.
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats"
seq:
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED] Character id whose stats are wanted — normally the viewer's own, pulled from
      the connect-burst record, but the card's "more details" button sends another player's id
      here (see `0x4220`).
