meta:
  id: mgo2_cmd_4b11_s2c
  title: "MGO2 0x4B11 - unmapped 0x4Bxx (clan/GHQ) reply, three words (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4B11; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39B4C,
  parser 0xD557A0.
  Raises two completion events (0xD32E70 at 0xD558B4 and 0xD558D4), so two UI waiters key off
  this one reply.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: result
    type: u4
    doc: "[ELF] read at 0xD5582C. [UNKNOWN] meaning."
  - id: unknown_0x04
    type: u4
    doc: "[UNKNOWN] read at 0xD55854. Position exact, meaning unestablished."
  - id: unknown_0x08
    type: u4
    doc: "[UNKNOWN] read at 0xD5586C. Position exact, meaning unestablished."
