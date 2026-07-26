meta:
  id: mgo2_cmd_4a13_s2c
  title: "MGO2 0x4A13 - unmapped reply, two named eight-word groups (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A13; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain), entry stub 0xD39578,
  parser 0xD44EF8.
  ODD ONE OUT: 0x4A13's parser does not live with the rest of the 0x4Axx block (0xD4Exxx -
  0xD52xxx) but at 0xD44EF8, in the same neighbourhood as the game-lobby parsers - 0x4902's is
  0xD47E18. That is a hint it belongs to a different subsystem than its id suggests; it is only
  a hint, and its stub (0xD39578) sits in the low stub cluster with them too.

  No identity header. Two structurally identical groups of {u32, 16-byte text, u32 x8}, each
  eight-word array hard-coded (`cmpdi r28,8` at 0xD450C8 and 0xD4513C) - no counts on the wire.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: unknown_0x00
    type: u4
    doc: "[ELF] read at 0xD44F7C (-> r1+120) and compared at 0xD44FA0 against a client-held id; mismatch aborts. [UNKNOWN] which id."
  - id: unknown_0x04
    type: u4
    doc: "[UNKNOWN] read at 0xD44FB0 (-> r1+116)."
  - id: unknown_0x08
    type: u1
    doc: "[UNKNOWN] read at 0xD44FC8 (-> r1+113). Note the parser stores this BEFORE the next byte despite reading it first - wire order is as listed."
  - id: unknown_0x09
    type: u1
    doc: "[UNKNOWN] read at 0xD44FE0 (-> r1+112)."
  - id: unknown_0x0a
    type: u4
    doc: "[UNKNOWN] read at 0xD44FF8 (-> r1+124)."
  - id: unknown_0x0e
    type: u4
    doc: "[UNKNOWN] read at 0xD45010 (-> r1+128)."
  - id: group_a
    type: named_words
    doc: "[ELF] reads at 0xD45070 (u32 -> obj+0x156C), 0xD45090 (16-byte raw -> obj+0x1570), then the eight-word loop 0xD450A4-0xD450D4."
  - id: group_b
    type: named_words
    doc: "[ELF] reads at 0xD450E4 (u32 -> +0x4C), 0xD45104 (16-byte raw -> +0x50), then the eight-word loop 0xD45118-0xD45148. Structurally identical to group_a; separate storage."
  - id: unknown_tail
    type: u1
    doc: "[UNKNOWN] last byte, read at 0xD45158 -> obj+0x160."
types:
  named_words:
    seq:
      - id: id
        type: u4
        doc: "[UNKNOWN] leading word."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] 16-byte raw read; width certain, string role from the width only."
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 8
        doc: "[ELF] exactly eight u32; the count is a hard-coded loop bound, not a wire field."
