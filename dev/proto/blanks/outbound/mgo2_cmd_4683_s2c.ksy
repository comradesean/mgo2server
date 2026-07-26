meta:
  id: mgo2_cmd_4683_s2c
  title: "MGO2 0x4683 \u2014 match-history list END (server -> client)"
  endian: be
doc: |
  End packet of the 0x4680 triple. Parser 0xD3ACF8, dispatcher stub 0xD39130.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD3AD7C) and stores it into the same subsystem-0x1D result
  slot UNCONDITIONALLY, marking completion. So the end value is the operative result and must be
  0 on the success path.

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
      [CONFIRMED live, OBSERVED.md]
