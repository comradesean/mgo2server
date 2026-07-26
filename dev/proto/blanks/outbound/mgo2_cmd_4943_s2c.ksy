meta:
  id: mgo2_cmd_4943_s2c
  title: "MGO2 0x4943 — server -> client: clan notification carrying u8 + eight u8s"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4943` at `0xd38c88` and branches to the
  thunk at `0xd397e0`, which tail-calls the parser at `0xd4bf40`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **16** via `0xD33CD8(ctx, 16)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a u8 and a **fixed loop of eight u8 reads** into a stack array
  [READ 0xd4c020-0xd4c050] — the loop terminates on the destination pointer reaching
  `stack+8`, so it is exactly eight, not count-driven. The eight bytes are then walked against
  the member array: a zero byte zeroes that member's 28-byte slot, a nonzero byte is stored at
  member+0x11 with 1 at member+0x12 [READ 0xd4c0cc-0xd4c0d8]. So it is a **per-member-slot
  state vector, one byte per slot, positional**. Payload 15 bytes; event 16.

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
  - id: unknown_06
    type: u1
    doc: "[UNKNOWN] -> clan+0x004 (`unknown_0a` of the shared clan record)."
  - id: member_states
    type: u1
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 0xd4c024-0xd4c050] Eight bytes, positionally one per member slot. 0 clears the
      slot; nonzero is written to member+0x11 (with 1 at member+0x12). Loop bound is
      hardcoded eight — there is no count field.
