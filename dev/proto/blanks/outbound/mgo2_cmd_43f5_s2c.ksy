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
seq:
  - id: unknown_body
    size-eos: true
    doc: |
      [ELF 0xD5B3B0] Present only to state that nothing is parsed. The parser reads zero bytes
      of payload — see the top-level doc. Expected length 0.
