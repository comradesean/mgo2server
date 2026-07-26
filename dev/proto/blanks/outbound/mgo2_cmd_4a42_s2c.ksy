meta:
  id: mgo2_cmd_4a42_s2c
  title: "MGO2 0x4A42 - unmapped 0x4Axx list reply, 94-byte records (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A42; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39950,
  parser 0xD4F7E8.
  A SIZE-DRIVEN LIST fronted by the length-aware call 0xD5CEB0 at 0xD4F890 (`cmpwi r3,-1`
  -> exit): N records back to back, no count field, exactly the 0x4902 pattern. The client's
  array holds 64 entries (`cmpwi r3,63` at 0xD4FB04); record 65 onward is parsed and dropped.
  COMMANDS.md flags 0x4A11 / 0x4A33 / 0x4A42 as the three list replies of this block - this is
  the widest record of the three.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF] size-driven (0xD4F890). 94 bytes each."
types:
  entry:
    doc: "[ELF] 94 wire bytes."
    seq:
      - id: id
        type: u4
        doc: "[UNKNOWN] read at 0xD4F8A8 -> record+0x00."
      - id: unknown_0x04
        type: u1
        doc: "[UNKNOWN] read at 0xD4F8C4 (-> r1+124)."
      - id: text
        size: 64
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] 64-byte raw read (0xD4F8E4). Width certain; string role from the width and the NUL-terminating read."
      - id: halves
        type: u2
        repeat: expr
        repeat-expr: 7
        doc: "[ELF] seven u16, unrolled 0xD4F900-0xD4F9A8 (r1+192 .. r1+204). Seven, not eight - the eighth slot in the neighbouring layouts has no read here."
      - id: unknown_0x55
        type: u4
        doc: "[UNKNOWN] read at 0xD4F9C4 (-> r1+116)."
      - id: unknown_0x59
        type: u4
        doc: "[UNKNOWN] read at 0xD4F9E8 (-> r1+216)."
      - id: unknown_0x5d
        type: u1
        doc: "[UNKNOWN] read at 0xD4FA04 (-> r1+220)."
      - id: unknown_0x5e
        type: u1
        doc: "[UNKNOWN] read at 0xD4FA20 (-> r1+221)."
      - id: flags
        type: u1
        doc: "[ELF] 1-byte raw read (0xD4FA40) expanded bit by bit into a flags word - each bit a distinct boolean. Last byte of the record. [UNKNOWN] meanings."
