meta:
  id: mgo2_cmd_43f4_s2c
  title: "MGO2 0x43f4 — unidentified in-match notification, EMPTY payload (server -> client)"
  endian: be
doc: |
  Parser 0xD5B45C (29 instructions, ends 0xD5B4CC), reached from the GAME dispatcher 0xD387C8 (compare tree at 0xD38804) via the
  stub at 0xD39D9C. Part of the in-match 0x43E*/0x43F* subsystem (COMMANDS.md). Never sent by
  us; absent from PROTOCOL.md and OBSERVED.md.

  THE PAYLOAD IS EMPTY. The parser never opens a stream reader at all: it fetches the packet
  header (0xD3879C), compares the id (cmpwi 0x43F4 at 0xD5B494), and on a match calls
  0xD33CD8 with UI event id 0x2F (47) and value 0 (li r4,47 / li r5,0 set up at
  0xD5B488/0xD5B490, before the compare), then 0xD5B41C. There is no call to 0xD5C844,
  0xD5CB8C, 0xD5CC14, 0xD5CCD8, 0xD5D018 or any other read primitive anywhere in the function.

  This is a bare notify: the id itself is the whole message. A server sending trailing bytes
  would have them ignored, and sending none is correct.

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
      [ELF 0xD5B45C] Present only to state that nothing is parsed. The parser reads zero bytes
      of payload — see the top-level doc. Expected length 0.
