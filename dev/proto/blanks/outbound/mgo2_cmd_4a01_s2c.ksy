meta:
  id: mgo2_cmd_4a01_s2c
  title: "MGO2 0x4A01 - unmapped 0x4Axx record reply with a state-bounded blob (server -> client)"
  endian: be
params:
  - id: blob_len
    type: u4
    doc: |
      NOT A WIRE FIELD. min(u16 at obj+0x0DA, 128), taken from client state at 0xD50800.
      Declared as a parameter so nobody mistakes the blob for a fixed 128 bytes.
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A01; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39870,
  parser 0xD50598.
  THE BLOB LENGTH IS NOT ON THE WIRE. The byte loop at 0xD507DC-0xD50814 runs while
  `i < u16 at obj+0x0DA` AND `i < 128` (0xD507F4 / 0xD50800 / 0xD50808), i.e. the count comes
  from client state - the third of the eight u16s at obj+0x0D6..0x0E4 that the 0x4A24/0x4A31
  parser writes (0xD4FD48-0xD4FE0C). This packet also reads eight u16s of its own, but into a
  DIFFERENT base, so it is not established that they are the same slots; treat the bound as
  external and declared as a parameter below. Getting this wrong desyncs everything after it.
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230, not by this parser
  directly: u32 then u16, both validated against the client's currently open object for this
  subsystem (0xD4929C and 0xD492D4); a mismatch aborts with -1018 before another byte is read.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230 (0xD49274)."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230 (0xD492B0)."
  - id: echo_id
    type: u4
    doc: "[ELF] read at 0xD5066C, compared at 0xD50694 against a u32 the client holds; mismatch aborts and nothing further is read. [UNKNOWN] which id."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD506A8 -> obj+0x004."
  - id: unknown_0x0b
    type: u1
    doc: "[UNKNOWN] read at 0xD506C4, into a second object's +0x000."
  - id: halves
    type: u2
    repeat: expr
    repeat-expr: 8
    doc: "[ELF] eight u16, unrolled 0xD506E0-0xD507A4, stored at that object's +0x002..+0x010. [UNKNOWN] meanings."
  - id: unknown_0x1c
    type: u4
    doc: "[UNKNOWN] read at 0xD507BC and widened to 64 bits at obj+0x1BF0 (the same slot and the same widening as 0x4A24's field at 0xD4FE24)."
  - id: blob
    size: blob_len
    doc: "[ELF] byte-at-a-time loop 0xD507DC-0xD50814. Length = min(client state u16 at obj+0x0DA, 128) - see the top-level note. [UNKNOWN] contents."
  - id: flags
    type: u1
    doc: "[ELF] 1-byte raw read (0xD5082C) expanded bit by bit into a flags word. [UNKNOWN]."
  - id: unknown_after_flags
    type: u1
    doc: "[UNKNOWN] read at 0xD5090C -> obj+0x005."
  - id: trailing_words
    type: u4
    repeat: expr
    repeat-expr: 6
    doc: "[ELF] six u32, unrolled 0xD50928-0xD509B4 -> obj+0x1C64..+0x1C78 - the same six slots 0x4A24/0x4A31 fill. [UNKNOWN] meanings."
