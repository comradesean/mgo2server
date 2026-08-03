meta:
  id: mgo2_cmd_4982_s2c
  title: "MGO2 0x4982 — server -> client: TEAM list entries for TEAM SELECT (middle of the 0x4981/0x4982/0x4983 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4982` at `0xd38ce8` and branches to the
  thunk at `0xd39630`, which tail-calls the parser at `0xd4b790`. Channel A (lobby TCP).

  NOUN CORRECTED 2026-08-03: this was titled the "clan-member list". Per the 2026-08-01
  adjudication recorded in `mgo2_cmd_4984_c2s.ksy` and `mgo2_cmd_4985_s2c.ksy`, the object is a
  **team**, and this is **the list of teams** shown on the TEAM SELECT screen (disc `lobby`
  string 640) — one row per team, every row field a team property (id, capacity, member count,
  rule, deployed state). Tournament content: **not served in v1**, and no available client
  build exercises it, so everything here is tier-1 only and cannot reach tier 2.

  THE LIST AND ITS ACCESSOR BANK [ELF 2026-08-03]. Destination is
  `list = *(session+0x11904) + 0x1C4C0` (`addis r9,r9,2 / addi r27,r9,-15168` at 0xD4B7F8):
  `+0` open marker (parse guard: -73 while 0), `+4` count, rows at `+8`, **stride 56, row
  offset == scratch offset** (the two `stswi` chunks abut: 32 bytes to row+8, 24 to row+40 —
  the old "entry+0x08 / entry+0x28" phrasing invited reading the record as 64 bytes; it is
  one contiguous 56-byte record at `list + 8 + 56*n`). The displacement -15168-after-addis-2
  appears at exactly five sites image-wide: the reset `0xD344F0`, the accessor `0xD490F0`,
  and the 0x4983/0x4981/0x4982 parsers — so the ONLY route to the rows is the bank
  `0xD490D4` GetList / `0xD49114` GetCount (6 callers) / `0xD4915C` GetRow (bounds-checked,
  14 callers, all in five TEAM SELECT functions: `0x8C60B4` sort, `0x8C6458` list events,
  `0x8C6F18`, `0x8C7A5C` build/paint, `0x8C8E4C` state machine). This list has NO
  listNode painter in the 0xAF3xxx-0xAF5xxx band — the readers are the four in-screen column
  loops in `0x8C7A5C` (name / members "n/m" / rule / deployed state) plus the join gates.

  THE OWNING SCREEN: TEAM SELECT, scene `FB_LOBBY_tournament_ST`, vtable
  `0x101B3C0`..`0x101B3E8`, 23-arm state machine `0x8C8E4C`. `0x4980` (the request that opens
  this triple) has **exactly one caller image-wide: `0x8C8F88`, state 1** — sent
  unconditionally on entering the screen; failure raises dialog 5200, and the wait on slot 62
  (`0xD49A98`) times out after 6000 ticks into dialog 5201. Selecting a row sends `0x4984`
  with the row's `team_id`; joining goes through `0x4912` behind the `0xD4908C`
  "already in a team" gate (dialogs 5212/5215/5217).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  **No result code and no count.** The parser loops on `0xD5CEB0` (bytes-remaining) and reads
  records until the cursor reaches `hdr.payload_len` [READ 0xd4b83c]; each completed record is
  appended at `list+0x008 + 56*n` with the count at `list+0x004`, and the loop **aborts with
  -71 once the count exceeds 99** [READ 0xd4ba10] — so at most 100 entries are accepted and
  the 101st poisons the whole reply. Size-driven, not count-driven; record this, because
  getting that backwards has bitten this project before.

  Each record is assembled in a 56-byte stack scratch (memset at 0xD4B818-0xD4B830) and then
  copied in two `lswi`/`stswi` chunks (32 bytes from scratch+0x00 to row+0x08, 24 bytes from
  scratch+0x20 to row+0x28 — contiguous, see above).

  **One field is conditional.** The flag byte's bit 2 gates a second 16-byte string: the
  parser expands the byte into a word at scratch+0x24 (bit 0 -> 0x80, bit 1 -> 0x40, bit 2 ->
  0x20, bit 3 -> clears the low 5 bits and sets 0x01) and then re-reads that word, taking the
  extra `0xD5D018` 16-byte read only when 0x20 survives [READ 0xd4b918-0xd4b934]. So a record
  is **35 bytes with the bit clear and 51 bytes with it set** — there is no length prefix and
  no way to parse the stream without tracking that bit.

  **OVERLAP HAZARD [ELF 2026-08-03], previously unrecorded:** `optional_name` spans
  scratch+0x16..+0x25 and the expanded flag word spans +0x24..+0x27 — a two-byte overlap. The
  word is written first and the string clobbers its two most-significant bytes. Benign on this
  build only because every expanded bit (0x80/0x40/0x20/0x01) lives in byte +0x27 and every
  reader masks the low byte; any future reader treating +0x24 as a u32 gets string bytes in
  the high half.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: |
      [ELF 0xd4b818-0xd4ba48] Repeat until the payload is exhausted. Count source is the
      payload length, NOT a leading count. Client-side cap 100 entries.
