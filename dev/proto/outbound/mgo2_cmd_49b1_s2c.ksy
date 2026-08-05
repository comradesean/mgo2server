meta:
  id: mgo2_cmd_49b1_s2c
  title: "MGO2 0x49B1 - server -> client: team record (shared 0xD4AF34 layout)"
  endian: be
doc: |
  MAPPED 2026-08-01. PROTOCOL.md and OBSERVED.md still describe nothing about 0x49B1; every
  name below comes from the ELF, and the record is the TEAM record shared by six ids.

  Evidence: GAME dispatcher 0xD387C8 (compare tree at 0xD38804), entry stub 0xD39660 -> thunk 0xD4B640, which sets
  `li r4,0x49B1` (0xD4B648) and `addi r5,r1,112` (the result out-param) and tail-calls the
  SHARED parser 0xD4AF34.

  0xD4AF34 SERVES A FAMILY: it dispatches on the id in r4 against 0x4911, 0x4913, 0x4985,
  0x4987, 0x49A1 and 0x49B1 (0xD4AF98-0xD4AFCC). 0x49B1 takes the same branch as 0x4985
  (0xD4AFDC) and skips the 0x4987-only sub-read at 0xD4B238. So the layout below is 0x49B1's
  path through a shared function - reading the function top to bottom without following the id
  compares would produce a layout no id actually uses.

  The record is memset to 680 bytes before parsing (0xD4B0F4, `li r5,680`), so unsent trailing
  fields read as 0 rather than stale. Total wire size on this path: 420 bytes.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

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
  [2026-08-03] Wrapper polarity, stated inverted in the five sibling files until today: `-1` is
  the parser's SUCCESS return (`li r3,-1` at `0xD4B524`, the fall-through end of a full parse;
  the failure exits -24 / -71 / 0 leave the slot alone), and ONLY a `-1` return completes the
  slot.

  The screen side reaches this record through exactly ONE channel [2026-08-03]: a team pointer
  is spilled to non-stack memory at 41 sites, every one writing team+0 into +108 of a
  screen/frame object (0x8BFD38 .. 0x8D0624). Any future negative on this struct must sweep
  that reload-plus-displacement channel — it is what a naive dataflow misses, and sweeping it
  recovers real readers (the entry_fee formatter 0x8C2888 reaches the record only this way).

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
      for the team, and the word its "am I on a team?" gate reads.

      **[CORRECTED 2026-08-04 — the polarity here was inverted, and the error code was on the
      wrong branch.]** `0xD4908C` returns **-1 when this word is NON-zero** and **0 when it is
      zero**:

      ```
      d490a0  lwz    r0,-9944(r9)    ; session+0xD928+0 = team_id
      d490a4  cmpwi  cr7,r0,0
      d490a8  bne    cr7,0xd490b0    ; NON-zero -> keep the -1 loaded at 0xd49094
      d490ac  li     r11,0           ; zero     -> 0
      ```

      So it is a boolean *"am I on a team?"*: **-1 = yes, 0 = no**. Its 23 call sites split
      cleanly by polarity, and they use **two different error codes**:

      - commands that **require membership** test `== 0` and fail **-1007** (`0xD4A394`,
        `0xD4BAFC`, `0xD4BEA0`, `0xD4C748`, `0xD4C8E0`, `0xD4D5C4`). A received -1007 raises
        dialog **5170** *"You have already left the team.\nUnable to leave team."* (`0x8C24AC`;
        `0x8D0020` maps it to 5168 instead).
      - commands that **require NON-membership** — Create Team, and the entry commands — test
        `== -1` and fail **-1004** (`0xD4A278`, `0xD4A978`, `0xD4AB00`, `0xD4AD44`).

      The old sentence said "-1 when it is zero" and hung -1007 on that branch; both halves were
      backwards. The dialog link itself was right.

      What the player experiences: this is why "Create Team" is refused while you are already in
      one, and why every team menu action is refused once you have left — two different refusals
      with two different sentences, decided by whether this word is zero.

      Every team-event notification's header word is also compared against it (helper
      `0xD49230`). For 0x4985/0x49b1 it is additionally checked against a context value and a
      mismatch aborts the whole reply.
  - id: team_serial
    type: u2
    doc: |
      [ELF 0xd4b148] [CONFIDENCE: high — 2026-08-04] Stored at team+0x29C — read SECOND on the
      wire but living far down the struct. `0xD492D4` loads it with `lhz` and compares it
      against the u16 in every team-notification header, and `0x49a8` is the only other writer
      (`sth r0,668(r28)` at 0xD4BF10).

      **What it is: a record epoch, and it is load-bearing.** `0xD49230(session, team, reader)`
      is the header validator that **every team notification runs first — 30 call sites**. It
      reads a u32 and a u16 off the wire and compares them against `team+0x000` and this field;
      **either mismatch returns -1018 and the whole notification is discarded** (`0xD492F8`).
      Both compares are skipped only when the reader's command id is `0x4960`.

      `0x49A8` is the pure bump: validate the header, read one u16, store it here, raise UI
      event 18 with the new value (`0xD4BF00`-`0xD4BF14`). Nothing else.

      **Why the game needs it.** The client caches one 680-byte team record and then receives a
      stream of deltas — 30 different notification ids, most of them carrying a member index and
      a state byte rather than a whole record. Applying a delta to a stale copy would silently
      desync the roster on screen: a row for someone who already left, a state that never
      un-ticks. So the server stamps the record with a serial, every delta quotes it, and the
      client throws away anything that does not match. `0x49A8` exists so the server can
      invalidate the client's copy without resending 680 bytes. **A player never sees this
      number; what they see is the absence of a phantom roster row.**

      **Server hazard for a future Team implementation, and it is the sharpest one in this
      record:** with 30 notifications gated on it, the server must increment this on every
      mutation *and* re-send it. Get that wrong and the second delta after any change is dropped
      with -1018 — the roster freezes with no error and no visible cause.

      The numbering rule itself is still [UNKNOWN]: nothing in the client constrains it beyond
      "must match".
  - id: team_state
    type: u1
    doc: |
      [ELF 0xd4b164 -> team+0x004] [CONFIDENCE: medium] A phase byte for the team, set by the
      server and pushed by two notifications. Readers, all with the value in hand:

      - `0x8C7D84`-`0x8C7D94` — **the Select Team list**, and the clearest one. Each 56-byte
        list entry is fetched through a third getter `0xD4915C`, and `entry+4 == 1` prints
        string **646**, anything else prints **647**. That is the team's status column:
        **"Open" vs "Deployed"** — i.e. whether a player browsing the team list can join this
        row at all.
      - `0x8CBC48`: `<= 2` vs `> 2` selects which **"please wait" line** the Team Standby screen
        shows. **[CORRECTED 2026-08-04 — the old reading of this branch is refuted.]** It was
        documented as choosing between menu labels **739 "Cancel Entry"** and **740 "Leave
        Team"**, and therefore as meaning "0-2 is withdrawable, 3+ is not". Those words are not
        ids 739/740. The Cancel-Entry / Accept-Entry pair is **693/694**, proven at `0x8C04AC`
        where `member_state == 2` selects 694 and otherwise 693, with 695 = "Leave Team". Ids
        739/740 are the two *status sentences* **"Your team has been formed. Please wait until
        the tournament starts."** and **"...until an opposing team is found."** So this branch
        picks a status line, not a menu label, and **no conclusion about withdrawability follows
        from it**.
      - `0x8CBCA8`: `== 5` selects a different standby panel.
      - `0x8C3080` / `0x8C3180` / `0x8D4A54` / `0x8D7B6C`: `== 9` makes the join event render
        **string 731 "Number of Players Currently Joined: %d / %d"** over a count of non-zero
        roster slots, instead of the per-member **718 "%s has joined the team."** — i.e. 9 is
        automatic team formation (strings 681-686 "Auto Join Team", 716 "Forming a team...",
        717 "Team formation complete."). `0x4918` makes the same case explicit from the other
        side: `0xD4D6D4` requires an incoming member's state byte to be **2** when `team_state`
        is 9 and **1** otherwise, rejecting with **-1036** — auto-formed teams arrive
        pre-approved.

      **What the field is for.** `team_state` is the team's position in the *entry pipeline*, and
      it drives three things a player sees: whether other players can find and join you (the
      Open/Deployed column in the Select Team list), what the Team Standby screen tells you you
      are waiting for, and whether team events are narrated per-person or as a headcount. It is
      on the wire rather than computed because only the server knows the state of the tournament
      or Survival queue the team is sitting in.

      Writers other than this parser [values corrected 2026-08-03 — they were swapped]:
      `0x4961` stores **5** (`0xD4C7DC`, inside the parser whose id compare is
      `cmpwi r0,18785` at 0xd4c73c) and `0x4960` stores **4** (`0xD4C988`, id compare
      `cmpwi r0,18784` at 0xd4c8d4). The addresses were attached to the right ids; the values
      were reversed.

      **[CORRECTED 2026-08-04 — "no other store to team+0x004 exists" was wrong, and the reason
      it was wrong is a method lesson.]** There are **fifteen** further wire writers. An
      `stb`-only sweep cannot see them, because the parsers do not store the byte themselves —
      they hand `team+4` to the u8 read primitive as an argument. Found by re-running the sweep
      on the **argument channel** as well as the memory channel: `0xD4B164` (the shared six),
      `0xD4BC88` (0x49A2), `0xD4C004` (0x4943), `0xD4CAB0` (0x4950), `0xD4EE18` (0x4A27),
      `0xD4F070` (0x4A02), `0xD506A8` (0x4A01), `0xD50BA0` (0x4A29), `0xD50FC4` (0x4A00),
      `0xD514E4` (0x4A22), `0xD51B18` (0x4A20), `0xD5A2A8` (0x4E23), `0xD5A4C8` (0x4E22),
      `0xD5A6D8` (0x4E21), `0xD5B240` (0x4E20).

      Eleven of them share **one wire shape**: `u8 team_state` followed by **eight u8 member
      states**, where a zero byte wipes the slot (`memset(slot, 0, 28)` via `0xDD36F8`) and a
      non-zero one stores at `slot+0x15`. Canonical instance `0x4E23` at `0xD5A29C`-`0xD5A368`.
      Each ends by raising a UI event carrying **the local player's own member_state**.

      Values pinned: **1** (Open, in the list column), **4** (`0x4960`, a member approved),
      **5** (`0x4961`, entry closed and a game assigned), **9** (auto-formation), plus the
      `<= 2` / `> 2` split on the standby status line. **0, 2, 3, 6, 7 and 8 are unobserved** —
      no site in the image discriminates them.
  - id: team_name
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF 0xd4b184 width; role CONFIRMED 2026-08-04] [CONFIDENCE: high] team+0x005, 16-byte
      raw block, NUL at +0x015. The Create Team screen's own field label is **string 664/672
      "Team Name"** and the rule text is **668** *"Enter a team name. The following symbols can
      also be used: ..."*.

      **[BAND CONFIRMED 2026-08-04.]** These ids were re-read from group `[2f0293]`'s own index
      records rather than counted, and the earlier alignment holds with **no drift**:
      **646 募集中 "Open"** / **647 出場中 "Deployed"** (the browser's status column),
      **654 / 665 / 673 "Password Lock"**, **656 "No comment."**, **664 / 672 "Team Name"**,
      **666 / 674 "Comment"**, **668** *"Enter a team name.\nThe following symbols can also be
      used:\n !#$()*+,-./:;=?@[]^_｛｝"*, **670** *"This comment is displayed when\nplayers select
      this team."*, **681-684 "Auto Join Team"** (four screen variants), **685** *"Automatically
      form a team together with other characters who have selected the 'Auto Join Team' option."*,
      **686** the same for *'Quick-Join Team'*. Context either side also resolved: 640 TEAM SELECT,
      644/648 Join Team, 649 Members, 655 *"There are currently no teams open to join."*, 657
      STATUS, 658-663 the CREATE TEAM family, 675 *"Good Luck."* (the default comment), 676 TEAM
      CREATION, 677 AUTO TEAM CREATION, 687 *"Enter With This Team"*, 688 *"Change Rules"*, 689/690
      the clan-affiliation pair.

      One id from that band had been an open anomaly and is now resolved: **742** takes two format
      arguments at `0x8CC474` and `0x8CDA8C`, which the previous alignment could not explain because
      the string it landed on had no conversion specifiers. Read from the index table it is
      *"The championship match has ended.\nWinning team: %s\nYour reward: %d"* — exactly the `%s`
      then `%d` its callers pass (`r5` = the team-name buffer, `r6` = `lwa` of the reward). So the
      formatter was not tolerating unused arguments; the alignment was simply off. It is the
      end-of-tournament results banner: after the final match every participant sees the winning
      team and their own Metal Gear Point reward on one dialogue.

      **The role is no longer inferred — there are two readers**, both on the `screen+108` spill
      channel:

      ```
      8c3d84  lwz  r4,108(r22)   ; team pointer out of the screen object
      8c3d88  addi r4,r4,5       ; team+0x005
      8c3d90  li   r5,32
      8c3da0  bl   0xAF70F0      ; bounded copy into a 33-byte buffer
      ```

      identically at `0x8CE82C`-`0x8CE840`; the buffer then goes to the text widget (`0x244340`).
      So this is the heading rendered across the team screens — what a player reads at the top
      of the panel, and what identifies the team in the browser to people who are not in it.
      That is why it is server-supplied rather than local: every viewer needs it, not just
      members.

      Note the display copy is **32 bytes, not 16** — the same over-wide read as `clan_name`, and
      inert for the same reason: `0xD5D018` writes the NUL at `team+0x015` (`stb r0,0(r9)` with
      `r9 = r4+r5`, `0xD5D07C`), so the bounded copy stops there. The wire width of 16
      (`li r5,16` at `0xD4B180`) is unaffected and correct.
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF 0xd4b1a4 width; role CONFIRMED 2026-08-04] [CONFIDENCE: high] team+0x016, 128 bytes,
      NUL at +0x096. The Create Team screen labels it **string 666/674 "Comment"**, described by
      **670** *"This comment is displayed when players select this team."*, with **"No
      comment."** as the empty placeholder.

      **The role is no longer inferred — two readers, both in the browse screens**, both reached
      through the *viewed-team* getter `0xD491C8` rather than the my-team one:

      ```
      8c6d9c  bl   0xD491C8
      8c6da4  addi r29,r3,22      ; team+0x016
      8c6db8  lbz  r0,0(r29)      ; first byte
      8c6dc0  beq  -> 0x8c6df4    ; empty -> li r3,299 ; bl 0x8E0C24 (placeholder)
      8c6dd4  bl   0xDCC4F0(...)  ; otherwise render the comment itself
      ```

      identically at `0x8C76B8`. So this is the blurb a team leader writes and **the thing a
      player reads in the team-details panel before deciding whether to join** — which is
      exactly where both readers live. The empty case substitutes a placeholder rather than
      leaving a blank panel; the id fetched at these two sites is **299**, not the 656 the Create
      Team screen uses, and both can be true because they are different screens.

      Same width as the player comment in 0x4221. Same width as the player comment in 0x4221.
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
  - id: slots
    type: slot
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
      objects. (2026-08-03: a full-decode image-wide sweep counts 38 hits / 16 in-band — the
      15 reflects a narrower instruction set, and the old "`0x00BE`-`0x00C0`" was an address
      range that understated the spread; conclusion unchanged, zero on a team base.) Control: the identical sweep for `+0x2A4` returns its four
      real readers and for `+0x298` its six, so the method does find readers when they exist.
  - id: unknown_264
    type: u2
    doc: |
      [ELF 0xd4b364 -> team+0x264] [UNKNOWN] **No reader anywhere in the image — precise
      negative, re-established 2026-08-03 by three independent enumerations, each validated on
      live controls in this struct** (the controls recover lobby_id x9, subtype x18, rule x14,
      clan_id x32, entry_fee's formatter 0x8C2888, and more):

      (1) Image-wide literal-displacement sweep: 293 hits at displacement 612 (97 in the
      0x880000-0xD80000 band, across 110 functions) — zero in a function that can hold a team
      pointer, and none at all in 0x8B0000-0x8E0000 (the team screens) or 0xD30000-0xD64000
      (networking), the only two bands genuine team-record readers inhabit. (The earlier "16
      hits in the band" was not reproducible — a narrower instruction set; conclusion
      unchanged, and these counts state the band and decode so they reproduce.)
      (2) Dataflow from all 81 team-pointer origin functions (121 with callees, three levels
      deep), modelling stack slots: zero accesses at +612 — the only touch anywhere is the u16
      read primitive's own store, reached from this parser.
      (3) The spill channel (see the doc block): every reload-through-screen-object access
      reaches tail offsets 608, 609, 640, 644 and 676 only — never 610..615.

      Tier-1 only, and it cannot reach tier 2: no available client build exercises this family.
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
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF 0xd4b3a0 width -> team+0x26C] [CONFIDENCE: medium-high] The name of that game. The
      0x4310 host-game sender, immediately after a successful send and only when
      `0xD4908C` says the player is in a team, memsets 17 bytes at **team+620** and copies the
      **same 16-byte buffer it just put on the wire as 0x4310's `name`** into it
      (`r24`, 0xD44888 and 0xD44CC4). So the client mirrors the hosted game's name here.
      **No reader exists, and the negative is now exhaustive** (2026-08-04): a forward-dataflow
      sweep from 250 team-pointer origins — every `bl 0xD491F8` (83 sites), every `bl 0xD491C8`
      (15), every `addi rX,rY,-9944` / `-23144`, and every `lwz rX,108(rY)` in the screen range —
      following **both** the memory channel and the call-argument channel, finds exactly two
      accesses at +620 image-wide, and both are the write path above. Control: the same sweep
      reproduces every reader list already documented in this file (`lobby_id` x9,
      `lobby_subtype` x15, `rule` x14, `clan_id` x26, the flag word's 17 maskers) at their known
      addresses.

      **Game purpose: the binary does not support one, and this is stated rather than guessed.**
      The field is written locally when *you* host a game while on a team, and the server echoes
      it back in this record, but nothing in the disc build renders `team+0x26C`. The plausible
      reading — a *"...is playing &lt;game name&gt;"* line on a team screen — is **labelled
      speculation** and is not claimed. What would settle it: a live capture of the team-details
      panel for a team whose `game_id` is non-zero, or locating the reader in the 1.36 image
      (re-derive it there; **do not** carry an address across builds).
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
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF 0xd4b3dc width -> team+0x284] [CONFIDENCE: high] That clan's name. `0x8C143C`-
      `0x8C1450` memsets a 33-byte display buffer and copies from **team+644** into it once
      `clan_id` is non-zero and the `0x40` bit is set. The 0x4925 notification rewrites the
      `{u32, char[16]}` pair on its own, so the two travel together.

      [2026-08-03] The display copy is **32 bytes, not 16**: seven sites (`0x8C143C`,
      `0x8C3A3C`, `0x8C3F5C`, `0x8C4F14`, `0x8CAEF8`, `0x8CE488`, `0x8CE9F0`) copy
      `+644..+675` into a 33-byte buffer — a window that physically spans `unknown_296`,
      `tournament_id`, `serial` and `unknown_2a0`. Inert: the parser's NUL at `+660` always
      stops the bounded copy there. The wire width of 16 (`li r5,16` at 0xD4B3D8) is
      unaffected and correct.
  - id: unknown_296
    type: u2
    doc: |
      [ELF 0xd4b3f8 -> team+0x296] [UNKNOWN] **No reader anywhere in the image — precise
      negative, re-established 2026-08-03** by the same three control-validated enumerations as
      `unknown_264`: displacement 662 has 10 hits image-wide (8 in .text; the two past 0xDE9328
      are misdisassembled data), all classified — six take their base from `bl 0x883F20`, the
      screen-object getter (whose own +662 is an unrelated one-shot latch byte, recorded so the
      collision is not mistaken for a hit later), and two are r1. The dataflow and
      spill-channel sweeps (see `unknown_264`) never reach +662. It is preceded by a 2-byte
      gap — the string at `+0x284` ends at `+0x293` and its NUL lands at `+0x294`.

      **Hazard, not bug: this is the parser's only unchecked read.** Of 26 read-primitive
      calls in 0xD4AF34, 25 are followed by `cmpwi cr7,r3,0; bne -> fail(-71)`; the one at
      0xD4B3F8 is not (0xD4B3FC is a nop), so a payload that dies exactly on this field is
      never reported and the parse runs on into `tournament_id`. Nothing served today reaches
      it, which is the part that can change.

      Tier-1 only, and it cannot reach tier 2: no available client build exercises this family.
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
      team-pointer functions only the parser's own write. (2026-08-03: full-decode counts are
      1254 image-wide / 355 in-band — same narrower-sweep arithmetic as `unknown_262`, same
      unchanged conclusion; the 2026-08-03 dataflow and spill-channel sweeps also never reach
      +672.)

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
      screen object, the lobby subtype being entered), not from this field.

      **[CORRECTED 2026-08-04 — the "formatting argument" sentence overstated what the player
      sees.]** `0x8C2888` does pass the value to `0x954F18` (`lwz r5,676(r9)`), but **none of
      strings 703-710 contains a conversion specifier** — checked in all six languages. On the
      confirmation screen the number is never printed; the fee's only visible effect there is
      choosing the variant that carries the *"* Metal Gear Points are required"* line. The fee
      **is** printed elsewhere: `0x8C46BC` reloads it with `lwa` and passes it to `0xDD0688`
      against a format string from the TOC (`lwz r4,-32528(r30)`) — a numeric entry-fee field.

      So what the player experiences is: a price shown on the entry screen, and a warning line
      added to the confirmation dialog when the price is non-zero. Zero means free and removes
      the warning entirely. Also written by the 0x4922 notification (0xD4D108).
      Signedness [UNKNOWN] for the same reason as `unknown_2a0`; the `lwa` at 0x8C46BC is
      caller-side and was not treated as decisive because the parser twin is unsigned.
