meta:
  id: mgo2_cmd_4903_s2c
  title: "MGO2 0x4903 — game-lobby list END (server -> client)"
  endian: be
doc: |
  End packet of the 0x4900 hub triple. Parser 0xD47714, dispatcher stub 0xD395B8.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD47794) and drives the subsystem-0x38 status/result
  setters, marking completion. PROTOCOL.md: "4 bytes result"; LOBBIES.md: "0x4903: result;
  marker 0".

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success. [CONFIRMED by PROTOCOL.md / LOBBIES.md]
