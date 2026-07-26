meta:
  id: mgo2_cmd_4932_s2c
  title: "MGO2 0x4932 — server -> client: clan notification carrying u8 + u32 + u8"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4932` at `0xd38c74` and branches to the
  thunk at `0xd39730`, which tail-calls the parser at `0xd4d18c`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **4** via `0xD33CD8(ctx, 4)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then u8, u32, u8. The first u8 is bounds-tested against 7 (member index), the
  trailing u8 against 1 (`cmplwi 1` / `bgt` aborts) [READ 0xd4d27c-0xd4d2a0], so it is a
  two-valued field. The u32 is compared against the member slot's own first word before a
  state byte is written at member+0x11 [READ 0xd4d2b8-0xd4d2d8]. Payload 12 bytes; event 4.

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
    doc: "[INFERRED] member array index; > 7 aborts [ELF 0xd4d27c]."
  - id: character_id
    type: u4
    doc: |
      [INFERRED] compared against `member.character_id` of the addressed slot; a mismatch
      aborts the mutation [ELF 0xd4d2b8].
  - id: unknown_0b
    type: u1
    doc: |
      [UNKNOWN] must be 0 or 1 — `cmplwi 1` / `bgt` aborts the parse for anything larger
      [ELF 0xd4d29c]. Two-valued; which two states is unestablished.
