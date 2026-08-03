meta:
  id: mgo2_cmd_4950_s2c
  title: "MGO2 0x4950 — server -> client: team notification — full member refresh (u8 + eight u8s + 204-byte block)"
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

  This is an **unsolicited team notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **9** via `0xD33CD8(ctx, 9)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, team, reader)`:
  a u32 compared against the client's cached team id (`team+0x000`) and a u16 compared against
  `team+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a u8, a **fixed loop of eight u8 reads** (same positional per-slot vector as
  `0x4943`), then the shared **204-byte block** via `0xD4364C` into team+0x0B0
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

  **RELABELLED 2026-08-01 — the header pair is the TEAM id and the TEAM record serial, not a
  clan's.** The object `0xD49230` validates against is `session + 0xD928`, the 680-byte team
  record: this parser re-bases it with `addis` +1 / `addi ...,-9944` at [ELF 0xd4ca68] and passes
  that pointer as the helper's second argument, and the family's missing-record gate answers
  `-1007` -> dialog 5170 *"You have already left the team."* A **clan** is a separate object the
  team merely points at, via `team+0x280` (clan id), `team+0x284` (clan name) and flag bit
  `0x40` in `team+0x094`; genuine clan operations answer in the disjoint `-12xx` band rather
  than this record's `-10xx`. Where the word "clan" still appears below it means that separate
  object and is deliberate.

  **Tier note.** No available client build exercises the `0x49xx` family, so **nothing in this
  file is backed by a capture.** Every claim is tier 1 (read from `MGO2.elf`) or is explicitly
  marked [INFERRED] or [UNKNOWN]. Do not read any of it as tier 2.

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
  - id: team_id
    type: u4
    doc: |
      [ELF 0xd49274] Must equal the client's cached team id (`team+0x000`) or the packet is
      dropped with `-1018`.
  - id: team_serial
    type: u2
    doc: |
      [ELF 0xd492b0] Must equal the u16 at `team+0x29C` — the serial the team-record replies
      set and `0x49a8` updates. Mismatch -> `-1018`, packet dropped.
  - id: team_state
    type: u1
    doc: |
      [ELF 2026-08-03 — named by destination; was `unknown_06`] Read straight into
      team+0x004 (0xd4cab0): `team_state`, the team's event-participation state. Enum and
      enumerations: `mgo2_cmd_4e20_s2c.ksy`. Tier-1 only.
  - id: member_states
    type: u1
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 0xd4cad0-0xd4caf8] Eight bytes, positionally one per member slot, exactly as in
      0x4943. Hardcoded loop bound; no count field. [2026-08-03] Corrected offsets: nonzero
      -> **member+0x15** (`member_state`, `stb` at 0xd4cb94) AND member+0x16 = 1
      (`stb r0,1(r11)` at 0xd4cb98, r11 = team+401+28*i) — this parser, unlike 0x4943, does
      write the second byte. Tail: event 9 with the local member's +0x15 (0xd4cc2c).
  - id: block_204
    size: 204
    doc: |
      [ELF 0xd4cb08] The shared 204-byte block read by 0xD4364C into team+0x0B0. Layout in
      `mgo2_cmd_4313_s2c.ksy`, type `game_settings` (canonical); `mgo2_cmd_4909.ksy`
      type `block_204` is a second mirror of the same bytes.
