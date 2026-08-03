meta:
  id: mgo2_cmd_43f5_s2c
  title: "MGO2 0x43f5 — unidentified in-match notification, EMPTY payload (server -> client)"
  endian: be
doc: |
  Parser 0xD5B3B0 (27 instructions, ends 0xD5B418), reached from the GAME dispatcher 0xD387C8 (compare tree at 0xD38804) via the
  stub at 0xD39DBC. Part of the in-match 0x43E*/0x43F* subsystem (COMMANDS.md). Never sent by
  us; absent from PROTOCOL.md and OBSERVED.md.

  THE PAYLOAD IS EMPTY, exactly as for 0x43F4: no reader is opened and no read primitive is
  called. The function fetches the header (0xD3879C), compares the id (cmpwi 0x43F5 at
  0xD5B3E8) and calls 0xD33CD8 with UI event id 0x37 (55) and value 0 (li r4,55 / li r5,0 at
  0xD5B3DC/0xD5B3E0). Unlike 0x43F2/0x43F3/0x43F4 it does NOT then call 0xD5B41C.

  A bare notify: the id itself is the whole message.

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
  - id: unknown_body
    size-eos: true
    doc: |
      [ELF 0xD5B3B0] Present only to state that nothing is parsed: the body is never read — the
      parser reads zero bytes of payload — see the top-level doc. Expected length 0.
