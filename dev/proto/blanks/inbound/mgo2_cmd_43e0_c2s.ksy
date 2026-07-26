meta:
  id: mgo2_cmd_43e0_c2s
  title: "MGO2 0x43e0 — automatch status fetch (client -> server)"
  endian: be
doc: |
  Builder function `0xD5BCB4` = `f(ctx, u8 arg)` (`stb r4,1416(r1)` at `0xD5BCE0`);
  `bl 0xD5CF40` at `0xD5BD28` (`li r4,0x43E0` at `0xD5BD24`). One `0xD5C8A0` (u8) write at
  `0xD5BD38`, seal `0xD5C828` at `0xD5BD44`, flush `0xD34CC0` at `0xD5BD54`. Not encrypted.
  **Total payload 1 byte.** Agrees with `PROTOCOL.md` ("a single u8 argument (observed 11)").
doc-ref: dev/docs/PROTOCOL.md "0x43e0 — automatch status fetch"
seq:
  - id: request_kind
    type: u1
    doc: |
      [CONFIRMED] 0x00. Observed live as **11**. Not validated by the sender, so 11 is the
      caller's value rather than a protocol constant. Sent on entry to the automatching lobby;
      the reply `0x43E1` is a u32 result plus, only when that result is zero, two u8s.
