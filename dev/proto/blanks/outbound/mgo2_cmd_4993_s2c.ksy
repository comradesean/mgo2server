meta:
  id: mgo2_cmd_4993_s2c
  title: "MGO2 0x4993 — server -> client: game entry withdraw/remove ack (removes one 0x4991 record)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4993` at `0xd38c10` and branches to the
  thunk at `0xd396e0`, which tail-calls the parser at `0xd48b98`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  One 4-byte result; **only if it is zero** a second 4-byte word [READ 0xd48c2c-0xd48c4c].
  End-of-read, then — again only on success — the parser walks the four 72-byte records the
  `0x4991` reply filled, and for the one whose first word equals the second word read here it
  **zeroes that record** (`0xDD36F8`, 72 bytes) [READ 0xd48c68-0xd48cb0]. Request-status slot
  **71** is completed with the result either way.

  So the second word is a key into the `0x4991` table, and this reply is the "entry removed"
  counterpart. Payload 8 bytes on success, 4 on failure.

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
    doc: "[ELF 0xd48c1c] 0 = success; nonzero ends the parse (4-byte payload) and no record is removed."
  - id: entry_key
    type: u4
    if: result == 0
    doc: |
      [ELF 0xd48c40] Matched against the first word of each of the four 0x4991 records; the
      match is zeroed. No match = silent no-op. Names the same value as `unknown_00` of the
      0x4991 record type; its meaning is [UNKNOWN], only its role as the key is [ELF].
