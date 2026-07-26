meta:
  id: mgo2_cmd_4821_s2c
  title: "MGO2 0x4821 \u2014 mailbox list START (server -> client)"
  endian: be
doc: |
  Start packet of the 0x4820 mailbox triple (0x4821 start / 0x4822 entries / 0x4823 end).
  Parser 0xD53854, dispatcher stub 0xD394F4.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD538F4), then the subsystem-0x55 status/result setters
  (0xD32E08 at 0xD53930, 0xD32E70 at 0xD53944), and on the zero branch also 0xD32E70 with 0 and
  0xD34038 -- the mailbox-array reset. PROTOCOL.md records this as "4 bytes result"; the ELF
  agrees, and start-then-end with nothing between is a real (empty mailbox) answer.

  Subsystem 0x55 is shared by the whole mail family: 0x4801, 0x4821, 0x4823, 0x4841, 0x4861,
  0x4881 all drive the same slot.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success. [CONFIRMED by PROTOCOL.md; ELF 0xD538F4]
