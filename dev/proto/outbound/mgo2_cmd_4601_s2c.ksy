meta:
  id: mgo2_cmd_4601_s2c
  title: "MGO2 0x4601 — player search, list START (server -> client)"
  endian: be
doc: |
  Start packet of the 0x4600 player-search triple. Parser 0xD45DF0, dispatcher stub 0xD39370.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD45E7C), then status setter 0xD32E08 / result setter
  0xD32E70 on subsystem index 0x53. Zero resets the entry count and lets the transaction proceed;
  nonzero completes it as failed with the value rendered %08X in the search error dialog
  (screen 0x0C13).

  PROTOCOL.md: "The start and end packets each carry a {u32 result code} -- 0 for success, not a
  count." It also records the traced-but-untested -611 (-0x263) "no results found" sentinel branch
  in this handler; we send the plain empty success triple instead.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success -- NEVER a record count (a count of 5 came back as
      the 1032:00000005 dialog for the sibling family; OBSERVED.md). [CONFIRMED]
