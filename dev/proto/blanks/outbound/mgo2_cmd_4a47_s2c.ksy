meta:
  id: mgo2_cmd_4a47_s2c
  title: "MGO2 0x4A47 - unmapped 0x4Axx reply, parsed inline in the dispatcher (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in PROTOCOL.md or OBSERVED.md describes 0x4A47.

  Evidence: GAME dispatcher 0xD387C8 (compare tree at 0xD38804), entry stub 0xD399C0 - and unusually there is NO separate
  parser function: 0x4A47 is parsed INLINE inside the dispatcher (0xD399C0-0xD39AB8), the only
  id in this batch that is. The dispatcher re-checks the id itself (0xD399D4, cmpwi 19015)
  before reading.

  Destination is a 6-byte client field at obj+0x6D0C, which the parser first zeroes with three
  sth stores (0xD39A04-0xD39A0C) - so a short/absent value reads as 0 rather than stale.
  On success it calls 0xD33CD8 with event 35 (0xD39AA8: li r4,35).
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
    type: u1
    doc: |
      [ELF] read at 0xD39A20 into a stack byte and RANGE-CHECKED: `cmplwi 9 / bgt+ -> bail`
      (0xD39A34). Values 0-9 only; 10 or more aborts the parse silently, so this is an index or
      small enum with ten legal values. Stored at obj+0x6D0C after the check. [UNKNOWN] meaning.
  - id: unknown_0x01
    type: u1
    doc: "[UNKNOWN] read at 0xD39A4C -> obj+0x6D0D. Position exact, meaning unestablished."
  - id: unknown_0x02
    type: u1
    doc: "[UNKNOWN] read at 0xD39A68 -> obj+0x6D0E. Position exact, meaning unestablished."
  - id: unknown_0x03
    type: u2
    doc: "[UNKNOWN] read at 0xD39A84 -> obj+0x6D10. Note the gap: obj+0x6D0F is skipped (alignment padding in the struct, NOT on the wire)."
