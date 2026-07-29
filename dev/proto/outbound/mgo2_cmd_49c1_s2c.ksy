meta:
  id: mgo2_cmd_49c1_s2c
  title: "MGO2 0x49C1 - unmapped 0x49xx single-record reply (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x49C1; COMMANDS.md lists it only as "parsed but never sent". Everything below is read out of
  the client parser - field ORDER and WIDTH are solid, MEANINGS are not.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39830,
  parser 0xD4E138.
  A single fixed 32-byte record, no loop. After RD_END the parser scans two small client
  tables (a 2-element one at obj+6268 stride 44, and a 3-element one) to place the record, then
  raises 0xD33CD8. Storage offsets are not recoverable cleanly because the placement is
  conditional; only the wire layout below is asserted.
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
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

seq:
  - id: unknown_0x00
    type: u2
    doc: "[UNKNOWN] read FIRST, at 0xD4E1B0 (into r1+114). Note the u16 precedes the u32s - do not reorder. Position exact, meaning unestablished."
  - id: unknown_0x02
    type: u4
    doc: "[UNKNOWN] read at 0xD4E1C8 (r1+120). Position exact, meaning unestablished."
  - id: unknown_0x06
    type: u4
    doc: "[UNKNOWN] read at 0xD4E1E0 (r1+116). Position exact, meaning unestablished."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD4E1F8 (r1+112). Position exact, meaning unestablished."
  - id: unknown_0x0b
    type: u1
    doc: "[UNKNOWN] read at 0xD4E210 (r1+113). Position exact, meaning unestablished."
  - id: unknown_0x0c
    type: u4
    doc: "[UNKNOWN] read at 0xD4E228 (r1+124). Position exact, meaning unestablished."
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [INFERRED] a 16-byte text field: fixed 16-byte raw read at 0xD4E244 (0xD5D018, len 16),
      the same width and read style every confirmed name field in this protocol uses
      (mgo2_cmd_4902.ksy name, mgo2_cmd_4221.ksy). Nothing renders it in a traced path, so
      "name" is the shape, not a proven role.
