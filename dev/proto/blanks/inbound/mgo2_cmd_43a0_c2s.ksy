meta:
  id: mgo2_cmd_43a0_c2s
  title: "MGO2 0x43a0 — pass host (client -> server)"
  endian: be
doc: |
  Builder function `0xD40F28` = `f(ctx, u32 a, u32 b)` (`stw r4,1416(r1)` at `0xD40F58`,
  `stw r5,1424(r1)` at `0xD40F54`); `bl 0xD5CF40` at `0xD40FA0` (`li r4,0x43A0` at `0xD40F9C`).
  Two `0xD5C9BC` (u32) writes at `0xD40FB0` and `0xD40FC0`, seal `0xD5C828` at `0xD40FCC`,
  flush `0xD34CC0` at `0xD40FDC`. Not encrypted. **Total payload 8 bytes.**

  The ELF confirms the live capture in `PROTOCOL.md` exactly: two u32s, arrived as
  `00000001 00000002` on a real host change, and neither is validated or transformed on the
  way out.
doc-ref: dev/docs/PROTOCOL.md "0x43a0 — pass host"
seq:
  - id: sender_chara_id
    type: u4
    doc: "[CONFIRMED] 0x00. The sending host's own character id. Unused by the server — attribution is connection-implicit."
  - id: new_host_chara_id
    type: u4
    doc: "[CONFIRMED] 0x04. The target. Must be another player in the game or the request is logged and dropped."