types:
  slot:
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
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
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
          must re-confirm" shape; 0x4960 stores **4**; 0x4932 stores exactly **1 or 2**
          (0xD4D2C0; the accepted wire range, 2026-08-03 — and its `== 2` selects UI event 5
          over 4). Nine notification parsers forward it straight to `0xD33CD8` as the UI
          event argument (`lbz r5,17(r11)` at 0xD4BDDC, 0xD4C108, 0xD4CC20, 0xD4EF00, 0xD4F160,
          0xD50C7C, 0xD5136C, 0xD5A394, 0xD5A5A4, 0xD5A7B4).

          **[EXTENDED 2026-08-04 — the enum is now mostly pinned, and two more writers found.]**
          `0x4925` also sweeps every non-zero slot to **1** (`0xD4CFA0`, guarded by the read at
          `0xD4CF94` so empty slots stay empty), and `0x4961` promotes state **4 to 6** and
          everything else non-zero to **5** (`0xD4C7DC`-`0xD4C80C`). `0x4918` requires **2** when
          `team_state == 9` and **1** otherwise, rejecting with -1036 (`0xD4D720`).

          | value | what it means | pinned by |
          | --- | --- | --- |
          | 0 | empty slot — a 0 in any bulk update **removes this member** | the `memset(slot,0,28)` on every bulk parser |
          | 1 | on the team, entry not yet approved | `0x4922`/`0x4925` reset; `0x4918` normal join |
          | 2 | entry approved/submitted | `0x8C04AC`, `0x8C27A4` |
          | 4 | this member just approved | `0x4960` (`0xD4C944`) |
          | 5 / 6 | entry closed: 4 becomes **6**, everyone else **5** | `0x4961` (`0xD4C7DC`) |

          **3, 7 and above are unobserved** — no site discriminates them.

          **What the player sees.** This is the badge on each roster row, and it decides what
          your own options menu offers: with your byte at 1 the menu reads **693 "Accept
          Entry"**; at 2 it flips to **694 "Cancel Entry"** and the confirm dialog changes to
          **711/712** *"Are you sure you want to cancel entry into the tournament/Survival?"*
          (`0x8C04AC`, `0x8C27A4`). It is also the mechanism behind "the leader changed the
          rules, so everyone has to agree again" — `0x4922` and `0x4925` sweep every occupied
          slot back to 1, which visibly un-ticks the whole roster at once.

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
