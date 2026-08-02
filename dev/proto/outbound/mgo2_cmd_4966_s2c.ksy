meta:
  id: mgo2_cmd_4966_s2c
  title: "MGO2 0x4966 — server -> client: team notification carrying one 4-byte word"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4966` at `0xd38cc8` and branches to the
  thunk at `0xd397c0`, which tail-calls the parser at `0xd4c388`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited team notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **14** via `0xD33CD8(ctx, 14)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, team, reader)`:
  a u32 compared against the client's cached team id (`team+0x000`) and a u16 compared against
  `team+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a single 4-byte read. Post-processing bounds-tests a member index against 7 and
  **zeroes** the byte at member+0x12 [READ 0xd4c450-0xd4c47c]. The mirror of `0x4965`'s
  set. Payload 10 bytes; event 14.

  **RELABELLED 2026-08-01 — the header pair is the TEAM id and the TEAM record serial, not a
  clan's.** The object `0xD49230` validates against is `session + 0xD928`, the 680-byte team
  record: this parser re-bases it with `addis` +1 / `addi ...,-9944` at [ELF 0xd4c3c4] and passes
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
  - id: character_id
    type: u4
    doc: "[INFERRED] used to locate a member slot; member+0x12 is cleared."
