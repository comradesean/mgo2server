meta:
  id: mgo2_cmd_4b12_s2c
  title: "MGO2 0x4B12 - unmapped 0x4Bxx list reply, 48-byte records (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4B12; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39B5C,
  parser 0xD56010.
  The only size-driven list in the 0x4Bxx block: fronted by the length-aware call 0xD5CEB0
  at 0xD560BC (`cmpwi r3,-1` -> exit), N records back to back, no count field. The client array
  holds 100 entries (`cmpwi r4,99` at 0xD561E4); anything past that is parsed and dropped.
  The two 16-byte text fields with a word between them are the same shape as one entry of the
  0x4A11 / 0x4A33 lists, at a different width - the resemblance is noted, not asserted.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF] size-driven (0xD560BC). 48 bytes each."
types:
  entry:
    doc: "[ELF] 48 wire bytes."
    seq:
      - id: id
        type: u4
        doc: "[UNKNOWN] read at 0xD560D4 -> record+0x00."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] 16-byte raw read (0xD560F4, -> r1+120). Width certain; string role from the width only."
      - id: unknown_0x14
        type: u4
        doc: "[UNKNOWN] read at 0xD56110 (-> r1+140)."
      - id: name2
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] second 16-byte raw read (0xD56130, -> r1+144)."
      - id: unknown_0x28
        type: u1
        doc: "[UNKNOWN] read at 0xD56158."
      - id: unknown_0x29
        type: u1
        doc: "[UNKNOWN] read at 0xD56178."
      - id: unknown_0x2a
        type: u1
        doc: "[UNKNOWN] read at 0xD56190."
      - id: unknown_0x2b
        type: u1
        doc: "[UNKNOWN] read at 0xD561A8. These four bytes are read as four separate u8, not one word - a server writing a u32 here would still parse, but the client treats them as four values."
      - id: unknown_0x2c
        type: u4
        doc: "[UNKNOWN] read at 0xD561CC (-> r1+168). Last field of the record."
