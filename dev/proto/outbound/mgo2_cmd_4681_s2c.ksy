meta:
  id: mgo2_cmd_4681_s2c
  title: "MGO2 0x4681 — match-history list START (server -> client)"
  endian: be
doc: |
  Start packet of the 0x4680 met-players-history triple. Parser 0xD3ADF4, dispatcher stub
  0xD39110.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD3AE78), then the subsystem-0x1D status/result setters
  (0xD32E08 / 0xD32E70). This is the handler OBSERVED.md traced on 2026-07-23: nonzero marks the
  transaction complete-with-error and stores the value verbatim at ctx+0x33C+idx*4, which the
  history UI polls and renders as the error dialog -- our count of 5 came back as
  "1032:00000005". Zero initialises the entry count to 0 and proceeds.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success. NOT a record count -- the client counts the 25-byte
      0x4682 records itself, capped at 64. [CONFIRMED live, OBSERVED.md]
