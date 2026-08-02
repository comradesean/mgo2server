meta:
  id: mgo2_cmd_4a03_s2c
  title: "MGO2 0x4A03 - Tournament/Survival counter update, four of the eight halves (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); mgo2_cmd_4a24_s2c.ksy is canonical for the event record. **0x4A03 is a
  partial update of that record**: it rewrites four of the eight u16 counters at
  event record +0x0D6..+0x0E4 and notifies the UI. Every one of its five wire fields is named
  below by struct-offset bijection to 0x4A24, so nothing here is left bare.

  TIER. Post-launch content; no available client build exercises 0x4A03, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  THE FOUR IT WRITES ARE EXACTLY THE FOUR 0x4A24 HAS NO READER FOR - `halves[0]`, `[1]`, `[6]`
  and `[7]`. That is a useful negative result rather than a coincidence: this build stores them
  and re-broadcasts one of them as an event payload, but nothing on screen consumes them.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD398C0,
  parser 0xD51880 (function entry 0xD51820 in some notes; the id compare `cmpwi 0x4A03` is at
  0xD518DC).
  No identity header (0xD49230 is NOT called) and no loop: five fields, 12 bytes, then a
  single 0xD33CD8 notify with **event 22**, whose payload is `halves[0]` (0xD519A4/0xD519BC).
  There are two preconditions before any field is stored: the team record must exist
  (0xD518C8 calls the team getter 0xD491F8; a zero id there aborts with **-1007**), and
  `event_id` must match. NOTE the read order: the four u16s are read into r1+118, r1+112,
  r1+114, r1+116 - i.e. the parser stores them out of order, which is why the offsets below are
  wire positions and the storage slots are quoted per field instead. The stores are all at the
  end, 0xD519C0-0xD519CC.
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
  - id: event_id
    type: u4
    doc: |
      [ELF] read at 0xD51908 (-> r1+120) and compared at 0xD5192C-0xD51930 against
      **event record +0x000**, i.e. the id 0x4A00 stamped and 0x4A24 must echo. Mismatch aborts
      with **-1106** and nothing after this field is stored. The base is computed at
      0xD51918-0xD51924 as `addis r9,r31,1` / `addi r9,r9,-9264` = **session+0xDBD0**, the
      session-embedded event record - the same base 0x4A24 uses, so this is a bijection, not a
      resemblance.
      **This is an id, not a result code**: it is compared against stored state and branches to
      an error constant, and it is never sign-extended into `0xD32E70`. This command consumes no
      request slot at all.
  - id: entrant_cap
    type: u2
    doc: |
      [ELF] read at 0xD51940 (-> r1+118), stored at 0xD519C4 to **event record +0x0D6** =
      `halves[0]` of mgo2_cmd_4a24_s2c.ksy. That slot is [INFERRED] there as the entrant-table
      cap, from its only two uses: 0xD520E8 and 0xD526C8 both use it as the upper bound of an
      append into a 52-byte-stride entrant table. The inference is unchanged here; what 0x4A03
      adds is that a second command writes the same slot.
      It is also this packet's event payload - 0xD519BC moves it into r5 for
      `0xD33CD8(session, 22, value)`.
  - id: half_0x0d8
    type: u2
    doc: "[ELF] read at 0xD51958 (-> r1+112), stored at 0xD519C8 to **event record +0x0D8** = `halves[1]`. [UNKNOWN] meaning: 0x4A24's sweep found no reader for +0x0D8 in either the 0x8C0000-0x900000 UI window or the 0xD30000-0xD70000 network window, with `halves[2]`/`[3]`/`[5]` as the controls that did come back. Written by two commands, read by none."
  - id: half_0x0e2
    type: u2
    doc: "[ELF] read at 0xD51970 (-> r1+114), stored at 0xD519CC to **event record +0x0E2** = `halves[6]`. [UNKNOWN] meaning; same no-reader sweep and same controls as above."
  - id: half_0x0e4
    type: u2
    doc: "[ELF] read at 0xD51988 (-> r1+116), stored at 0xD519C0 to **event record +0x0E4** = `halves[7]`. [UNKNOWN] meaning; same no-reader sweep and same controls as above. Note this one is stored FIRST of the four despite being last on the wire."
