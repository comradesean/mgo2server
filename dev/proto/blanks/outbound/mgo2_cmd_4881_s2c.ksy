meta:
  id: mgo2_cmd_4881_s2c
  title: "MGO2 0x4881 \u2014 0x4880 mail-manage ack (server -> client)"
  endian: be
doc: |
  Reply to the unimplemented 0x4880 mail request. Parser 0xD52E88, dispatcher stub 0xD39534.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD52EF4) and drives the subsystem-0x55 status/result
  setters. Nothing else is read: a bare 4-byte result is a complete reply. PROTOCOL.md documents
  no layout for this id.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success. [ELF 0xD52EF4; live 2026-07-26 — served, and the client's
      mailbox refreshes without a stall]

      The whole payload: 4 bytes, no body, no flags byte (contrast `0x4801`, whose second byte
      decides whether the request completes at all). The delete itself is server-side bookkeeping
      — the client re-lists afterwards and believes whatever the new `0x4822` entries say.
