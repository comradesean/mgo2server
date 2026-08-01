meta:
  id: mgo2_cmd_4987_s2c
  title: "MGO2 0x4987 — server -> client: team record + 204-byte block (shared 0xD4AF34 layout)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4987` at `0xd38cfc` and branches to the
  thunk at `0xd396f0`, which tail-calls the parser at `0xd4d770`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This id is one of **six** routed into the shared team-record parser `0xD4AF34`
  (`0x4911`, `0x4913`, `0x4985`, `0x4987`, `0x49A1`, `0x49B1`; compare tree at
  `0xd4af98-0xd4afd8`). All six carry the **same 420-byte payload**, except `0x4987`, which
  inserts a 204-byte sub-block (see that file). The per-id wrapper only differs in the
  request-status slot it completes.

  Structure of the shared parser: verify the id, 4-byte result; **if the result is nonzero
  every field below is skipped** and only the request slot is completed [READ 0xd4b084].
  On success the 680-byte team record is filled. For `0x4985`/`0x49B1` the record is first
  memset to 680 bytes and the leading id is cross-checked against a context value
  [READ 0xd4b0b8-0xd4b0e0]; for the other four the existing record is reset via `0xD49368` /
  `0xD4EC14` and reused. The wire layout is identical either way.

  The 8-entry member array is a **fixed loop of eight** (`cmpwi cr6,r26,7`), not
  count-driven [READ 0xd4b254-0xd4b2e4]: 25 wire bytes per member, 28-byte stride in the
  struct. Record the distinction — a leading count is not present.

  Wrapper `0xd4d770`: on a `-1` return from the shared parser it does nothing; otherwise it
  completes request-status slot **72** with the result via `0xD32E08`/`0xD32E70`.

  **`0x4987` is the only variant with an extra field.** After the flag byte the parser
  branches on the id and reads a 204-byte block via `0xD4364C` into team+0x0B0
  [READ 0xd4b230-0xd4b244], making its payload **624 bytes** instead of 420. It is also
  the only one with post-processing: on success it copies team+0x25C/0x260/0x261 into a
  roster object and, if a game entry matching team+0x25C exists, copies 64 bytes of text
  into it [READ 0xd4b46c-0xd4b51c]. The 204-byte block is the same one 0x4909 and 0x4950
  read; see `mgo2_cmd_4909.ksy` for its field-by-field layout, which is not duplicated
  here.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.

  **THIS OBJECT IS A TEAM, NOT A CLAN** (settled 2026-08-01; the files previously said "clan"
  throughout). Three independent lines: (a) one parser fills it for all six ids and its own gate
  `0xD4908C` fails with `-1007` -> dialog 5170 *"You have already left the team."*; (b) the flag
  bit at `+0x094` selects menu label **689 "Set Clan Affiliation"** vs **690 "Cancel Clan
  Affiliation"** (`0x8BFF38`) — a team *references* a clan through one bit, so the two cannot be
  the same object; (c) the error band here is `-10xx`, disjoint from the `-12xx` band the real
  clan operations use. A clan is a separate record reached through `+0x280`/`+0x284`.

  **TWO DESTINATIONS, ONE LAYOUT — corrected 2026-08-01.** The id compare tree at
  `0xD4AFA4`-`0xD4AFD8` does not merely choose whether to memset; it chooses **which team record
  is filled**, and the older wording in these files ("the allocating variant") obscured that.

  - `0x4911`, `0x4913`, `0x49A1`, `0x4987` -> `0xD4AFF8`: `addis r9,r25,1` / `addi r31,r9,-9944`
    = **session + 0xD928**, the player's OWN team. Reached by getter `0xD491F8` (83 call sites,
    all over the team screens).
  - `0x4985`, `0x49B1` -> `0xD4AFDC`: `lwz r9,6404(r9)` / `addis r9,r9,2` / `addi r31,r9,-23144`
    = **[session + 0x11904] + 0x1A598**, the team being VIEWED. Reached by getter `0xD491C8`
    (15 call sites, all in the `0x8C6C`-`0x8C9F` browse screens). These two also memset the 680
    bytes first and cross-check the leading id against `[session+0x11904] + 0x26CFC`
    (`0xD4B0B8`-`0xD4B0E0`); the other four reset the existing record through `0xD49368` /
    `0xD4EC14` and reuse it.

  The wire layout is identical either way. Wrapper request-status slots, one per id and the only
  other per-id difference: **0x4911 -> 60, 0x4985 -> 63, 0x4913 -> 64, 0x4987 -> 72 (or 86 when
  `tournament_id` is non-zero), 0x49A1 -> 73, 0x49B1 -> 74** (0xD4B560-0xD4B78C, 0xD4D770).

  **STRUCT MAP** (680 bytes = 0x2A8; `+` offsets are into the struct, not the wire):

  ```
  +0x000 u32       team id (the gate word 0xD4908C tests)
  +0x004 u8        team state / phase
  +0x005 char[16]  team name        (NUL at +0x015)
  +0x016 char[128] comment          (NUL at +0x096 — see the overrun note)
  +0x094 u32       flag word, three bits expanded from one wire byte
  +0x097 u8        hard zero, never from the wire (0xD4B1D4 stores the read's own 0 return)
  +0x0B0 204 B     game-settings block — parsed for 0x4987 ONLY
  +0x17C 8 x 28 B  roster, slot 0 = leader
  +0x25C u32       lobby id
  +0x260 u8        lobby subtype
  +0x261 u8        rule id
  +0x262 u16       (no reader)
  +0x264 u16       (no reader)
  +0x268 u32       game id
  +0x26C char[16]  game name
  +0x280 u32       affiliated clan id
  +0x284 char[16]  affiliated clan name
  +0x296 u16       (no reader)
  +0x298 u32       tournament / entry id
  +0x29C u16       record serial (read SECOND on the wire, stored far down the struct)
  +0x2A0 u32       (no reader)
  +0x2A4 u32       entry fee in Metal Gear Points
  ```

  **THE COMMENT/FLAG OVERRUN, CHECKED FIRST (2026-08-01).** This has exactly the shape of the
  live `0x4349` hazard, so it was the first thing tested. The comment is 128 bytes at `+0x016`,
  so it occupies `+0x016..+0x095`, and `0xD5D018` then writes a NUL at `dest+size` = `+0x096`
  (`stb r0,0(r9)` at `0xD5D07C`, `r9 = r4 + r5`). The flag word is a big-endian `u32` at
  `+0x094`, i.e. bytes `+0x094..+0x097`. **Three of its four bytes are inside the comment.**
  The overrun is real but INERT, for three reasons, each read from the binary:

  - every flag bit the parser sets (`0x80`, `0x40`, `0x10`) lives in the **least-significant
    byte, `+0x097`**, which the comment cannot reach — it stops at `+0x096`;
  - `+0x097` is explicitly stored as zero at `0xD4B1D4`, *before* the ORs;
  - the flag word is updated read-modify-write (`lwz r0,148(r9)` / `ori` / `stw r0,148(r9)` at
    `0xD4B1E8`-`0xD4B22C`), so the comment tail in `+0x094..+0x096` survives the flag write too —
    the corruption runs in neither direction.

  The residual hazard is a reader that treats the word as a whole. There is none: every reader
  masks a single bit with `rldicl.` (`0x8BFF3C`, `0x8C1408`, `0x8C200C`, `0x8C20C4`, `0x8C3A04`,
  `0x8C3F2C`, `0x8C4EDC`, `0x8C57D0`, `0x8C99FC`, `0x8C9F08`, `0x8CAEC8`, `0x8CB078`, `0x8CE458`,
  `0x8CE608`, `0x8CE9C4`, `0x8CEB70`, `0x8CFE04`), and none tests a bit above `0x80` or compares
  the word. Swept band `0x880000`-`0xD80000` for `lwz/stw ...,148(rX)`; the same sweep finds the
  known-live readers of `+0x2A4` and `+0x298`, so it is not a sweep that misses things.

  **EVIDENCE TIER — READ THIS BEFORE CITING ANY FIELD BELOW.** Every name here is **tier 1**
  (read from `MGO2.elf`) and **cannot reach tier 2**: no available client build exercises the
  `0x49xx` team family, so nothing in this file is confirmed against a live client and no capture
  backs it. The family is post-launch content (Tournament / Survival) and is **not served in v1**
  — mapping it is in scope, implementing it is not. Our server has no handler for any of the six
  ids (checked 2026-08-01), so no value we currently put on the wire is affected by this mapping.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xd4b074] [CONFIDENCE: high] 0 = success; nonzero ends the parse here (4-byte
      payload). s4 is on CALLER evidence — the thunk reloads the out-param with `lwa` before
      publishing it to 0xD32E70 (e.g. 0xD4B5A8) — not on the read primitive, which is
      byte-identical to 0xD5CCD8 and is not a signed accessor.
  - id: team_id
    type: u4
    doc: |
      [ELF 0xd4b0a8 / 0xd4b128] [CONFIDENCE: high] Stored at team+0x000. The client's identity
      for the team: `0xD4908C` returns -1 when it is zero (error -1007 -> dialog 5170 *"You have
      already left the team."*), and every team-event notification's header word is compared
      against it (helper `0xD49230`). For 0x4985/0x49b1 it is additionally checked against a
      context value and a mismatch aborts the whole reply.
  - id: team_serial
    type: u2
    doc: |
      [ELF 0xd4b148] [CONFIDENCE: medium — role clear, semantics not] Stored at team+0x29C —
      read SECOND on the wire but living far down the struct. `0xD492D4` loads it with `lhz`
      and compares it against the u16 in every team-notification header, and `0x49a8` is the
      only other writer (`sth r0,668(r28)` at 0xD4BF10). It behaves as a record version that
      notifications must quote; the numbering rule is [UNKNOWN].
  - id: team_state
    type: u1
    doc: |
      [ELF 0xd4b164 -> team+0x004] [CONFIDENCE: medium] A phase byte for the team, set by the
      server and pushed by two notifications. Readers, all with the value in hand:

      - `0x8CBC48`: `<= 2` labels the standby menu item **739 "Cancel Entry"**, `> 2` labels it
        **740 "Leave Team"** — so 0-2 is "entry can still be withdrawn" and 3+ is not.
      - `0x8CBCA8`: `== 5` selects a different standby panel.
      - `0x8C3080` / `0x8C3180` / `0x8D4A54`: `== 9` makes the join event render **string 731
        "Number of Players Currently Joined: %d / %d"** over a count of non-zero roster slots,
        instead of the per-member **718 "%s has joined the team."** — i.e. 9 is the automatic
        team-formation screen (strings 681-686 "Auto Join Team", 716 "Forming a team...").

      Writers other than this parser: `0x4961` stores **4** (`0xD4C7DC`) and `0x4960` stores
      **5** (`0xD4C988`). No other store to team+0x004 exists in the 88 functions that can hold
      a team pointer. The full enum is [UNKNOWN] — only 4, 5 and 9 and the `<=2` split are
      pinned.
  - id: team_name
    type: str
    size: 16
    doc: |
      [ELF 0xd4b184 width; INFERRED role] [CONFIDENCE: high] team+0x005, 16-byte raw block,
      NUL at +0x015. The Create Team screen's own field label is **string 664/672 "Team Name"**
      and the rule text is **668** *"Enter a team name. The following symbols can also be
      used: ..."*.
  - id: comment
    type: str
    size: 128
    doc: |
      [ELF 0xd4b1a4 width; INFERRED role] [CONFIDENCE: high] team+0x016, 128 bytes, NUL at
      +0x096. The Create Team screen labels it **string 666/674 "Comment"**, described by
      **670** *"This comment is displayed when players select this team."*, with **656 "No
      comment."** as the empty placeholder. Same width as the player comment in 0x4221.
      **Its last two bytes and its terminator sit inside the flag word at +0x094** — see the
      overrun analysis in the file header; the result is inert, not a bug.
  - id: flags
    type: u1
    doc: |
      [ELF 0xd4b1b4-0xd4b22c] [CONFIDENCE: high for bits 0 and 1, none for bit 2] Read as a
      1-byte raw block into a stack temp, then expanded into the u32 at team+0x094:

      | wire bit | test | struct bit | meaning |
      | --- | --- | --- | --- |
      | 0 | `clrldi. r9,r0,63` @0xD4B1E0 | `0x80` | **Password Lock** — string 654/665. At `0x8C99FC` and `0x8C9F08` (the browse-team screens, viewed-team getter `0xD491C8`) a set bit makes the join call `0xD4AA44` with a password buffer; clear passes 0. |
      | 1 | `rldicl. r9,r0,63,63` @0xD4B1FC | `0x40` | **Clan affiliation.** `0x8BFF3C` picks menu label **690 "Cancel Clan Affiliation"** when set, **689 "Set Clan Affiliation"** when clear; `0x8C2008` picks confirm text **702** *"Are you sure you want to cancel the team's clan affiliation?"* vs **701** *"This will affiliate the team with the team leader's clan..."*; `0x8C20C4` inverts it (`xori 64`) and feeds `0xD4DCF4`. Sixteen further sites gate the clan name/id display on it. |
      | 2 | `rldicl. r9,r0,62,63` @0xD4B218 | `0x10` | **[UNKNOWN] and unread.** No reader anywhere tests `0x10`: swept `0x880000`-`0xD80000` for every `lwz/stw ...,148(rX)` and every hit in the team screens masks bit 6 or bit 7 only. Control: the same sweep does find both live masks above. |

      **Bits 3-7 of the wire byte are read and discarded** — the parser expands exactly three.
      A zero byte is also unconditionally stored at team+0x097 (0xD4B1D4); it is not a wire
      field, and it is what keeps the comment overrun harmless.
  - id: game_settings
    size: 204
    doc: |
      [ELF 0xd4b238] [CONFIDENCE: high] **Present for 0x4987 only** — the parser branches on
      `cmpwi r24,0x4987` at 0xD4B230. Read by the shared reader 0xD4364C into team+0x0B0, which
      makes this id's payload 624 bytes instead of 420.

      This is the team's **game-settings / rule-rotation block**, and the identification is a
      struct-offset bijection rather than a resemblance: `0xD49448` builds the 968-byte
      host-settings object by copying **204 bytes from team+0x0B0 to object+752**, next to
      `object+0 = team+0x268` and `object+168 = team+0x260`; in the 0x4310 sender the same
      object's `src+752` is the rule array and `src+168` is `lobby_subtype`
      (`mgo2_cmd_4310_c2s.ksy`). Its internal layout is modelled canonically in
      `mgo2_cmd_4313_s2c.ksy`, type `game_settings`, and mirrored in `mgo2_cmd_4909.ksy`; kept
      opaque here so the copies cannot drift. 0xD4364C has nine call sites, listed in
      `mgo2_cmd_4909.ksy`.
  - id: members
    type: member
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 0xd4b254-0xd4b2e4] [CONFIDENCE: high] Exactly eight roster entries; the loop bound is
      hardcoded (`cmpwi cr6,r26,7`) and there is no count on the wire. 25 wire bytes each,
      28-byte struct stride starting at team+0x17C. **Slot 0 is the LEADER**: `0xD4DC18`
      compares slot 0's id against the local character record and fails -1014 when it does not
      match, which is what gates the leader-only menu (**string 732/734 "LEADER OPTIONS"** vs
      **733 "MEMBER OPTIONS"**).
  - id: lobby_id
    type: u4
    doc: |
      [ELF 0xd4b2f4 -> team+0x25C] [CONFIDENCE: high] The id of the lobby the team is registered
      in. Proof is a lookup, not a resemblance: on success 0x4987 copies this word to
      `rosterObj+7160` (0xD4B498) and then walks the **hub list** with `0xD48D10`/`0xD49040`
      — `ctx+0xB790`, 120-byte stride, entries at `+8`, count at `+4`, which is exactly the
      list `LOBBIES.md` documents and `0x4902` fills (0xD480CC) — matching `entry+0` against it
      and copying the 64-byte text at `entry+27` outward (0xD4B4F8-0xD4B51C). `entry+0` is the
      lobby id and `entry+27` the lobby's own text. `0xD511B8` and `0xD5B320` repeat the same
      triple. Also written by the 0x4922 notification (0xD4D10C).
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF 0xd4b310 -> team+0x260] [CONFIDENCE: high] The lobby subtype the team is entered in
      — Tournament / Survival / Official Tournament in `LOBBIES.md`'s table.

      **Cross-packet bijection.** The 0x4310 *host game* sender reads this byte and stores it at
      `src+168` (`lbz r0,608(r3)` / `stb r0,168(r29)`, 0xD44804), but only after `0xD4908C` says
      the player is in a team. `src+168` is serialised as 0x4310 wire `0x0A2`, which
      `mgo2_cmd_4310_c2s.ksy` names `lobby_subtype`. Same struct byte, two commands. 0x4316
      (0xD43C94) and 0x4320 (0xD452D0) copy it the same way, and `0xD49470` puts it at
      `object+168` of the 968-byte host-settings object.

      Range: the 0x4967 notification computes `subtype - 3` and rejects anything above 6
      (`0xD4C254`, error **-1018**), so the client accepts **3..9** here. That is a superset of
      the three subtypes `LOBBIES.md` can name; the arms pair up 3/4, 5/6, 7/8 with 9 alone, and
      what distinguishes the pairs is [UNKNOWN].
  - id: rule
    type: u1
    doc: |
      [ELF 0xd4b32c -> team+0x261] [CONFIDENCE: high] The game rule (Deathmatch, Team
      Deathmatch, ... Coop) — **the client says so in its own words**. Five readers
      (`0x8C1194`, `0x8C4208`, `0x8C4DA0`, `0x8CE908`, `0x8CFAE8`) all do
      `lbz r3,609(r3)` / `rlwinm r3,r3,1,23,30` / `bl 0x8E0BF0`, i.e. fetch string id
      **2 x rule** from resource group **0x654515** — the rule-name group whose base
      `mgo2_cmd_4682_s2c.ksy` locked at 342. Ids 0-17 there are nine adjacent identical pairs:
      0/1 Deathmatch, 2/3 Team Deathmatch, 4/5 Rescue Mission, 6/7 Capture Mission, 8/9 Sneaking
      Mission, 10/11 Base Mission, 12/13 BOMB Mission, 14/15 Team Sneaking, 16/17 Coop Mission.
      So rule 0 = Deathmatch ... rule 8 = Coop — the same enum as 0x4310's rotation `rule`.
      Also written by 0x4922 (0xD4D110) and travels with lobby_id/lobby_subtype in five
      request builders (0xD4BDA4, 0xD4CBE8, 0xD4D874, 0xD512A8, 0xD5B320) as `{+4, +8, +9}`.
  - id: unknown_262
    type: u2
    doc: |
      [ELF 0xd4b348 -> team+0x262] [UNKNOWN] [CONFIDENCE: parsed-and-unread is high; meaning is
      nil] **Stated negative: nothing reads it.** Swept two ways. (1) All 88 functions that can
      hold a team pointer — every site computing `session+0xD928` or `[session+0x11904]+0x1A598`
      plus every caller of the getters `0xD491F8`/`0xD491C8` — scanned for displacement 610:
      one hit, the parser's own write. (2) The whole text band `0x880000`-`0xD80000` (lower edge
      below the team screens at `0x8C0xxx`, upper edge above the networking module, which ends
      near `0xD64000`) for `lwz/lbz/lhz/stw/stb/sth ...,610(rX)`: 15 hits, all on unrelated
      objects in `0x00BE`-`0x00C0`. Control: the identical sweep for `+0x2A4` returns its four
      real readers and for `+0x298` its six, so the method does find readers when they exist.
  - id: unknown_264
    type: u2
    doc: |
      [ELF 0xd4b364 -> team+0x264] [UNKNOWN] [CONFIDENCE: parsed-and-unread is high; meaning is
      nil] **Stated negative: nothing reads it.** Same two sweeps as `unknown_262`, same edges,
      same control. Displacement 612 has 16 hits in the band, none on a team base, and one hit
      in the team-pointer functions — the parser's own write.
  - id: game_id
    type: u4
    doc: |
      [ELF 0xd4b380 -> team+0x268] [CONFIDENCE: medium-high] The id of the game the team is
      deployed to; **0 means "none"**. `0xD49448` refuses to build the 968-byte host-settings
      object when it is zero and otherwise stores it at `object+0`, alongside the subtype at
      `object+168` and the 204-byte settings at `object+752`. `0x8D028C` passes it as the second
      argument of `0xD4134C`, which sends **0x4312** (`li r4,0x4312` at 0xD413BC) — the join
      path. `0x8D0348` latches it into the screen at `+1088`, and 0x4961 forwards it as the
      event argument of `0xD33CD8(session, 11, gameId)` (0xD4C844). The list row label is
      **string 647 "Deployed"**.
  - id: game_name
    type: str
    size: 16
    doc: |
      [ELF 0xd4b3a0 width -> team+0x26C] [CONFIDENCE: medium-high] The name of that game. The
      0x4310 host-game sender, immediately after a successful send and only when
      `0xD4908C` says the player is in a team, memsets 17 bytes at **team+620** and copies the
      **same 16-byte buffer it just put on the wire as 0x4310's `name`** into it
      (`r24`, 0xD44888 and 0xD44CC4). So the client mirrors the hosted game's name here.
      No reader was traced — the sweep for displacement 620 over `0x880000`-`0xD80000` finds
      only this write on a team base — so the field is written locally and echoed by the server;
      what renders it is [UNKNOWN].
  - id: clan_id
    type: u4
    doc: |
      [ELF 0xd4b3bc -> team+0x280] [CONFIDENCE: high] The id of the clan the team is affiliated
      with, **0 when unaffiliated**. Nine screens run the same two-step: `lwz r0,640(r3)`,
      `cmpwi 0` and then the `0x40` flag bit, and only if both pass do they render the name at
      `+0x284` (e.g. 0x8C13FC-0x8C1450). `0x8C1604` compares it against `charObj+6816`, the
      viewer's own clan id, to choose between two different labels. Rewritten together with
      `clan_name` by the 0x4925 notification, and copied between records at 0x8C39C4/0x8CE418.
  - id: clan_name
    type: str
    size: 16
    doc: |
      [ELF 0xd4b3dc width -> team+0x284] [CONFIDENCE: high] That clan's name. `0x8C143C`-
      `0x8C1450` memsets a 33-byte display buffer and copies from **team+644** into it once
      `clan_id` is non-zero and the `0x40` bit is set. The 0x4925 notification rewrites the
      `{u32, char[16]}` pair on its own, so the two travel together.
  - id: unknown_296
    type: u2
    doc: |
      [ELF 0xd4b3f8 -> team+0x296] [UNKNOWN] [CONFIDENCE: parsed-and-unread is high; meaning is
      nil] **Stated negative: nothing reads it.** Note it is preceded by a 2-byte gap — the
      string at `+0x284` ends at `+0x293` and its NUL lands at `+0x294`. Same two sweeps as
      `unknown_262`: displacement 662 gives one hit in the team-pointer functions (this write)
      and 8 in the band, all on unrelated objects in `0x0088`-`0x0095`. Same control.
  - id: tournament_id
    type: u4
    doc: |
      [ELF 0xd4b40c -> team+0x298] [CONFIDENCE: medium] The id of the tournament / Survival
      entry the team is in, **0 when there is none**. Three uses:

      - 0x4987's wrapper (`0xD4D804`) branches on it: non-zero arms request-status slot **86**
        for a follow-up request instead of completing slot 72 — so a team with a tournament id
        triggers a second fetch.
      - Two 0x4Axx parsers compare a wire value against it and abort with **-1106** on mismatch
        (`0xD4F050` in 0x4A02, `0xD4FCFC`), i.e. it is the key the tournament replies are
        validated against.
      - `0xD51180` writes it to offset 0 of the ~7300-byte tournament-status object before
        filling that object's 204-byte settings and its `{lobby, subtype, rule}` triple.

      Which of "tournament", "Survival" or "match" it names is [UNKNOWN] — the client uses one
      code path for all of them and picks the wording from the lobby subtype at display time.
  - id: unknown_2a0
    type: u4
    doc: |
      [ELF 0xd4b428 -> team+0x2A0, read with the 0xD5CC64 twin] [UNKNOWN] [CONFIDENCE:
      parsed-and-unread is high; meaning is nil] **Stated negative: nothing reads it.** Same two
      sweeps and control as `unknown_262`; displacement 672 has 144 hits in the band and every
      one is either a stack adjustment (`addi r1,r1,672`) or an unrelated object, and in the
      team-pointer functions only the parser's own write.

      **Signedness [UNKNOWN]** — RESOLVED-AS-UNKNOWN 2026-07-26 and unchanged: 0xD5CC64 is
      byte-identical to 0xD5CCD8 and is not a signed accessor, nothing reloads team+0x2A0 with
      `lwa`, and there is no consumer to ask. u4 is the corpus default for an unproven 4-byte
      read; that is a default, not a claim.
  - id: entry_fee
    type: u4
    doc: |
      [ELF 0xd4b444 -> team+0x2A4] [CONFIDENCE: medium] The Metal Gear Points cost of entering,
      **0 = free**; last field, and the record ends at 680 bytes. The client's own wording
      supplies the name: `0x8C2744` and `0x8C2804` test it against zero and pick between two
      pairs of confirmation strings that differ **only** by the fee note —

      - non-zero: **703/704** *"Do you approve of the team's entry into the tournament/Survival?
        * Metal Gear Points are required to enter tournaments/Survival."*, or **707/708** for a
        member rather than the leader;
      - zero: **705/706** *"You will enter the tournament/Survival with the team's current
        settings. Is this OK?"*, or **709/710** — the same member sentences with the MGP line
        removed.

      Tournament vs Survival comes from a different byte (`lbz r0,660(r3)` on the `0x883F20`
      screen object, the lobby subtype being entered), not from this field. `0x8C2888` then
      passes the value itself as a formatting argument (`lwz r5,676(r9)` -> `0x954F18`), and
      `0x8C46BC` reloads it with `lwa`. Also written by the 0x4922 notification (0xD4D108).
      Signedness [UNKNOWN] for the same reason as `unknown_2a0`; the `lwa` at 0x8C46BC is
      caller-side and was not treated as decisive because the parser twin is unsigned.
