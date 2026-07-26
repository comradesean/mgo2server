meta:
  id: mgo2_cmd_4392_c2s
  title: "MGO2 0x4392 — set game / advance the rotation (client -> server)"
  endian: be
doc: |
  Builder function `0xD41188` = `f(ctx, u8 rotation_index)` (`stb r4,1416(r1)` at `0xD411B4`);
  `bl 0xD5CF40` at `0xD411FC` (`li r4,0x4392` at
  `0xD411F8`). One payload write — `0xD5C8A0` (u8) at `0xD4120C`, source `r1+1416` — then the
  seal `0xD5C828` at `0xD41218` and the flush `0xD34CC0` at `0xD41228`. Not encrypted.
  **Total payload 1 byte.** The ELF agrees exactly with the live capture recorded in
  `PROTOCOL.md` ("one byte, the rotation index").
doc-ref: dev/docs/PROTOCOL.md "0x4392 — set game (advance the rotation)"
seq:
  - id: rotation_index
    type: u1
    doc: |
      [CONFIRMED] 0x00. The index into the host's game rotation, sent by the host on
      "Restart (Next)" — capture-proven twice, 2026-07-22, with the browser following the
      applied change. The server resolves `current_game`/`rule`/`map`/`flags` from the stored
      host-settings blob at `0xA3 + 3*index`.
