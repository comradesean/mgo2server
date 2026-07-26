meta:
  id: mgo2_cmd_4220_c2s
  title: "MGO2 0x4220 — player details request (client -> server)"
  endian: be
doc: |
  **Four bytes.** Evidence: builder call site `bl 0xd5cf40` at `0xd3b9c4` (sender `0xD3B950`).
  One write primitive: `bl 0xd5c9bc` (write-u32) at `0xd3b9d4` from stack `1416(r1)`. Seal
  immediately after; wait slot `0x1c` (`li r4,28`), matching PROTOCOL.md's "Subsystem index
  `0x1C`". [ELF]

  Confirms PROTOCOL.md "Request: one u32, the selected player's id". [CONFIRMED live
  2026-07-23]. The single 201-byte reply `0x4221` is already specced in
  `dev/proto/mgo2_cmd_4221.ksy`.
doc-ref: dev/docs/PROTOCOL.md "0x4220 — player details"
seq:
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED] The selected player's character id, taken from the stored per-row id of the
      met-players history list (`0x4682`). Which history-record field that is was to be
      settled by the request log.