types:
  member:
    doc: |
      25 wire bytes, 28-byte struct stride (team+0x17C + 28*n). Slot 0 is the leader
      (`0xD4DC18`, -1014). Struct bytes `+0x16` and `+0x17` are not on the wire; `+0x16` is a
      client-local per-member byte the 0x4965/0x4966/0x4967 notifications write (0xD4C2CC and
      neighbours).
    seq:
      - id: character_id
        type: u4
        doc: |
          [ELF 0xd4b274 -> slot+0x00] [CONFIDENCE: high for the role] Named from use: the
          0x4960 and 0x4964-0x4967 notifications each carry a single u32 and locate the slot
          whose first word matches it, 0x4950 does the same before overwriting a slot, and
          `0xD4DC18` matches slot 0's copy against the local character record to decide leader
          vs member. Whether the value is the character id or an account id is [UNKNOWN]; the
          match is only ever against another copy of itself.
      - id: name
        type: str
        size: 16
        doc: |
          [ELF 0xd4b290 width -> slot+0x04] [CONFIDENCE: high] 16-byte raw block, NUL at
          slot+0x14. Rendered as the member name in **string 718 "%s has joined the team."**,
          **719/768 "%s has left the team."**, **720 "%s has been kicked."** and **698 "You are
          about to kick %s off the team."** (0x8C313C and neighbours copy from `slot+0x04`).
      - id: member_state
        type: u1
        doc: |
          [ELF 0xd4b2ac -> slot+**0x15**] [CONFIDENCE: medium] Per-member entry state, and the
          single most-read byte in the roster. `0x8C27A4` tests `== 2` to offer **711/712**
          *"Are you sure you want to cancel entry into the tournament/Survival?"*, so **2 means
          "entry submitted"** (cf. **693 "Accept Entry"**, **722 "%s has approved entry."**).
          0x4922 resets every occupied slot to **1** (0xD4D13C) — the "rules changed, everyone
          must re-confirm" shape; 0x4960 stores **4**; 0x4932 stores small constants
          (0xD4D2C0). Nine notification parsers forward it straight to `0xD33CD8` as the UI
          event argument (`lbz r5,17(r11)` at 0xD4BDDC, 0xD4C108, 0xD4CC20, 0xD4EF00, 0xD4F160,
          0xD50C7C, 0xD5136C, 0xD5A394, 0xD5A5A4, 0xD5A7B4). The full enum is [UNKNOWN]; only
          1, 2 and 4 are pinned.

          OFFSET CORRECTION 2026-07-26, unchanged and re-verified 2026-08-01; wire widths never
          changed. The slot loop sets `addi r28,r31,384` (0xD4B258) and `addi r27,r31,368`
          (0xD4B25C), so the slot base is `r27+12 = r31+380` and the name buffer is
          `r28 = r31+384 = slot+0x04`. This read is `addi r4,r28,17` (0xD4B298) = `r31+401` =
          **slot+0x15**, not slot+0x11.
      - id: unknown_18
        type: u4
        doc: |
          [ELF 0xd4b2cc -> slot+**0x18**] [UNKNOWN] [CONFIDENCE: parsed-and-unread is high;
          meaning is nil] `addi r4,r28,20` (0xD4B2B4) = `r31+404` = slot+0x18. 4 + 16 + 1 + 4 =
          25 wire bytes against a 28-byte struct stride.

          **Stated negative: nothing reads it.** The roster is only ever addressed as
          `team+380+28n`, so the sweep enumerated, across all 88 team-pointer-bearing functions,
          every literal displacement in `[380, 604)` and bucketed it by `(d-380) mod 28`:
          slot+0x00 has 48 hits, slot+0x04 has 60, slot+0x15 has 3 — and **slot+0x18 has three
          hits, all `r1`-based stack frame arithmetic in unrelated functions**. The
          computed-index form was swept separately: every `addi rX,rY,384` in
          `0x880000`-`0xD80000` followed within 14 instructions by a small displacement gives
          `+17` (slot+0x15) and `+18` (slot+0x16) repeatedly and `+20` never. Control: slot+0x15
          and slot+0x04 are found by both halves of the same sweep.
