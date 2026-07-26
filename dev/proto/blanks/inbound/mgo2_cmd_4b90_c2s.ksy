meta:
  id: mgo2_cmd_4b90_c2s
  title: "MGO2 0x4b90 — clan/GHQ request naming a player (client -> server)"
  endian: be
doc: |
  18-byte payload: u8, u8, then a fixed 16-byte name field.

  Evidence (ELF, retail BLUS30109): sender 0xD55CDC, signature (session, u8 a, u8 b,
  char* name). Prologue spills `stb r4,1432(r1)` and `stb r5,1440(r1)`. Builder
  `bl 0xD5CF40` at 0xD55D98 (`li r4,0x4b90` at 0xD55D94), then
  `bl 0xD5C86C` at 0xD55DA8 (u8 from 1432 = the r4 parameter),
  `bl 0xD5C86C` at 0xD55DB8 (u8 from 1440 = the r5 parameter),
  `0xD5D0AC(pkt, name, 0x10)` at 0xD55DCC (fixed 16-byte `memcpy`),
  seal `bl 0xD5C828` at 0xD55DD8, flush `bl 0xD34CC0` at 0xD55DE8.

  Validation, all returning -24 without sending: session != NULL; **r4 <= 1** (`clrlwi` to a
  byte then `cmplwi 1` / `bgt` at 0xD55CF4/0xD55D20 — so the first field is a two-valued
  flag, 0 or 1); name != NULL; `strlen(name) <= 16` (0xDCC7F8 at 0xD55D30); and the name
  passes the character-class validator 0xD32DD0 — the same one 0x4B00 and 0x4B42 apply to
  their name fields. Note r5 is NOT range-checked.

  On a successful flush the flow state advances via `0xD32E08(session, 114, 1)`. This sender
  has no clan-record precondition (no 0xD57750 / 0xD5709C call), which sets it apart from the
  rest of the family.

  Reading [INFERRED]: a request that identifies a *player by name* (16 bytes is the protocol
  name width) with a two-valued mode flag — invite/kick, accept/reject and add/remove all
  fit and none is distinguished by the ELF. The 0/1 flag is hard evidence; the meaning is not.
  Never observed live; not answered by this server.
seq:
  - id: flag_0000
    type: u1
    doc: |
      [ELF] Position and width exact (0xD5C86C). **Range-checked to 0 or 1** at 0xD55D20 —
      the client will not send any other value. A binary mode/direction selector; which
      polarity means what is [UNKNOWN].
  - id: unknown_0001
    type: u1
    doc: |
      [ELF] Position and width exact (0xD5C86C). The r5 parameter, passed through with no
      validation at all. Meaning [UNKNOWN].
  - id: name
    type: str
    size: 16
    encoding: UTF-8
    doc: |
      [ELF] Exactly 16 bytes, `memcpy`'d from the caller's string; `strlen <= 16` and the
      0xD32DD0 character-class check are enforced first. 16 is the protocol name width
      (CLAUDE.md), so [INFERRED] this is a player or clan name typed by the user. Whether
      the tail is zero-filled depends on the caller's buffer and is [UNKNOWN] — unlike
      0x4B64/0x4B66 there is no `memset` of a staging buffer here, so `pad-right` is
      deliberately not asserted. Encoding is a guess.
