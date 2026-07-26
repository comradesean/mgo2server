meta:
  id: mgo2_cmd_4a03_s2c
  title: "MGO2 0x4A03 - unmapped 0x4Axx reply, word plus four halves (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A03; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD398C0,
  parser 0xD51880.
  No identity header (0xD49230 is NOT called) and no loop: five fields, 12 bytes, then a
  single 0xD33CD8 notify. NOTE the read order: the four u16s are read into r1+118, r1+112,
  r1+114, r1+116 - i.e. the parser stores them out of order, which is why the offsets below are
  wire positions and the storage slots are quoted per field instead.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: unknown_0x00
    type: u4
    doc: "[UNKNOWN] read at 0xD51908 (-> r1+120). Position exact, meaning unestablished."
  - id: unknown_0x04
    type: u2
    doc: "[UNKNOWN] read at 0xD51940 (-> r1+118). Position exact, meaning unestablished."
  - id: unknown_0x06
    type: u2
    doc: "[UNKNOWN] read at 0xD51958 (-> r1+112). Position exact, meaning unestablished."
  - id: unknown_0x08
    type: u2
    doc: "[UNKNOWN] read at 0xD51970 (-> r1+114). Position exact, meaning unestablished."
  - id: unknown_0x0a
    type: u2
    doc: "[UNKNOWN] read at 0xD51988 (-> r1+116). Position exact, meaning unestablished."
