meta:
  id: mgo2_cmd_4a12_s2c
  title: "MGO2 0x4A12 - unmapped clan/GHQ-block reply (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A12; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD398A0,
  parser 0xD51D54.

  The parser then runs the notify path 0xD32E3C / 0xD32E08 / 0xD32E70 and
  a send at 0xD418C0 - i.e. receiving this makes the client emit a follow-up request.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: result
    type: u4
    doc: |
      [ELF] The only field the parser reads. Every reply in this family whose parser reads a
      single u32 follows the same shape as the documented result singles (PROTOCOL.md), but
      nothing here proves 0 means success for THIS id - the value is not compared against 0
      inside the parser, it is handed to the UI/event layer. [UNKNOWN] semantics.
