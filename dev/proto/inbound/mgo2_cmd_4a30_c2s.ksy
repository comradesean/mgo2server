meta:
  id: mgo2_cmd_4a30_c2s
  title: "MGO2 0x4a30 — Tournament/Survival: request one event by id (client -> server)"
  endian: be
doc: |
  4-byte payload: one unsigned u32 — **the id of the event the player selected in the browse
  list**. The 0x4Axx block is the Tournament / Survival subsystem, settled 2026-08-02 (tier 1);
  see mgo2_cmd_4a24_s2c.ksy.

  TIER. Post-launch content; no available client build sends 0x4A30, so **everything here is
  tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  THE FLOW, END TO END, and it is what names the argument. The caller is **0x8F43E0-0x8F43FC**:
  it takes the highlighted row of the browse list through the accessor **0xD4EBA8** (the
  104-byte-stride array at `*(session+0x11904)+0x252F0` that **0x4A42** fills), loads that
  row's **+0x00** — 0x4A42's `event_id` — and passes it here as the only argument. After the
  flush the client caches the same u32 at `*(session+0x11904)+0x26D08` and arms request slot 87.
  **0x4A31's parser echo-checks exactly that cached word** (0xD4FCC8) before writing the event
  record, so the server must return the id it was given.
  The caller's failure dialog is **5409, "Unable to acquire Tournament list."** — one of the
  three dialogs that identify this block.

  TWO LEGAL COMPLETIONS FOR SLOT 87, which is worth knowing before implementing a server:
    * **0x4A31** — parser 0xD4FB80 (shared with 0x4A24), clears the slot at 0xD501E8. One
      packet carrying the whole event record.
    * **0x4A34** — parser 0xD52398, clears the slot at 0xD524A0. That is the terminator of the
      **0x4A32 / 0x4A33 / 0x4A34** list triple, i.e. the entrant table delivered row by row.
  Either satisfies the request. The third setter of slot 87, 0xD4F5F0, writes state **0**, so
  it is a reset rather than a completion.

  Also note the adjacency at the destination: the cached id sits at `+0x26D08` and **0x4A47's**
  6-byte entry-status ticker sits immediately after it at `+0x26D0C`.

  Evidence (ELF, retail BLUS30109): sender 0xD5048C, signature (session, u32). Prologue
  spills `stw r4,1416(r1)`. Builder `bl 0xD5CF40` at 0xD50500 (`li r4,0x4a30` at 0xD504FC);
  the only write between builder and seal is `bl 0xD5C9BC` at 0xD50510 (unsigned u32, 4
  bytes MSB first). Seal `bl 0xD5C828` at 0xD5051C, flush `bl 0xD34CC0` at 0xD5052C.
  Preconditions: session != NULL plus the two generic connection checks (0xD38504,
  0xD3844C). The u32 is not range-checked.

  Useful extra: on a successful flush the client **caches the value it just sent** into the
  global block at `+0x6D08` (`lwz r0,1416(r1)` / `stw r0,27912(r9)` at 0xD50564..0xD50568),
  then advances the flow state via `0xD32E08(session, 87, 1)`. 0x4B20's sender does the same
  thing into the adjacent slot `+0x6D00`. So the argument is a *selection the client
  remembers* — a current-item or current-page id — rather than a one-shot action code.

  The old note that "the 0x4A33 list id is adjacent to this send id, which is suggestive of a
  request/list pairing but is [INFERRED] from numbering only" is now **confirmed by evidence
  rather than adjacency**: 0x4A34, the terminator of the 0x4A32/0x4A33/0x4A34 triple, is a
  slot-87 completer, and slot 87 is the slot this sender arms.

  Never observed live; not answered by this server, and not served in v1.
seq:
  - id: event_id
    type: u4
    doc: |
      [ELF] Position and width exact (unsigned, 0xD5C9BC). Unvalidated by the sender.
      **The id of the selected tournament / survival event**: the caller reads it from the
      browse-list row that 0x4A42 delivered (row+0x00), and the client caches it at
      `*(session+0x11904)+0x26D08` after the flush (`lwz r0,1416(r1)` / `stw r0,27912(r9)` at
      0xD50564-0xD50568). 0x4A31's parser compares its own leading id against that cached word
      and aborts with -1106 on a mismatch, so the value is a request key the reply must echo.
      Named by struct-offset bijection across three commands (0x4A42 row+0x00 -> here ->
      0x4A31's check), not by resemblance.
