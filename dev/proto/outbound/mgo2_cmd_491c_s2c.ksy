meta:
  id: mgo2_cmd_491c_s2c
  title: "MGO2 0x491c — server -> client: two-word result reply, 0x49xx clan/GHQ family"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x491c` at `0xd38c40` and branches to the
  thunk at `0xd396c0`, which tail-calls the parser at `0xd4d8d4`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  Result-gated: one 4-byte read, and **only if it is zero** two more 4-byte reads
  [READ 0xd4d94c-0xd4d984]. Then request-status slot **69** is completed with the result.
  The two words are read into stack slots and, in this function, never stored anywhere —
  the parser at `0xD4EA60` is called on entry to fetch a roster object, but neither word
  reaches it. So the payload is 12 bytes on success and 4 bytes on failure.

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
    doc: "[ELF 0xd4d93c] 0 = success; nonzero ends the parse here (4-byte payload)."
  - id: unknown_04
    type: u4
    if: result == 0
    doc: "[UNKNOWN] read into a stack slot and discarded by this function. Position exact."
  - id: unknown_08
    type: u4
    if: result == 0
    doc: "[UNKNOWN] as above."
