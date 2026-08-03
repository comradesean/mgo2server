meta:
  id: mgo2_cmd_4e20_s2c
  title: "MGO2 0x4e20 — Survival match pairing: the two participants and their win counts, 53 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  is in mgo2_cmd_4e00_c2s.ksy. `0x4E20` is a **server push** (no request slot) announcing a
  Survival match-up: two participants, each with an id, a 16-byte name and a win count.

  TIER. Post-launch content; no available client build exercises this command, so **everything
  here is tier 1 and cannot be raised to tier 2.** Not served in v1.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5B134**, which re-checks the id (`cmpwi r0,20000`) before reading anything.

  ## Destination: the Survival ladder record, and that is what names the fields

  The parser holds three objects at once, and it matters which is which:

  | reg | accessor | address | what it is |
  | --- | --- | --- | --- |
  | r25 | `0xD491F8(session)` | `session+0xD928` | the player's own **team record** |
  | r22 | `0xD4EA60(session)` | `session+0xDBD0` | the **Survival event record** (`0x4E10`'s) |
  | r27 | `0xD3F7B0(session)` | `session+0x11558` | the shared **Survival ladder record** |

  Every payload field lands on `r27` except the header and one byte, and `r27`'s layout is already
  mapped: mgo2_cmd_43b0_c2s.ksy calls it *"the Survival ladder"* and names
  `+0x0C`/`+0x10` participant A's / B's **win count**, `+0x14`/`+0x4C` their **ids** and
  `+0x18`/`+0x50` their **names**; mgo2_cmd_4a13_s2c.ksy independently confirms `+0x14`/`+0x18`/
  `+0x50` from its own renderer (lobby string 761, *"Next match: vs. %s"*). `0x4E20` writes all six
  of those slots and nothing else. That is a struct-offset bijection — same accessor `0xD3F7B0`,
  same six offsets, same six widths — so the names transfer wholesale.

  It also **fills the record's shared 5-field header from client state, not from the wire**
  (0xD5B318-0xD5B334): `R+0 <- team+664`, `R+4 <- team+604`, `R+8 <- team+608`, `R+9 <- team+609`.
  Those are the `lobby_id` / `lobby_subtype` / `lobby_subtype_sibling` slots
  mgo2_cmd_43f0_s2c.ksy maps. A server must not try to send them here; there is no field for them.

  ## No request slot, so it cannot stall anything

  The parser ends at `0xD33CD8(session, 36, *(u8*)(event record + 0x0D4))` — the fire-and-forget UI
  event helper, carrying the event record's **`phase`** byte (mgo2_cmd_4a24_s2c.ksy names +0x0D4
  `phase`, valid range 2..10). No `0xD32E08` call anywhere in the function. Not sending `0x4E20`
  cannot produce `FFFFFF60`; only the unanswered `0x4E00` can.

  Wire size: **53 bytes** = 4 + 2 + 4 + 1 + 4 + 16 + 1 + 4 + 16 + 1, confirmed against the read
  sequence 0xD5B208-0xD5B2FC.

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 / 0xD5CCD8 u4 (identical twins — see the CORRECTION below), 0xD5D018 fixed byte
  block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. An earlier revision
  added: "In each signed/unsigned pair the LOWER address is the signed accessor (write-side
  proof: 0xD5C95C uses `sraw`, 0xD5C9BC uses `srw`)." **That claim is SUPERSEDED — see the
  CORRECTION below.** Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare at every width): that rule is wrong,
  and it is wrong on the READ side at ALL widths, not just at u32. Each "signed/unsigned pair"
  is instruction-for-instruction identical — same bound check, same byte-assembly loop, same
  `extsb` on each byte, same store width:
    * u8:  0xD5CB54 == 0xD5CB8C  (bound `cmpwi 1023`, `lbzx`/`stb`, cursor += 1)
    * u16: 0xD5CBC4 == 0xD5CC14  (bound `cmpwi 1022`, two `lbzx`, `sth`,  cursor += 2)
    * u32: 0xD5CC64 == 0xD5CCD8  (bound `cmpwi 1020`, 4-iteration loop, `stw`, cursor += 4)
    * u64: 0xD5CD4C == 0xD5CDC0  (bound `cmpwi 1016`, 8-iteration loop, `std`, cursor += 8)
  So **no read primitive is a signed accessor at any width**, and "0xD5CBC4 s2" / "0xD5CC64 s4"
  are as unfounded as the u32 claim. Signedness comes from the CALLER — the value being
  reloaded with `lwa`, or being compared against known-negative error constants — never from
  the primitive's address.

  The write side does not rescue the rule either. There are **three** u32 write primitives, not
  a signed/unsigned pair: 0xD5C95C (`sraw`), 0xD5C9BC (`srw`) and 0xD5CA1C (`sraw`). The
  sraw/srw difference is inert because each iteration masks with `and r0,r4,r0` where r0 =
  `slw r7,r10` of 255, and then stores only the low byte with `stbx`: for shifts 16/8/0 the
  masked operand is non-negative in 32 bits so the two shifts agree outright, and for shift 24
  they differ only in bits above bit 7, which `stbx` discards. Identical bytes on the wire.

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

