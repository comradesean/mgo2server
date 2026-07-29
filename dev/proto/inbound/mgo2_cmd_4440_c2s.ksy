meta:
  id: mgo2_cmd_4440_c2s
  title: "MGO2 0x4440 — team / spectator change (client -> server)"
  endian: be
doc: |
  Builder function `0xD52A44` = `f(ctx, u8 arg)` (`stb r4,1416(r1)` at `0xD52A70`);
  `bl 0xD5CF40` at `0xD52AB8` (`li r4,0x4440` at `0xD52AB4`). One `0xD5C86C` (u8) write at
  `0xD52AC8`, seal `0xD5C828` at `0xD52AD4`, flush `0xD34CC0` at `0xD52AE4`. Not encrypted.
  **Total payload 1 byte.** The argument is not validated or range-checked.

  This settles one open question in `PROTOCOL.md` "`0x4440` — unknown", which reports the two
  reference servers disagreeing: Nomad parses nothing, mgo2-server registers it twice, once as
  an unknown ack and once as a "GetPlayerOptions" reading a u8. **The ELF says the request is
  exactly one u8** — so the shape mgo2-server's second registration assumes is the right one,
  independently of its name or its 5-byte reply. The *meaning* of the byte is still unestablished.

  Live context from `PROTOCOL.md`'s admin-action table: `0x4440` exchanges accompany an accepted
  team change, and the `0x4440`/`0x4344` pair fires on host Restart — consistent with a team or
  spectator-slot selector, not asserted.
doc-ref: dev/docs/PROTOCOL.md "0x4440 — unknown"
seq:
  - id: unknown_00
    type: u1
    doc: "[ELF] 0x00 — the whole payload is this one byte, position and width exact from `0xD52AC8`. **[UNKNOWN] meaning**; team index / spectator flag are the candidates from the live pairing, neither tested."
