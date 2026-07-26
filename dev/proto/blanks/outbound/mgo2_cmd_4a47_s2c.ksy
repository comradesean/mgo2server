meta:
  id: mgo2_cmd_4a47_s2c
  title: "MGO2 0x4A47 - unmapped 0x4Axx reply, parsed inline in the dispatcher (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in PROTOCOL.md or OBSERVED.md describes 0x4A47.

  Evidence: dispatcher 0xD38804, entry stub 0xD399C0 - and unusually there is NO separate
  parser function: 0x4A47 is parsed INLINE inside the dispatcher (0xD399C0-0xD39AB8), the only
  id in this batch that is. The dispatcher re-checks the id itself (0xD399D4, cmpwi 19015)
  before reading.

  Destination is a 6-byte client field at obj+0x6D0C, which the parser first zeroes with three
  sth stores (0xD39A04-0xD39A0C) - so a short/absent value reads as 0 rather than stale.
  On success it calls 0xD33CD8 with event 35 (0xD39AA8: li r4,35).
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: unknown_0x00
    type: u1
    doc: |
      [ELF] read at 0xD39A20 into a stack byte and RANGE-CHECKED: `cmplwi 9 / bgt+ -> bail`
      (0xD39A34). Values 0-9 only; 10 or more aborts the parse silently, so this is an index or
      small enum with ten legal values. Stored at obj+0x6D0C after the check. [UNKNOWN] meaning.
  - id: unknown_0x01
    type: u1
    doc: "[UNKNOWN] read at 0xD39A4C -> obj+0x6D0D. Position exact, meaning unestablished."
  - id: unknown_0x02
    type: u1
    doc: "[UNKNOWN] read at 0xD39A68 -> obj+0x6D0E. Position exact, meaning unestablished."
  - id: unknown_0x03
    type: u2
    doc: "[UNKNOWN] read at 0xD39A84 -> obj+0x6D10. Note the gap: obj+0x6D0F is skipped (alignment padding in the struct, NOT on the wire)."
