meta:
  id: mgo2_cmd_49c3_s2c
  title: "MGO2 0x49C3 - unmapped 0x49xx reply (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x49C3; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39840,
  parser 0xD4DE50.
  After RD_END the parser walks a 3-element client array (stride 44, 0xD4DF20-0xD4DF5C and
  0xD4DF60-0xD4DFA8, bound 88 = 2*44) matching the value it just read and clearing/refilling
  slot+12. So this is a single-record UPDATE against a small fixed table the client already
  holds - not a list reply.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: unknown_0x00
    type: u4
    doc: "[UNKNOWN] read at 0xD4DEB0 into r1+120. Used as the match key against slot+0 of the 3-entry table. Position exact, meaning unestablished."
  - id: unknown_0x04
    type: u4
    doc: "[UNKNOWN] read at 0xD4DEC8 into r1+116. Position exact, meaning unestablished."
  - id: unknown_0x08
    type: u1
    doc: "[UNKNOWN] read at 0xD4DEE0 into r1+112. Last byte of the payload. Position exact, meaning unestablished."
