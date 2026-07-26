meta:
  id: mgo2_cmd_4982_s2c
  title: "MGO2 0x4982 — server -> client: clan-member list ENTRIES (middle of the 0x4981/0x4982/0x4983 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4982` at `0xd38ce8` and branches to the
  thunk at `0xd39630`, which tail-calls the parser at `0xd4b790`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  **No result code and no count.** The parser loops on `0xD5CEB0` (bytes-remaining) and reads
  records until the cursor reaches `hdr.payload_len` [READ 0xd4b83c]; each completed record is
  appended at `list+0x008 + 56*n` with the count at `list+0x004`, and the loop **aborts with
  -71 once the count exceeds 99** [READ 0xd4ba10] — so at most 100 entries are accepted and
  the 101st poisons the whole reply. Size-driven, not count-driven; record this, because
  getting that backwards has bitten this project before.

  Each record is assembled in a 56-byte stack scratch and then copied in two `lswi`/`stswi`
  chunks (32 bytes from scratch+0x00 to entry+0x08, 24 bytes from scratch+0x20 to entry+0x28).

  **One field is conditional.** The flag byte's bit 2 gates a second 16-byte string: the
  parser expands the byte into a word at scratch+0x24 (bit 0 -> 0x80, bit 1 -> 0x40, bit 2 ->
  0x20, bit 3 -> clears the low 5 bits and sets 0x01) and then re-reads that word, taking the
  extra `0xD5D018` 16-byte read only when 0x20 survives [READ 0xd4b918-0xd4b934]. So a record
  is **35 bytes with the bit clear and 51 bytes with it set** — there is no length prefix and
  no way to parse the stream without tracking that bit.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: |
      [ELF 0xd4b818-0xd4ba48] Repeat until the payload is exhausted. Count source is the
      payload length, NOT a leading count. Client-side cap 100 entries.
types:
  entry:
    seq:
      - id: unknown_00
        type: u4
        doc: "[UNKNOWN] first word of the record; scratch+0x00. Position exact, meaning unestablished."
      - id: name
        type: str
        size: 16
        doc: |
          [INFERRED] scratch+0x05. 16-byte block read with the raw-copy primitive; name-width
          by analogy with the 16-byte name fields in 0x4902 and 0x4221. Text is inferred, the
          width is [ELF 0xd4b874].
      - id: unknown_15
        type: u1
        doc: "[UNKNOWN] scratch+0x04 — read AFTER the 16-byte block, stored before it."
      - id: flags
        type: u1
        doc: |
          [ELF 0xd4b8b0-0xd4b934] Bit field, expanded one bit per position into the word at
          scratch+0x24: bit 0 -> 0x80, bit 1 -> 0x40, bit 2 -> 0x20, bit 3 -> clears the low
          five bits then sets 0x01. **Bit 2 also gates the presence of `optional_name`
          below.** Bits 4-7 are read but never expanded. Individual meanings [UNKNOWN].
      - id: optional_name
        type: str
        size: 16
        if: (flags & 0x20) != 0
        doc: |
          [ELF 0xd4b924] Present ONLY when the expanded flag word has 0x20 set, i.e. when
          wire bit 2 of `flags` is set. Copied to scratch+0x16. A second name-width string
          [INFERRED]; identity [UNKNOWN].
      - id: unknown_a
        type: u1
        doc: "[UNKNOWN] scratch+0x28."
      - id: unknown_b
        type: u1
        doc: "[UNKNOWN] scratch+0x29."
      - id: unknown_c
        type: u1
        doc: "[UNKNOWN] scratch+0x2a."
      - id: unknown_d
        type: u4
        doc: "[UNKNOWN] scratch+0x2c."
      - id: unknown_e
        type: u1
        doc: "[UNKNOWN] scratch+0x30."
      - id: unknown_f
        type: u1
        doc: "[UNKNOWN] scratch+0x31."
      - id: unknown_g
        type: s4
        doc: "[UNKNOWN] scratch+0x34, read with the 0xD5CC64 twin."
