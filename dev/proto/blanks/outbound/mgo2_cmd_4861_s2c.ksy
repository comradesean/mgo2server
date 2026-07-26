meta:
  id: mgo2_cmd_4861_s2c
  title: "MGO2 0x4861 \u2014 0x4860 mail-manage ack (server -> client)"
  endian: be
doc: |
  Reply to the unimplemented 0x4860 mail-management request. Parser 0xD53064, dispatcher stub
  0xD394E4.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD530D0) and drives the subsystem-0x55 status/result
  setters. Nothing else is read, so a bare 4-byte result is a complete reply -- which is what
  PROTOCOL.md already notes ("0x4860 is a no-op 0x4861 {0}"), here confirmed from the binary
  rather than from a reference server.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success. [ELF 0xD530D0]
