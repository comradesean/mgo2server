meta:
  id: mgo2_cmd_49c1_s2c
  title: "MGO2 0x49C1 - unmapped 0x49xx single-record reply (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x49C1; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39830,
  parser 0xD4E138.
  A single fixed 32-byte record, no loop. After RD_END the parser scans two small client
  tables (a 2-element one at obj+6268 stride 44, and a 3-element one) to place the record, then
  raises 0xD33CD8. Storage offsets are not recoverable cleanly because the placement is
  conditional; only the wire layout below is asserted.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: unknown_0x00
    type: u2
    doc: "[UNKNOWN] read FIRST, at 0xD4E1B0 (into r1+114). Note the u16 precedes the u32s - do not reorder. Position exact, meaning unestablished."
  - id: unknown_0x02
    type: u4
    doc: "[UNKNOWN] read at 0xD4E1C8 (r1+120). Position exact, meaning unestablished."
  - id: unknown_0x06
    type: u4
    doc: "[UNKNOWN] read at 0xD4E1E0 (r1+116). Position exact, meaning unestablished."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD4E1F8 (r1+112). Position exact, meaning unestablished."
  - id: unknown_0x0b
    type: u1
    doc: "[UNKNOWN] read at 0xD4E210 (r1+113). Position exact, meaning unestablished."
  - id: unknown_0x0c
    type: u4
    doc: "[UNKNOWN] read at 0xD4E228 (r1+124). Position exact, meaning unestablished."
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [INFERRED] a 16-byte text field: fixed 16-byte raw read at 0xD4E244 (0xD5D018, len 16),
      the same width and read style every confirmed name field in this protocol uses
      (mgo2_cmd_4902.ksy name, mgo2_cmd_4221.ksy). Nothing renders it in a traced path, so
      "name" is the shape, not a proven role.
