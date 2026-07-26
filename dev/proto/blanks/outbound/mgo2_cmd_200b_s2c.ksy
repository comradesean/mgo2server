meta:
  id: mgo2_cmd_200b_s2c
  title: "MGO2 0x200b — news-list end (server -> client)"
  endian: be
doc: |
  Closes the news list (reply 3/3 to `0x2008`). Parser arm 0xd36710, GATE dispatcher 0xd361a4 (compare tree at 0xd361e8).
  Reads exactly one u32 (primitive 0xd5cc64 at 0xd3674c).

  Guard: `lwzu r0,3552(r27); cmpwi r0,0; beq -> bail(-73)` — the news marker must be non-zero,
  i.e. `0x2009` must have opened the list. Then `notify(event 12, state 2)`, `notify(event 12,
  value)`, and `marker = 0` (the read return code, always 0 here, is stored at `0(r27)`).

  Note the value is passed straight to the UI notification, exactly as in `0x2009`'s non-zero
  path — the same channel carries "list finished OK" and "list failed".

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x2008 — get news"
seq:
  - id: result
    type: u4
    doc: |
      [ELF] Wire 0x00. Forwarded verbatim as `notify(12, value)` at 0xd3678c. No comparison
      against 0 in this arm, so the parser accepts any value; we send 0.
