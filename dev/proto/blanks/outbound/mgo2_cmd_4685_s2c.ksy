meta:
  id: mgo2_cmd_4685_s2c
  title: "MGO2 0x4685 \u2014 match-detail list START (server -> client)"
  endian: be
doc: |
  Start packet of the 0x4684 match-detail triple. Parser 0xD3ABC8, dispatcher stub 0xD39140.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD3AC4C), then the subsystem-0x1E status/result setters
  (0xD32E08 / 0xD32E70). Same mechanics as 0x4681: nonzero fails the transaction with the value
  rendered in the error dialog (screen 0x1034), zero resets the entry count. Records are the
  93-byte 0x4686 (already specced in dev/proto), client table caps at 32.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success, never a count. [CONFIRMED by PROTOCOL.md]
