meta:
  id: mgo2_cmd_4983_s2c
  title: "MGO2 0x4983 — server -> client: clan-member list END (closes the 0x4981/0x4982/0x4983 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4983` at `0xd38cf0` and branches to the
  thunk at `0xd39640`, which tail-calls the parser at `0xd49ea4`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  Guarded: the parser reads `list+0x000` first and **returns -73 without touching the payload
  if it is 0** [READ 0xd49f10], i.e. an end packet with no preceding `0x4981` start is
  ignored. Otherwise one 4-byte read, then `0xD32E08(ctx, 62, 2)` / `0xD32E70(ctx, 62, result)`
  completes the request and the result is also stored at `list+0x000`.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xd49f34] The only field. 0 for success in both start and end, as with every other
      list triple in this protocol (PROTOCOL.md, `dev/proto/README.md`).
