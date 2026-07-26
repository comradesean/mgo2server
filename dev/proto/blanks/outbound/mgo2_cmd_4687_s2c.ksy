meta:
  id: mgo2_cmd_4687_s2c
  title: "MGO2 0x4687 \u2014 match-detail list END (server -> client)"
  endian: be
doc: |
  End packet of the 0x4684 triple. Parser 0xD3AACC, dispatcher stub 0xD39160.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD3AB50) and stores it into the subsystem-0x1E result slot
  unconditionally, marking completion. Must be 0 on the success path.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code, stored unconditionally. MUST be 0 on the success path.
      [CONFIRMED by PROTOCOL.md]
