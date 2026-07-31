meta:
  id: mgo2_cmd_4500_c2s
  title: "MGO2 0x4500 — ADDLIST add / change relationship (client -> server)"
  endian: be
doc: |
  Builder function `0xD46FE0` = `f(ctx, u8 state, u32 target_chara_id)` (`stb r4,1416(r1)` at
  `0xD47010`, `stw r5,1424(r1)` at `0xD4700C`); `bl 0xD5CF40` at `0xD47058`
  (`li r4,0x4500` at `0xD47054`). Writes `0xD5C86C` (u8) at `0xD47068` then `0xD5C9BC` (u32) at
  `0xD47078`; seal `0xD5C828` at `0xD47084`, flush `0xD34CC0` at `0xD47094`. Not encrypted.
  **Total payload 5 bytes.**

  The ELF confirms `PROTOCOL.md`'s `{u8 state, u32 target chara id}` exactly, including the field
  order — which matters because the `0x4502` reply reverses it relative to `0x4512`. Neither
  field is validated by the sender (unlike `0x4580`, which caps its state at 1 — see
  mgo2_cmd_4580.ksy).
doc-ref: dev/docs/PROTOCOL.md "0x4500 — add / change relationship"
seq:
  - id: state
    type: u1
    doc: "[CONFIRMED] 0x00. **0 = friend, 1 = blocked** — both confirmed live 2026-07-22 across a full none -> friend -> blocked -> none cycle. Note the sender does not clamp this, unlike `0x4580`."
  - id: target_chara_id
    type: u4
    doc: "[CONFIRMED] 0x01. The character being added/blocked. Note the field is unaligned on the wire — the u8 comes first."
