meta:
  id: mgo2_cmd_4510_c2s
  title: "MGO2 0x4510 — ADDLIST remove relationship (client -> server)"
  endian: be
doc: |
  Builder function `0xD46EB0` = `f(ctx, u8 state, u32 target_chara_id)` (`stb r4,1416(r1)` at
  `0xD46EE0`, `stw r5,1424(r1)` at `0xD46EDC`); `bl 0xD5CF40` at `0xD46F28`
  (`li r4,0x4510` at `0xD46F24`). Writes `0xD5C86C` (u8) at `0xD46F38` then `0xD5C9BC` (u32) at
  `0xD46F48`; seal `0xD5C828` at `0xD46F54`, flush `0xD34CC0` at `0xD46F64`. Not encrypted.
  **Total payload 5 bytes** — byte-identical in shape to `0x4500` (`0xD46FE0` is the next
  function along and is the same code with a different id), which is why the two live in the same
  request format even though their *replies* differ in field order.

  Confirms `PROTOCOL.md`'s `{u8 state, u32 target chara id}`.
doc-ref: dev/docs/PROTOCOL.md "0x4510 — remove relationship"
seq:
  - id: state
    type: u1
    doc: "[CONFIRMED] 0x00. The state being **removed** (0 friend, 1 blocked). A friend -> blocked change sends `0x4510 {0}` then `0x4500 {1}`; clearing to none sends `0x4510` alone. Every `0x4510` blocks on its reply."
  - id: target_chara_id
    type: u4
    doc: "[CONFIRMED] 0x01. The character whose relation is being cleared."
