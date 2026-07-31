meta:
  id: mgo2_cmd_4b13_s2c
  title: "MGO2 0x4b13 — clan list END (server -> client)"
  endian: be
doc: |
  **End of the clan list.** The last packet of the 0x4b11 / 0x4b12 / 0x4b13 triple answering the
  paged clan list request 0x4b10. [CONFIRMED LIVE 2026-07-27].

  Order on the wire: 0x4b11 header `{result, offset, total}`, then 0x4b12 with the 48-byte rows
  (omitted entirely when the page is empty), then this. Like every other list end in the protocol
  it carries a **result code, never a count** — the client counts the 0x4b12 records itself, and
  putting a count in a start/end slot produced the live 1032:00000005 error on the sibling social
  path (dev/docs/OBSERVED.md).

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39B6C,
  parser 0xD55698.
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
  - id: result
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] Clan-list-end result, and the only field the parser reads. 0 = the
      list is complete. **Never a record count** — see the top-level doc.
