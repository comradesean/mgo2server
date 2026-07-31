meta:
  id: mgo2_cmd_49a2_s2c
  title: "MGO2 0x49a2 — server -> client: clan notification — member array refresh (u8 + eight 21-byte records)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x49a2` at `0xd38d3c` and branches to the
  thunk at `0xd39800`, which tail-calls the parser at `0xd4bbcc`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **17** via `0xD33CD8(ctx, 17)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a u8 into clan+0x004, then a **fixed loop of eight** (`cmpwi cr6,r27,7`) reading
  {u32, 16-byte block, u8} into the member array at clan+0x17C + 28*n, at member offsets
  +0x00, +0x04 and +0x11 [READ 0xd4bcb0-0xd4bd1c]. This is the same 28-byte member record the
  shared clan-record parser fills, minus its trailing u32. Payload **175 bytes**; event 17.

  Count source is the hardcoded loop bound. Eight records always, no count field.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

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
  - id: members
    type: member
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 0xd4bcb0-0xd4bd1c] Exactly eight records, 21 wire bytes each, 28-byte struct stride
      at clan+0x17C. Hardcoded loop bound.
types:
  member:
    doc: |
      21 wire bytes. The same slots as `member` in the shared clan record (see
      `mgo2_cmd_4911.ksy`) except that the trailing u32 at member+0x14 is not sent here and
      keeps whatever it held.
    seq:
      - id: character_id
        type: u4
        doc: "[INFERRED] member+0x00."
      - id: name
        type: str
        size: 16
        doc: "[INFERRED] member+0x04, 16-byte raw block. Width is [ELF 0xd4bce4]."
      - id: unknown_14
        type: u1
        doc: "[UNKNOWN] member+0x11, the per-member state byte the notifications rewrite."
