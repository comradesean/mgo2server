meta:
  id: mgo2_cmd_4a28_s2c
  title: "MGO2 0x4A28 - unmapped 0x4Axx reply, eight-word array (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A28; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below are read out of the client parser and are solid. MEANINGS are
  not - almost every field is [UNKNOWN] on purpose.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39990,
  parser 0xD50CDC.
  An echo id then a FIXED eight-word array then one more word. The eight is a hard-coded
  loop bound (`cmpdi r31,8` at 0xD50DE8, stride 4 into obj+0x1C40), not a count on the wire -
  worth stating because most list replies in this range are size-driven and this one is neither.
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230 and therefore easy to
  miss when reading this parser alone: u32 then u16. Both are validated against the client's
  currently open object for this subsystem (u32 vs obj+0x000 at 0xD4929C, u16 vs obj+0x29C at
  0xD492D4); a mismatch aborts with -1018 (0xFFFFFC06) before another byte is consumed. For
  command id 0x4960 only, 0xD49230 skips both comparisons and just consumes the six bytes.
  Modelled below as `obj_id` + `obj_serial`; the names describe the check, not a proven meaning.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230."
  - id: echo_id
    type: u4
    doc: "[ELF] read at 0xD50D90, compared at 0xD50DB8 against a u32 the client holds; mismatch aborts. [UNKNOWN] which id."
  - id: words
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: "[ELF] exactly 8 u32, loop 0xD50DC4-0xD50DF4 -> obj+0x1C40 + 4*i. Fixed count. [UNKNOWN] meaning."
  - id: unknown_tail
    type: u4
    doc: "[UNKNOWN] read at 0xD50E04 -> obj+0x1C60. Position exact, meaning unestablished."
