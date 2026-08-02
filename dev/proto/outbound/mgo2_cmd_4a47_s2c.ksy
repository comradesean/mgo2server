meta:
  id: mgo2_cmd_4a47_s2c
  title: "MGO2 0x4A47 - Tournament/Survival entry-status ticker per lobby subtype (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. **Every field of 0x4A47 is named, from a traced reader plus disc
  strings** - this is the best-evidenced command in the 0x4Axx block after 0x4A24. It is the
  little "how many have signed up, how long is left" ticker on the tournament / survival
  waiting screens.

  TIER. Post-launch content; no available client build exercises 0x4A47, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.** The field meanings come from
  the client's own format strings, which is the strongest evidence available on this side, but
  it is still tier 1.

  DESTINATION, corrected 2026-08-02. Not `session+0x6D0C`. The base is
  `lwz r4,6404(session+0x10000)` / `addis r29,r4,2` / `addi r9,r29,27916` =
  **`*(u32*)(session+0x11904) + 0x26D0C`** (0xD399E4-0xD399F8) - the same heap object that
  holds the second event-record instance, and **immediately after the u32 at +0x26D08 that the
  0x4A30 sender stashes** (0xD50568) and 0x4A31 echo-checks (0xD4FCC8). Six bytes, zeroed by
  three `sth` stores first (0xD39A04-0xD39A0C), so a short or absent value reads as 0 rather
  than stale. The same six bytes are also zeroed by 0xD34688-0xD34698 on teardown.

  THE READER, and it is what names everything below. **0xD382B0** is a guarded getter:
  `if (record.byte0 == arg) return record; else return NULL` (0xD382E0-0xD382E8). Its two call
  sites, **0x8CD6E8** and **0x8C3684**, both pass **`team+0x260`, the lobby subtype**
  (`lbz r4,608(team)`) as that argument - the field dev/docs/AUTOMATCH.md resolved and
  mgo2_cmd_4a24_s2c.ksy carries as `lobby_subtype` (3 = Tournament, 4 = Survival,
  5 = Official Tournament). On a hit both sites then format:
    * lobby string **727**, *"Current Entry Status: %d / %d"*, with `record+1` and `record+2`
      as the two `%d` (0x8CD710-0x8CD720, 0x8C36AC-0x8C36BC);
    * lobby strings **728 / 729 / 730**, *"%s (time remaining: %d minutes)"*, *"... %d
      seconds)"*, *"... %d minutes % seconds)"*, from `record+4` treated as a count of
      **seconds** (`divwu` by 60 for minutes at 0x8CD74C, remainder for seconds).
  Disc-string method: dev/docs/AUTOMATCH.md section 10; set `$strres:9789..11033`, string base
  11034. Control for the resolution: ids 251 and 245 in the same set come back "Automatching"
  and "Free Battle", matching PROTOCOL.md's already-established Lobby Select labels.

  Evidence: GAME dispatcher 0xD387C8 (compare tree at 0xD38804), entry stub 0xD399C0 - and
  unusually there is NO separate parser function: 0x4A47 is parsed INLINE inside the dispatcher
  (0xD399C0-0xD39AB8), the only id in this batch that is. The dispatcher re-checks the id
  itself (0xD399D4, cmpwi 19015) before reading.
  On success it calls 0xD33CD8 with event 35 (0xD39AA8: li r4,35), payload = `lobby_subtype`.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE34 delimiter-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  ADDRESS AND SEMANTICS CORRECTION (2026-07-26, read out of the primitive itself): the string
  reader's entry point is **0xD5CE34**, not 0xD5CE3C — the previous function's `blr` is at
  0xD5CE30 and 0xD5CE3C is two instructions into the body. It is **not** a NUL-terminated
  string reader: the loop compares each byte against **r5, a caller-supplied delimiter**
  (`cmpw cr7,r0,r5` at 0xD5CE78); NUL is only a secondary stop (`cmpwi cr6,r0,0` at 0xD5CE7C).
  Callers that pass r5 = 0 get NUL termination as a special case. Either way the cursor is
  advanced **past** the terminator (`addi r9,r9,1` at 0xD5CEA4 after `stw r11` at 0xD5CE94), so
  the field consumes **len + 1** wire bytes, and the client writes its own NUL at dest+len
  (0xD5CE9C).

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
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF] read at 0xD39A20 into a stack byte and RANGE-CHECKED: `cmplwi 9 / bgt+ -> bail`
      (0xD39A34). Values 0-9 only; 10 or more aborts the parse silently. Stored at
      record+0x00 after the check.
      **It is the lobby subtype**, and the whole record is keyed on it: the getter 0xD382B0
      returns this record only when this byte equals `team+0x260`, the subtype of the lobby the
      player is standing in (0x8CD6E4, 0x8C3680). So the ticker a client sees is the one whose
      subtype byte matches its lobby, and a server that sends the wrong subtype here makes the
      panel silently vanish rather than error. Same enum as mgo2_cmd_4a24_s2c.ksy's
      `lobby_subtype`: 3 = Tournament, 4 = Survival, 5 = Official Tournament. The 0..9 range
      check is consistent with subtypes, which PROTOCOL.md enumerates up to 10.
      It is also the payload of the event-35 notify (0xD39AA4).
  - id: entrants_now
    type: u1
    doc: '[ELF] read at 0xD39A4C -> record+0x01. **The first `%d` of lobby string 727, "Current Entry Status: %d / %d"** - the number signed up so far. Read at 0x8CD710 and 0x8C36AC as the fifth argument to the formatter 0xDD0688.'
  - id: entrants_required
    type: u1
    doc: '[ELF] read at 0xD39A68 -> record+0x02. **The second `%d` of lobby string 727** - the target the count is shown against. Read at 0x8CD718 and 0x8C36B4. [INFERRED] whether it is a minimum or a maximum: string 756, "Not enough teams have joined. The tournament has been canceled.", says a minimum exists, but nothing links that path to this byte.'
  - id: seconds_remaining
    type: u2
    doc: |
      [ELF] read at 0xD39A84 -> record+0x04. Note the gap: record+0x03 is skipped (alignment
      padding in the struct, **not** on the wire - the u16 follows the u8 immediately).
      **A countdown in seconds.** 0x8CD728-0x8CD79C divides it by 60 for the minutes of lobby
      string 728, takes the remainder for the seconds of 729, and uses 730 when both are
      non-zero; zero suppresses the timer entirely (`beq` at 0x8CD730). The seconds are
      rounded down to a multiple of five before display (the `%10 > 4 ? -5` fixup at
      0x8CD734-0x8CD760), which is presentation, not protocol.
