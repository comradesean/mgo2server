meta:
  id: mgo2_cmd_4a50_s2c
  title: "MGO2 0x4A50 - unmapped 0x4Axx reply with a 256-byte text block (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A50; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39ABC,
  parser 0xD502C8.
  269 bytes, no loop, no identity header. The 256-byte block at the end is the largest single
  text field seen anywhere in Channel A; after RD_END the parser memcpy's (0xDC95C0) the parsed
  record into client storage and notifies via 0xD33CD8.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE3C NUL-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: unknown_0x00
    type: u4
    doc: "[UNKNOWN] read at 0xD50348. Position exact, meaning unestablished."
  - id: unknown_0x04
    type: u1
    doc: "[UNKNOWN] read at 0xD50360 (-> r1+116). Position exact, meaning unestablished."
  - id: unknown_0x05
    type: u4
    doc: "[UNKNOWN] read at 0xD50378 (-> r1+120). Position exact, meaning unestablished."
  - id: unknown_0x09
    type: u4
    doc: "[UNKNOWN] read at 0xD50390 (-> r1+124). Position exact, meaning unestablished."
  - id: text
    size: 256
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF] fixed 256-byte raw read (0xD503B8, 0xD5D018 with len 256) into r1+128. Width is
      certain. "text" is [INFERRED] from the width and from 0xD5D018's NUL-terminating
      behaviour, which only matters for strings; no renderer was traced.
