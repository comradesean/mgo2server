meta:
  id: mgo2_cmd_4a11_s2c
  title: "MGO2 0x4A11 - unmapped 0x4Axx list reply, 45-byte records (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A11; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39890,
  parser 0xD51F2C.
  A SIZE-DRIVEN LIST: the loop is fronted by the length-aware call 0xD5CEB0 at 0xD51FD4
  (`cmpwi r3,-1` -> exit), so the record count is however many fit in the payload - there is no
  count field, and the packet carries N records back to back exactly like 0x4902 does. The
  client also caps insertion against a stored u16 at obj+0x0D6 (0xD520E8), so records past
  that cap are parsed and dropped rather than rejected.

  READ SEQUENCE IS IDENTICAL TO 0x4A33 (parser 0xD524F4) field for field. Separate functions,
  separate storage - a matching shape, not a proven duplicate; no divergence test has been run.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF] size-driven (0xD51FD4). 45 bytes each; a short record desyncs the rest of the packet rather than erroring."
types:
  entry:
    doc: "[ELF] 45 wire bytes."
    seq:
      - id: unknown_0x00
        type: u2
        doc: "[UNKNOWN] read FIRST, at 0xD51FF0 (-> r1+114), before the word. Do not reorder."
      - id: unknown_0x02
        type: u4
        doc: "[UNKNOWN] read at 0xD52008 -> record+0x00."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] 16-byte raw read (0xD52028) -> record+0x04. Width certain; string role from the width only."
      - id: unknown_0x16
        type: u1
        doc: "[UNKNOWN] read at 0xD52044 -> record+0x15."
      - id: unknown_0x17
        type: u1
        doc: "[UNKNOWN] read at 0xD52060 (-> r1+112)."
      - id: name2
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] second 16-byte raw read (0xD52098) -> record+0x18."
      - id: unknown_0x28
        type: u1
        doc: "[UNKNOWN] read at 0xD520B4 -> record+0x29."
      - id: unknown_0x29
        type: u4
        doc: "[UNKNOWN] read at 0xD520D0 -> record+0x2C. Last field of the record."
