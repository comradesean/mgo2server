meta:
  id: mgo2_cmd_4823_s2c
  title: "MGO2 0x4823 — mailbox list END (server -> client)"
  endian: be
doc: |
  End packet of the 0x4820 mailbox triple. Parser 0xD52F5C, dispatcher stub 0xD39514.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD52FE4) and drives the subsystem-0x55 status/result
  setters. PROTOCOL.md: "4 bytes result".

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success. [CONFIRMED by PROTOCOL.md; ELF 0xD52FE4; live 2026-07-26]

      Requires the in-flight flag at `mailBlock+0x1DBD0` to be **nonzero** — i.e. a `0x4821` with
      result 0 must have preceded it — else the handler returns -73 (`0xD52FCC`). It clears the
      flag and fires event 85/2.

      **There is no compaction or filter pass here**, unlike the roster triple's `0x4583`
      (`0xD466D4`), which drops any collected record whose u16 at wire 0x14 is zero. Entries that
      fail to appear in the mailbox are therefore not being filtered — they were filed into a
      category no UI code reads. See `mgo2_cmd_4822_s2c.ksy`.
