meta:
  id: mgo2_cmd_4442_s2c
  title: "MGO2 0x4442 \u2014 0x4440-family push notification (server -> client)"
  endian: be
doc: |
  Parser 0xD52878, dispatcher stub 0xD394B4. Reads EXACTLY ONE u32 (0xD5CC64 at 0xD528D4) and
  then calls 0xD33CD8 with event id 0x31 (49) and the u32 as its value -- the same "fire a UI
  event" helper 0x43F2..0x43F5 and 0x4802 use. It does NOT touch the status/result setters
  (0xD32E08 / 0xD32E70) for subsystem 0x54, which is what 0x4441 does.

  So this id is not the tail of the 0x4440 reply; it is an unsolicited notification the server may
  push. Nothing in the ELF says what event 0x31 renders -- [UNKNOWN].

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Payload of UI event 0x31. Meaning [UNKNOWN]: the parser only forwards it.
      [ELF 0xD528D4]
