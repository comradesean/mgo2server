meta:
  id: mgo2_cmd_4a20_s2c
  title: "MGO2 0x4A20 - unmapped 0x4Axx reply, counted groups plus state-bounded blob (server -> client)"
  endian: be
params:
  - id: blob_len
    type: u4
    doc: "NOT A WIRE FIELD. min(u16 at obj+0x0DA, 128), from client state (0xD51C14)."
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A20; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below come out of the client parser and are solid. MEANINGS are not.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD398B0,
  parser 0xD51A08.
  TWO different count sources in one packet, which is why they are called out separately:
  the `groups` count IS a wire field (the u16 at 0xD51B64, used as the loop bound at 0xD51B88),
  while the trailing blob's length is NOT (loop 0xD51BF0, bounded by `i < u16 at obj+0x0DA`
  and `i < 128` - 0xD51C08 / 0xD51C14 / 0xD51C1C, client state, same slot 0x4A01 uses).
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230, not by this parser
  directly: u32 then u16, both validated against the client's currently open object for this
  subsystem (0xD4929C and 0xD492D4); a mismatch aborts with -1018 before another byte is read.
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
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230."
  - id: echo_id
    type: u4
    doc: "[ELF] read at 0xD51ADC, compared at 0xD51B04 against a u32 the client holds; mismatch aborts. [UNKNOWN] which id."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD51B18 -> obj+0x004."
  - id: unknown_0x0b
    type: u1
    doc: "[UNKNOWN] read at 0xD51B34, into a second object's +0x000."
  - id: unknown_0x0c
    type: u2
    doc: "[UNKNOWN] read at 0xD51B4C (-> r1+114). Read BEFORE group_count. Position exact, meaning unestablished."
  - id: group_count
    type: u2
    doc: "[ELF] read at 0xD51B64 (-> r1+112) and used as the outer bound of the group loop (0xD51B88, `lhz r4,112(r1)`, stride 16). A real wire count."
  - id: groups
    type: group
    repeat: expr
    repeat-expr: group_count
    doc: "[ELF] loop 0xD51B88-0xD51BC8; four u32 per group (`cmpdi r29,4` at 0xD51BB8), stride 16."
  - id: blob
    size: blob_len
    doc: "[ELF] byte-at-a-time loop at 0xD51BF0. Length = min(client state u16 at obj+0x0DA, 128), NOT a wire field. [UNKNOWN] contents."
types:
  group:
    seq:
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 4
        doc: "[UNKNOWN] four u32 per group, read at 0xD51BB0."
