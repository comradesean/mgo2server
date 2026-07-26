meta:
  id: mgo2_cmd_4344_c2s
  title: "MGO2 0x4344 — peer register (client -> server)"
  endian: be
doc: |
  Builder function `0xD42FA8`; `bl 0xD5CF40` at `0xD43058` (`li r4,0x4344` at `0xD43050`).
  Payload writes: `0xD5C9BC` (u32) at `0xD43068`, then `0xD5C8A0` (u8) at `0xD43078`. Seal
  `0xD5C828` at `0xD43084`, flush `0xD34CC0` at `0xD43094`. Not encrypted.
  **Total payload 5 bytes.**

  This is the only one of the four peer-register senders with a second argument:
  `f(ctx, u32 a, u8 b)`, staged at `r1+1432` (`stw r4` at `0xD42FDC`) and `r1+1440`
  (`stb r5` at `0xD42FD8`). Its three siblings (`0x4340`/`0x4342`/`0x4346`) are the same
  function shape minus the byte.

  `PROTOCOL.md`'s admin-action table records the `0x4440`/`0x4344` pair firing on a host
  Restart (Round)/Restart (Stage), which is the only live sighting; no payload was decoded
  there.
doc-ref: dev/docs/PROTOCOL.md "What the host admin menu actually sends"
seq:
  - id: chara_id
    type: u4
    doc: "[ELF] 0x00, position and width exact. **[UNKNOWN] meaning** — first argument, passed through unvalidated. See mgo2_cmd_4340.ksy for why the name is a guess."
  - id: unknown_04
    type: u1
    doc: "[UNKNOWN] 0x04. Second argument, written verbatim with no range check in `0xD42FA8`. Given the Restart pairing with `0x4440` (team/spectator), a team or slot index is the obvious candidate — untested."
