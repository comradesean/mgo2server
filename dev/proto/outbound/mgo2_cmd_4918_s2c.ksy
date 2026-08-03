meta:
  id: mgo2_cmd_4918_s2c
  title: "MGO2 0x4918 — server -> client: team notification — member joined/updated (28-byte payload)"
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

  This is an **unsolicited team notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **1** via `0xD33CD8(ctx, 1)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, team, reader)`:
  a u32 compared against the client's cached team id (`team+0x000`) and a u16 compared against
  `team+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then u8, u32, a 16-byte raw block and u8, assembled into a 28-byte stack scratch
  that is memset first [READ 0xd4d5f0]. The first u8 is bounds-tested against 7 before use as
  a member index; the 16-byte block is passed to `0xDCC7F8` (a string-length helper) and the
  packet is **dropped if the result is 16**, i.e. the block must be NUL-terminated within its
  16 bytes [READ 0xd4d6c4]. Payload 28 bytes; event 1.

  **RELABELLED 2026-08-01 — the header pair is the TEAM id and the TEAM record serial, not a
  clan's.** The object `0xD49230` validates against is `session + 0xD928`, the 680-byte team
  record: this parser re-bases it with `addis` +1 / `addi ...,-9944` at [ELF 0xd4d5c0] and passes
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
  - id: member_slot
    type: u1
    doc: "[INFERRED] member array index; > 7 aborts the mutation [ELF 0xd4d69c-0xd4d6a4]."
  - id: character_id
    type: u4
    doc: |
      [INFERRED] the 28-byte scratch's first word, matching `member.character_id` of the
      team-record member array. Named from position, not from a label.
  - id: name
    type: str
    size: 16
    doc: |
      [ELF 0xd4d664] 16-byte raw block. **Must be NUL-terminated inside 16 bytes** — the
      parser measures it and drops the packet if the length comes back 16 [READ 0xd4d6c4].
      That check is what makes "text" here [ELF] rather than [INFERRED].
  - id: member_state
    type: u1
    doc: |
      [ELF 2026-08-03 — named by destination and renderer; was `unknown_1b`, and the old
      "scratch+0x19" was wrong] Last byte. The read target is `addi r4,r1,137` (0xd4d678)
      against the scratch base r1+116, i.e. **scratch+0x15**; the 28-byte block copy
      (lswi/stswi at 0xd4d71c-0xd4d720) lands it at **member+0x15** of the roster row
      (team+380+28*slot) — `member_state`, the byte the member-list painter renders as "OK"
      when 2 and "NG" otherwise (0x8C0EDC, dev element name `MEMBER_STATE`/`st_member_state`),
      that selects lobby string 693 "Accept Entry" (0x8C04C0/0x8C2794), and that the 0x4930
      toggle flips (0x8C28DC sends 0 if own byte is 2, else 1).

      The old 0xd4d6dc note conflated two operands: the `cmpwi 9` is on **team_state**
      (`lbz r0,4(r27)` at 0xd4d6d4), and only the `cmpwi 2` / `cmpwi 1` are on this byte —
      the gate is "if team_state == 9 this byte must be 2, else it must be 1", otherwise
      -1036. Two further gates this file omitted: `character_id != 0` (0xd4d6a8) and
      `name[0] != 0` (0xd4d6b4). Side effects of the install: member+0x16 is set to 1
      (`stb r0,138(r1)`), and because the scratch is memset and block-copied, member+0x14,
      +0x17 and the u32 at +0x18 are zeroed. Tier-1 only; no client build exercises this.
