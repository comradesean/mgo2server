meta:
  id: mgo2_cmd_4a21_s2c
  title: "MGO2 0x4A21 - unmapped 0x4Axx reply, counted groups plus state-bounded blob (server -> client)"
  endian: be
params:
  - id: blob_len
    type: u4
    doc: "NOT A WIRE FIELD. min(u16 at obj+0x0DA, 128), from client state (0xD517CC)."
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A21; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD398D0,
  parser 0xD51658.
  Same two-count shape as 0x4A20 but with NO identity header (0xD49230 is never called) and
  no leading pair of bytes: it opens straight on the echo id. The `groups` count is a wire u16
  (0xD51734, bound at 0xD51764); the blob length is client state (0xD517C0 / 0xD517CC:
  `i < u16 at obj+0x0DA` and `i < 128`).
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: echo_id
    type: u4
    doc: "[ELF] read at 0xD516FC, compared at 0xD51724 against a u32 the client holds; mismatch aborts and nothing further is read. [UNKNOWN] which id."
  - id: group_count
    type: u2
    doc: "[ELF] read at 0xD51734 (-> r1+112), used as the outer loop bound at 0xD51764. A real wire count."
  - id: groups
    type: group
    repeat: expr
    repeat-expr: group_count
    doc: "[ELF] loop 0xD51764-0xD5179C; four u32 per group (`cmpdi r29,4` at 0xD51790)."
  - id: blob
    size: blob_len
    doc: "[ELF] byte-at-a-time loop at 0xD517A8. Length = min(client state u16 at obj+0x0DA, 128), NOT a wire field. [UNKNOWN] contents."
types:
  group:
    seq:
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 4
        doc: "[UNKNOWN] four u32 per group, read at 0xD51788."
