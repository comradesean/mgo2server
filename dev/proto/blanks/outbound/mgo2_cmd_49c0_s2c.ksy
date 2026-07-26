meta:
  id: mgo2_cmd_49c0_s2c
  title: "MGO2 0x49C0 - unmapped 0x49xx keyed-update reply (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x49C0; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39820,
  parser 0xD4E420.
  SHAPE: a status word, then a COUNT, then count key/value word pairs. The count is a real
  wire field (read at 0xD4E4C0, loop bound at 0xD4E550: `cmpw r26,count; blt -> 0xD4E4D4`), so
  unlike most list replies in this range it is NOT size-driven. Each pair's key is matched
  against three fixed client fields (obj+0x84, obj+0xB0, obj+0xDC at 0xD4E504-0xD4E534) and on
  a hit the value is stored at obj+0x90 / obj+0xBC / obj+0xE8 respectively. Keys that match
  nothing are silently dropped.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE34 delimiter-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  ADDRESS AND SEMANTICS CORRECTION (2026-07-26, read out of the primitive itself): the string
  reader's entry point is **0xD5CE34**, not 0xD5CE3C — the previous function's `blr` is at
  0xD5CE30 and 0xD5CE3C is two instructions into the body. It is **not** a NUL-terminated
  string reader: the loop compares each byte against **r5, a caller-supplied delimiter**
  (`cmpw cr7,r0,r5` at 0xD5CE78); NUL is only a secondary stop (`cmpwi cr6,r0,0` at 0xD5CE7C).
  Callers that pass r5 = 0 get NUL termination as a special case. Either way the cursor is
  advanced **past** the terminator (`addi r9,r9,1` at 0xD5CEA4 after `stw r11` at 0xD5CE94), so
  the field consumes **len + 1** wire bytes, and the client writes its own NUL at dest+len
  (0xD5CE9C).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: status
    type: u4
    doc: |
      [ELF] read at 0xD4E498. MUST be 0: any non-zero value branches straight to RD_END
      (0xD4E4AC / 0xD4E4B0 -> 0xD4E564) and the count and pairs are never read. This is the one
      field in this file whose behaviour is established rather than guessed.
  - id: pair_count
    type: u4
    doc: "[ELF] number of pairs that follow, read at 0xD4E4C0. Loop-bound, not a byte length."
  - id: pairs
    type: pair
    repeat: expr
    repeat-expr: pair_count
    doc: "[ELF] count-driven, NOT size-driven (0xD4E550)."
types:
  pair:
    seq:
      - id: key
        type: u4
        doc: "[UNKNOWN] read first (0xD4E4D4). Matched against obj+0x84 / obj+0xB0 / obj+0xDC; an unmatched key is discarded."
      - id: value
        type: u4
        doc: "[UNKNOWN] read second (0xD4E4F0). Stored 12 bytes past whichever field the key matched."
