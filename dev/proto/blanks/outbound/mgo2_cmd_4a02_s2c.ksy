meta:
  id: mgo2_cmd_4a02_s2c
  title: "MGO2 0x4A02 - unmapped 0x4Axx reply, echo plus a 128-byte blob (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A02; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below are read out of the client parser and are solid. MEANINGS are
  not - almost every field is [UNKNOWN] on purpose.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39860,
  parser 0xD4EF5C.
  READ SEQUENCE IS IDENTICAL TO 0x4A29 (parser 0xD50A90) field for field. They are separate
  functions with separate storage, so this is a matching shape, not a proven duplicate - no
  divergence test has been run.

  THE 128-BYTE BLOB IS READ ONE BYTE AT A TIME (loop 0xD4F084-0xD4F0A8, bound `base+128`) into a
  stack scratch buffer. No store from that buffer into the clan/session struct was traced, so
  whether the client keeps the contents at all is [UNKNOWN] - but the 128 bytes MUST be on the
  wire or everything after them desyncs.
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
    doc: "[ELF] see the identity-header note above (helper 0xD49230, read at 0xD49274)."
  - id: obj_serial
    type: u2
    doc: "[ELF] see the identity-header note above (helper 0xD49230, read at 0xD492B0)."
  - id: echo_id
    type: u4
    doc: |
      [ELF] read at 0xD4F040 and compared against a u32 the client already holds
      (obj+0x298 in the 0x4A02 path, 0xD4F050). A mismatch aborts the parse with -1106
      (0xFFFFFBAE) and NOTHING after this field is consumed. So the server must echo back the
      same id it delivered in the earlier packet of this exchange. [UNKNOWN] which id that is.
  - id: unknown_after_echo
    type: u1
    doc: "[UNKNOWN] read at 0xD4F070 -> obj+0x004. Position exact, meaning unestablished."
  - id: blob
    size: 128
    doc: |
      [ELF] exactly 128 bytes, consumed by a byte-at-a-time loop (0xD4F084..0xD4F0A8). Fixed
      length - no count field anywhere in this packet. [UNKNOWN] contents.
