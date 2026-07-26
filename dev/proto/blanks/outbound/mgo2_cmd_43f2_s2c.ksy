meta:
  id: mgo2_cmd_43f2_s2c
  title: "MGO2 0x43f2 — unidentified in-match notification (server -> client)"
  endian: be
doc: |
  Parser 0xD5B588, reached from the GAME dispatcher 0xD387C8 (compare tree at 0xD38804) via the stub at 0xD39D7C. One of the four
  0x43Fx ids belonging to the in-match subsystem the client sends 0x43E0 / 0x43E2 into
  (COMMANDS.md, "0x43e*/0x43f*"). Never sent by us; nothing in PROTOCOL.md or OBSERVED.md.

  Trace: the parser resolves a subsystem object with 0xD3F7B0, checks the header id
  (cmpwi 0x43F2 at 0xD5B5E0), opens the reader (0xD5C844), reads EXACTLY ONE u32
  (0xD5CCD8 at 0xD5B600) straight into that object at **obj+0x90**, closes the reader, then
  reloads obj+0x90 and calls 0xD33CD8 with UI event id 0x2D (45) and the value, followed by
  0xD5B41C (a screen/state poke shared with 0x43F3 and 0x43F4).

  Note that unlike the list-triple ids this family does NOT use the status/result setters
  0xD32E08 / 0xD32E70 — it is a push notification path, not a request/reply transaction.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: unknown_0x00
    type: u4
    doc: |
      [ELF 0xD5B600] The whole payload: one u32, stored at obj+0x90 and forwarded as the value
      of UI event 0x2D. [UNKNOWN] meaning — the binary gives the width, the destination and the
      event number, and nothing about what the event renders. Not a result code as far as the
      parser is concerned: there is no zero/nonzero branch on it.