types:
  entry:
    seq:
      - id: team_id
        type: u4
        doc: |
          [ELF 2026-08-03] scratch+0x00 -> row+0x00. **The team's id** — passed as the argument
          to the `0x4984` sender `0xD4A578` when a row is selected (`0x8C964C`, `0x8C974C`),
          and compared against the viewed-team record's `+0x00` (`0xD491C8` ->
          `ctx+0x1A598`) at `0x8C6D28`/`0x8C762C`. The same value
          `mgo2_cmd_4984_c2s.ksy` already documents as `team_id`; this closes the loop from
          the row side. Tier-1 only — no client build exercises this family.
      - id: name
        type: str
        size: 16
        doc: |
          [ELF 2026-08-03 — now confirmed as the TEAM NAME] scratch+0x05, 16-byte raw block,
          NUL at +0x15 via the memset. Painted into the column set up with
          `STRING_naiyou_ON_HOST` by `0x8C7A5C`'s first column loop — `row+5` is handed as a
          C string to the cell setter `0x94AD8C` at `0x8C88B4` — and it is sort key 0,
          compared with `strcmp` (`0x8C6178`, `0x8C9168`).
      - id: deploy_state
        type: u1
        doc: |
          [ELF 2026-08-03 — named by its label strings and its gate] scratch+0x04 -> row+0x04
          (read AFTER the 16-byte block, stored before it). **The team's
          deployment/availability state, and the join gate.** The column painter `0x8C7D84`
          renders `strres("lobby", row[0x04]==1 ? 646 : 647)` — **string 647 is "Deployed"**
          (the same label `mgo2_cmd_4985_s2c.ksy` pins for the team record's `game_id` row
          state) — into the `STRING_naiyou_ON_STATUS-2` column. And it is a hard gate: a value
          `!= 1` refuses joining with dialog **5215 "New members cannot currently join the
          team."** (`0x8C94A4`/`0x8C94D8`, `0x8C6654`). So 1 = joinable, non-1 = deployed/
          closed; the exact text of string 646 has not been fetched from the disc.
      - id: flags
        type: u1
        doc: |
          [ELF 0xd4b8b0-0xd4b934] Bit field, expanded one bit per position into the word at
          scratch+0x24: bit 0 -> 0x80, bit 1 -> 0x40, bit 2 -> 0x20, bit 3 -> clears the low
          five bits then sets 0x01. **Bit 2 also gates the presence of `optional_name`
          below.** Bits 4-7 are read but never expanded — no effect on this build.

          Per-bit readers [ELF 2026-08-03]: **wire bit 1** (word 0x40) shows the row element
          `NULL_ON_KEY` (`0x8C6B38`, `0x8C8C84`) — deliberately NOT named "password lock"
          here, because `0x4913`'s record flags put the password bit at wire bit 0 and
          asserting the match would be cross-packet inference; **wire bit 3** (word 0x01)
          **blocks joining** with dialog 5215 (`clrldi. r9,r0,59` at `0x8C6664`/`0x8C94B4`);
          **wire bit 0** (word 0x80): no reader anywhere.
      - id: optional_name
        type: str
        size: 16
        if: (flags & 0x20) != 0
        doc: |
          [ELF 0xd4b924] Present ONLY when the expanded flag word has 0x20 set, i.e. when
          wire bit 2 of `flags` is set. Copied to scratch+0x16. A second name-width string
          [INFERRED]; identity [UNKNOWN].

          [ELF 2026-08-03] **Parsed and never read** — the taint propagation over all five
          TEAM SELECT reader functions (stack spills modelled, escape check run: no row
          pointer leaves them except `row+5` to the cell setter) finds nothing at +0x16, and
          so the string reading now has no renderer to support even the inference. Note the
          two-byte overlap with the expanded flag word (doc block above).
      - id: member_capacity
        type: u1
        doc: |
          [ELF 2026-08-03] scratch+0x28. **The team's member capacity** — the "/ m" half of
          the members column: `0x8C83AC`-`0x8C8428` renders `"<count>" + "/" + "<capacity>"`
          into `STRING_naiyou_ON_PLAYER`, each clamped to 99 for display. And the join gate's
          other half: `if (row[0x29] >= row[0x28])` raises dialog **5207 "Maximum number of
          players already reached. Unable to join team."** (`0x8C94BC`-`0x8C94D0`,
          `0x8C666C`).
      - id: member_count
        type: u1
        doc: |
          [ELF 2026-08-03] scratch+0x29. **Current member count** — the "n /" half of the
          members column (see `member_capacity`), the left operand of the 5207 capacity gate,
          and **sort key 1**, compared numerically (`0x8C61A8`, `0x8C918C`).
      - id: friend_block_flags
        type: u1
        doc: |
          [ELF 2026-08-03] scratch+0x2a. Per-row icon bits, each with its own reader: **bit 0
          shows the row element `NULL_ON_FRIEND`** (`0x8C6B9C`/`0x8C8CE8`), **bit 1 shows
          `NULL_ON_BLACK`** (`0x8C6C00`/`0x8C8D4C`) — element names resolved from the module
          TOC (`r30 = 0xFEF588`). So: "contains a friend" / "contains a blocked player" row
          icons, named from this screen's own elements, not inherited from `0x4302`'s
          same-named field. Bits 2-7: no reader.
      - id: unknown_d
        type: u4
        doc: |
          [UNKNOWN] scratch+0x2c. **Parsed and never read [ELF 2026-08-03 — precise
          negative].** The scan: (1) the list is reachable only through the accessor bank
          (five displacement sites image-wide, all enumerated in the doc block); (2) taint
          propagation of the GetRow return through all five reader functions, stack spills
          modelled, finds loads at +0x00/+0x04/+0x24/+0x28/+0x29/+0x2A/+0x31 and the derived
          `row+5` pointer only; (3) blanket displacement sweep over `0x8C5E00`..`0x8C9D80`
          finds no +44 hit on a row base. Control: the same sweep resolves the single byte
          +0x31 (`rule`) and every named neighbour — it discriminates. Tier-1 only.
      - id: unknown_e
        type: u1
        doc: |
          [UNKNOWN] scratch+0x30. **Parsed and never read [ELF 2026-08-03 — precise
          negative].** Same three-part scan and control as `unknown_d` (nothing at +0x30; the
          control resolves the immediately adjacent +0x31). Tier-1 only.
      - id: rule
        type: u1
        doc: |
          [ELF 2026-08-03] scratch+0x31. **The team's rule id**, painted into the
          `STRING_naiyou_ON_STATUS` column: `0x8C809C` does `lbz r3,49(r9); addi r3,r3,22;
          bl 0x8E0BF0` = `strres(0x654515, rule + 22)` — the abbreviated rule-name run
          (ids 22..29 are `DM`, `TDM`, ... — the same expression already pinned in
          `mgo2_cmd_4313_s2c.ksy` and `mgo2_cmd_4909_s2c.ksy`).
      - id: unknown_g
        type: s4
        doc: |
          [UNKNOWN] scratch+0x34, read with the 0xD5CC64 twin. **Parsed and never read
          [ELF 2026-08-03 — precise negative].** Same three-part scan and control as
          `unknown_d` (nothing at +0x34). Tier-1 only.
