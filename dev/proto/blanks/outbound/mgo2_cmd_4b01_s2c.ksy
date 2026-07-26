meta:
  id: mgo2_cmd_4b01_s2c
  title: "MGO2 0x4B01 - unmapped 0x4Bxx (clan/GHQ) reply, two words (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4B01; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39ACC,
  parser 0xD56DBC.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: result
    type: u4
    doc: "[ELF] first word, read at 0xD56E2C. [UNKNOWN] meaning; not compared against 0 in the parser."
  - id: unknown_0x04
    type: u4
    doc: "[UNKNOWN] second word, read at 0xD56E50 into a separate stack slot (r1+116). Position exact, meaning unestablished."
