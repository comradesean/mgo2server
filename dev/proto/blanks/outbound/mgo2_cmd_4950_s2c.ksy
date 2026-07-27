meta:
  id: mgo2_cmd_4950_s2c
  title: "MGO2 0x4950 — server -> client: clan notification — full member refresh (u8 + eight u8s + 204-byte block)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4950` at `0xd38c90` and branches to the
  thunk at `0xd39770`, which tail-calls the parser at `0xd4c9ec`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **9** via `0xD33CD8(ctx, 9)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a u8, a **fixed loop of eight u8 reads** (same positional per-slot vector as
  `0x4943`), then the shared **204-byte block** via `0xD4364C` into clan+0x0B0
  [READ 0xd4cb08]. Post-processing mirrors `0x4943`: zero bytes clear a member slot, nonzero
  bytes write **member+0x15/+0x16** (DOC CORRECTION 2026-07-26 — earlier revisions said
  +0x11/+0x12; the ELF has `addi r31,r25,401` and `addi r29,r25,380` at 0xD4CB20/0xD4CB2C, so
  the slot base is r25+380 and r31 = slot+0x15, with `stb` at 0(r11) and 1(r11) — 0xD4CB94 and
  0xD4CB98. Nothing on the wire changes: this is post-processing of the client's own struct);
  additionally the slot whose `character_id` matches the local
  player is remembered and, if none matched, the whole packet is abandoned before the event is
  raised [READ 0xd4cbb0]. Payload **219 bytes**; event 9.

  The 204-byte block's layout is modelled once, canonically, in `mgo2_cmd_4313_s2c.ksy`
  (type `game_settings`) — the best-evidenced copy, because 0x4313's field names are backed by
  live capture of the `0x4310` push and the `0x4305` reply (OBSERVED.md). `mgo2_cmd_4909.ksy`
  carries a second, byte-accounting mirror (`block_204`). It is kept opaque here so the copies
  cannot drift. The reader `0xD4364C` has nine call sites: `0xD445A4` (0x4313), `0xD48440`
  (0x4905), `0xD48964` (0x4909), `0xD4B244` (0x4987), `0xD4CB08` (here), `0xD5006C`
  (0x4A24/0x4A31), `0xD51014` (0x4A00), `0xD5AF38` (0x4E10), `0xD5B78C` (0x43F1).

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
  - id: member_states
    type: u1
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 0xd4cad0-0xd4caf8] Eight bytes, positionally one per member slot, exactly as in
      0x4943. Hardcoded loop bound; no count field.
  - id: block_204
    size: 204
    doc: |
      [ELF 0xd4cb08] The shared 204-byte block read by 0xD4364C into clan+0x0B0. Layout in
      `mgo2_cmd_4313_s2c.ksy`, type `game_settings` (canonical); `mgo2_cmd_4909.ksy`
      type `block_204` is a second mirror of the same bytes.