seq:
  - id: team_id
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `context_id`] Validated by 0xD49230 against **`team+0x00`**,
      where `team = 0xD491F8(session) = session+0xD928`; mismatch = -1018 and the packet is
      dropped. mgo2_cmd_491b_c2s.ksy already names `*(0xD491F8(session)+0x00)` **the team id**, so
      this is the receiving player's own team id, echoed back so the client can reject a push meant
      for a stale team.
  - id: team_seq
    type: u2
    doc: |
      [ELF 2026-08-02, renamed from `context_seq`] Validated by 0xD49230 against the u16 at
      **`team+0x29C`** (`lhz r0,668(r29)`, 0xD492D4); mismatch = -1018. A generation/sequence
      counter on the team record — [UNKNOWN] what increments it. Shared with 0x4d00, 0x4e22 and
      0x4e23, which use the identical 6-byte preamble.
  - id: event_id
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_06`; the old "read to a stack slot" was true and
      unhelpful] Read at 0xD5B210 and **required to equal the u32 at Survival event record +0x000**
      (0xD5B220-0xD5B230, `li r31,-1106`) — i.e. `0x4E10`'s `event_id`. A mismatch drops the packet
      silently with -1106.

      Same token, same check and same code as `0x4E12`'s payload and `0x4A24`'s `obj_id`, on the
      same slot of the same object. So a server pushing `0x4E20` must still be echoing whatever it
      put in the `0x4E10` that opened the list.
  - id: team_state
    type: u1
    doc: |
      [ELF 2026-08-02 -> team+0x04; NAMED 2026-08-03] Read at 0xD5B240 -> **`team+0x04`** —
      the team record, not the ladder record; the old note "-> obj+0x04" did not say which
      object and the two are 7048 bytes apart.

      **The team's event-participation state, and it is server-authoritative.** Eleven
      commands write it from the wire (0x4A27 0xD4EE0C, 0x4A02 0xD4F064, 0x4A01 0xD5069C,
      0x4A29 0xD50B94, 0x4A00 0xD50FB8, 0x4A22 0xD514D8, 0x4A20 0xD51B0C, and the four
      0x4E2x), 0x4960/0x4961's parsers store constants 4/5, and **no client-side writer
      exists** — chokepoint sweep over all 83 `bl 0xD491F8` sites plus all 24 direct
      `addi ...,-9944` materialisations, zero `stb ...,4(team)`. Notably the team-info
      commands (0x4911/0x4913/0x4987/0x49A1) do NOT write it, so it is specifically the
      event-participation state, not general team state.

      Seven readers pin the enum: **<= 2** -> the menu offers "Team Standby"; **> 2** ->
      "Cancel Entry" (0x8CBC48 — note it reads through a pointer CACHED at screen+108, a
      reader an accessor-only sweep cannot see); **5 -> the "Join Game" row exists at all**
      (0x8CBCA8, which also emits the extra icon); **9** -> the screen renders a counted
      roster instead of member names (0x8C3080/0x8C3180), two actions are refused outright
      (0x8D4A54, 0x8D7B6C), and 0x4918 roster rows must then carry member status 2 rather
      than 1 (0xD4D6D4). Values 4/6/7/8 are accepted and stored but distinguished by nothing.

      Bijection: `0x4E21`, `0x4E22` and `0x4E23` write this exact slot from the same position
      in their own payloads (0xD5A6D8, 0xD5A4C8, 0xD5A2A8), so it is one field shared by all
      four commands in the block — renamed in all four. This supersedes 2026-08-02's refusal
      to sweep displacement 4: the chokepoint method plus the cached-pointer channel is what
      a bare displacement sweep could not be. Tier-1 only; cannot reach tier 2 on this build.
  - id: participant_a_id
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_0b`] Read at 0xD5B25C -> Survival ladder record
      **+0x14**. **Participant A's (team's) id.**

      Struct-offset bijection with mgo2_cmd_43b0_c2s.ksy's `rec+0x14` and mgo2_cmd_4a13_s2c.ksy's
      `group_a.team_id`: same accessor `0xD3F7B0`, same offset, same width. Those files name it
      from consumers this packet does not have — 0x8CE0AC/0x8CE1B0 compute
      `n = (rec[0x14] == myId) ? rec[0x0C] : rec[0x10]`, which is what pairs this id with
      `participant_a_wins` below, and 0x8CDFC0 compares it against the local player's own team id.
      Same id space as `0x4E11`'s `entrant_id`.
  - id: participant_a_name
    size: 16
    type: str
    encoding: ASCII
    doc: |
      [ELF 2026-08-02, renamed from `name_a`] 16-byte raw read at 0xD5B27C -> Survival ladder record
      **+0x18**. **Participant A's team name.**

      Bijection with mgo2_cmd_4a13_s2c.ksy `group_a.team_name`, which evidences the string role
      rather than inferring it from width: 0x8CDFF8/0x8CE01C hand rec+0x18 to the string copier
      0xAF70F0 and then to lobby string 761, *"Next match: vs. %s"*.
  - id: participant_a_wins
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_1f`] Read at 0xD5B29C as a **u8** and stored **widened
      to u32** at 0xD5B2BC (`lbz r0,112(r1)` / `stw r0,12(r27)`) -> Survival ladder record
      **+0x0C**. **Participant A's win count in the Survival series.**

      Bijection with mgo2_cmd_43b0_c2s.ksy's `side_a_win_count` (`rec+0x0C`), which is named by its
      consumer, not by position: 0x8CE0AC/0x8CE1B0 select between +0x0C and +0x10 using the
      `+0x14`/`+0x4C` id pair and render the result into lobby strings 762 (*"Match #%d has
      ended…"*, as `n+1`) and 763 (*"…winning streak ends at %d wins."*). The same pairing rule is
      what makes this **A's** counter specifically.

      Source-width note, flagged not changed: 0x4A12 fills the same slot from a u16
      (mgo2_cmd_43b0_c2s.ksy records this) and this packet fills it from a u8. The wire field here
      genuinely is one byte (`0xD5CB8C`), so nothing moves — but a server cannot express a streak
      above 255 through `0x4E20`, and `0x4E11.win_streak` has the same ceiling.
  - id: participant_b_id
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_20`] Read at 0xD5B2C0 -> Survival ladder record
      **+0x4C**. **Participant B's (team's) id.** Bijection with mgo2_cmd_43b0_c2s.ksy `rec+0x4C`
      and mgo2_cmd_4a13_s2c.ksy `group_b.team_id`; the "(u4, str16, u1) pattern repeating twice
      suggests two parallel entities" guess in the old doc is now settled — they are the two sides
      of one Survival match, and the screen's own header string is lobby 810,
      *"DEFENDER / CHALLENGER"*.
  - id: participant_b_name
    size: 16
    type: str
    encoding: ASCII
    doc: |
      [ELF 2026-08-02, renamed from `name_b`] 16-byte raw read at 0xD5B2E0 -> Survival ladder record
      **+0x50**. **Participant B's team name.** Bijection with mgo2_cmd_4a13_s2c.ksy
      `group_b.team_name` — the renderer prints B's name when A's id is the viewer's own team,
      which is how "vs. %s" always names the opponent.
  - id: participant_b_wins
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_34`] Last byte. Read at 0xD5B2F8 as a u8 and stored
      widened to u32 at 0xD5B314 (`stw r0,16(r27)`) -> Survival ladder record **+0x10**.
      **Participant B's win count**, by the same consumer-side pairing that names
      `participant_a_wins`: mgo2_cmd_43b0_c2s.ksy `side_b_win_count`. Same u8 ceiling.
