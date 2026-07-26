meta:
  id: mgo2_cmd_4918_s2c
  title: "MGO2 0x4918 — server -> client: clan notification — member joined/updated (28-byte payload)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4918` at `0xd38bf0` and branches to the
  thunk at `0xd39700`, which tail-calls the parser at `0xd4d564`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **1** via `0xD33CD8(ctx, 1)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then u8, u32, a 16-byte raw block and u8, assembled into a 28-byte stack scratch
  that is memset first [READ 0xd4d5f0]. The first u8 is bounds-tested against 7 before use as
  a member index; the 16-byte block is passed to `0xDCC7F8` (a string-length helper) and the
  packet is **dropped if the result is 16**, i.e. the block must be NUL-terminated within its
  16 bytes [READ 0xd4d6c4]. Payload 28 bytes; event 1.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: clan_id
    type: u4
    doc: |
      [ELF 0xd49274] Must equal the client's cached clan id (`clan+0x000`) or the packet is
      dropped with `-1018`.
  - id: clan_serial
    type: u2
    doc: |
      [ELF 0xd492b0] Must equal the u16 at `clan+0x29C` — the serial the clan-record replies
      set and `0x49a8` updates. Mismatch -> `-1018`, packet dropped.
  - id: member_slot
    type: u1
    doc: "[INFERRED] member array index; > 7 aborts the mutation [ELF 0xd4d69c-0xd4d6a4]."
  - id: character_id
    type: u4
    doc: |
      [INFERRED] the 28-byte scratch's first word, matching `member.character_id` of the
      clan-record member array. Named from position, not from a label.
  - id: name
    type: str
    size: 16
    doc: |
      [ELF 0xd4d664] 16-byte raw block. **Must be NUL-terminated inside 16 bytes** — the
      parser measures it and drops the packet if the length comes back 16 [READ 0xd4d6c4].
      That check is what makes "text" here [ELF] rather than [INFERRED].
  - id: unknown_1b
    type: u1
    doc: "[UNKNOWN] last byte; scratch+0x19. Compared against 9, 2 and 1 in the post-processing at 0xd4d6dc."
