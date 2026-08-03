meta:
  id: mgo2_cmd_49c1_s2c
  title: "MGO2 0x49C1 - team-invitation notification: inbox insert or outbox status update (server -> client)"
  endian: be
doc: |
  IDENTIFIED 2026-08-03: **the 0x49xx team family's invitation notification.** Tier-1 only —
  the 0x49Cx senders are uncallable on this build (see the reachability note), so no capture
  can ever back this on this binary. Post-launch content, not served in v1.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39830,
  parser 0xD4E138. A single fixed 32-byte record, no loop.

  THE STORAGE, fully recovered (this corrects the earlier "storage offsets are not
  recoverable cleanly" and the "a 2-element table and a 3-element one" reading — both tables
  are 3-element, and they are halves of ONE structure): a contiguous **6 x 44-byte array at
  `session + 0x117F8`** plus a u32 at `session + 0x11900` — 268 bytes, proved by the
  session-init `memset(session+0x117F8, 0, 268)` at 0xD35784/0xD3578C and the identical clear
  at 0xD49328-0xD4934C. Entries 0-2 (`+6136`) are the **inbox** — invitations received;
  entries 3-5 (`+6268` = +6136+132) are the **outbox** — invitations sent, written by the
  0x49C0 builder and updated by the 0x49C0 reply; `+264` is the 0x49C0 rate limiter's
  last-send time (10 s, error -1043). Which half this packet touches is decided by `state`:
  **state == 1 inserts into the inbox** (0xD4E268 `cmpwi cr7,r0,1`; insert path
  0xD4E27C-0xD4E334), **state != 1 updates the matching outbox entry's `+12`**
  (0xD4E338-0xD4E364, matching on entry `+0`, touching nothing else). Then 0xD33CD8 raises
  **event 51 (state==1) or 52 (state!=1)** — both of which reach nothing: no callback is ever
  registered at 51/52 (all 16 registerCallback sites pass other ids; the group-57 "all 0-55"
  form is never called) and the pending-byte poller's twelve sites poll ids
  {3,28,29,30,34,36,39,40,41,55} only. **The notification is parsed but unobservable.**

  Record layout (44 bytes), from the insert block 0xD4E2D0-0xD4E334:
  `+0` entry_id (wire 0x02) · `+4` issued_at (wire 0x06) · `+8` u16 (wire 0x00) · `+12` state
  as a word (wire 0x0a) · `+16` u8 (wire 0x0b) · `+20` u32 (wire 0x0c) · `+24` 17 bytes name
  + NUL (wire 0x10).

  Reader closure behind every negative below: a full D-band sweep for any pointer into
  `[6136, 6404]` off the session base returns exactly nine sites — the init memset, the clear,
  accessors 0xD49224/0xD4E3E0/0xD4E40C, the 0x49C3 parser 0xD4DEFC, this parser
  (0xD4E26C/0xD4E270), the 0x49C0-reply parser 0xD4E484, and the 0x49C0 builder
  (0xD4E66C/0xD4E68C/0xD4E6D4) — all five functions read end to end, so every entry-relative
  access is accounted for. Control: the same closure finds `+0`'s readers (0x49C3 at
  0xD4DF28/0xD4DF38/0xD4DF74; 0x49C0-reply at 0xD4E504/0xD4E51C/0xD4E530). Note `+12`
  (state) is written by three commands and read by none, so `+0` is the only valid control.

  Reachability: the 0x49C0/0x49C2 senders and all five table/slot accessors have **zero call
  sites** (controls in the same banks: the my-team accessor 0xD491F8 has 83 callers; twelve of
  the sixteen same-bank slot-result wrappers have UI callers). Sending 0x49C1 to this build is
  harmless but inert: the parser runs and mutates the tables, nothing reads them, and no slot
  is armed so nothing can stall. Method note recorded 2026-08-03: OPD entries in this image
  are 4-byte {entry, toc} word pairs — a qword-based descriptor scan silently returns nothing
  for everything.

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
  - id: unknown_0x00
    type: u2
    doc: |
      [UNKNOWN] read FIRST, at 0xD4E1B0 (into r1+114) -> entry +8. Note the u16 precedes the
      u32s - do not reorder. **No reader anywhere in the image [ELF 2026-08-03, closed
      enumeration in the doc block].** The only other writer is the 0x49C0 builder, copying
      the same slot out of its caller's record (`lhz r29,8(r27)` / `sth r29,8(r31)`) — and
      that copy is NOT put on the wire, so it is a client-side attribute carried alongside
      the name. Discarded entirely on the state!=1 path. A "level/rank" reading is plausible
      from the {id, u16, name} shape and is unsupported — not written down.
  - id: entry_id
    type: u4
    doc: |
      [ELF 2026-08-03] read at 0xD4E1C8 (r1+120) -> entry +0. **The invitation's key.** It is
      what 0x49C3 matches (0xD4DF28/0xD4DF38), what 0x49C2 sends back to answer, the ONLY
      field used on the state!=1 path (matched against outbox +0 at 0xD4E338/0xD4E34C), and
      the value handed to the UI event as r5 (0xD4E370). Same id space as 0x49C2's `entry_id`
      and 0x49C3's.
  - id: issued_at
    type: u4
    doc: |
      [ELF 2026-08-03] read at 0xD4E1E0 (r1+116) -> entry +4. **Issue time, Unix seconds** —
      the units come from the mirror writer: the 0x49C0 builder fills the same slot of an
      outbox entry with `time(NULL)` (`bl 0xDD21F8` = sc 145, at 0xD4E724/0xD4E754), the same
      clock its 10-second rate limiter compares. Role: the **eviction key** — the inbox insert
      takes the first empty slot (or the slot already holding this entry_id), else reuses the
      entry with the LARGEST +4 (unsigned compare, 0xD4E2B0-0xD4E2C0). Note the policy that
      implies, and do not smooth it over: with all three slots full, the client evicts the
      MOST RECENT invitation; the two oldest are protected and the newest slot churns.
  - id: state
    type: u1
    doc: |
      [ELF 2026-08-03] read at 0xD4E1F8 (r1+112) -> entry +12 (widened to a word). **The
      routing discriminator, not just data** — the field a server implementation would get
      wrong first: **1 = freshly issued** -> insert into the INBOX and raise event 51;
      anything else -> update the matching OUTBOX entry's state and raise event 52
      (0xD4E268, 0xD4E374). "1 = freshly issued" is proved by the 0x49C0 builder writing
      literal 1 into every outbox entry it creates (`li r0,1` at 0xD4E738). Same 1..4 value
      space as 0x49C2's `answer` and 0x49C3's `new_state`. Once stored, the slot is read by
      nothing (see the doc block's closure) — the state drives routing at parse time only.
  - id: unknown_0x0b
    type: u1
    doc: |
      [UNKNOWN] read at 0xD4E210 (r1+113) -> entry +16. **No reader anywhere in the image
      [ELF 2026-08-03, closed enumeration].** The 0x49C0 builder never writes +16 (it memsets
      the entry then writes +0/+4/+8/+12/+24 only), so the field exists only on the inbound
      path and has no client-side counterpart to argue from. Discarded on the state!=1 path.
  - id: unknown_0x0c
    type: u4
    doc: |
      [UNKNOWN] read at 0xD4E228 (r1+124) -> entry +20. **No reader anywhere in the image
      [ELF 2026-08-03, closed enumeration]**; never written by the outbox path either.
      Discarded on the state!=1 path.
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [INFERRED] a 16-byte text field: fixed 16-byte raw read at 0xD4E244 (0xD5D018, len 16),
      the same width and read style every confirmed name field in this protocol uses
      (mgo2_cmd_4902.ksy name, mgo2_cmd_4221.ksy). Nothing renders it in a traced path, so
      "name" is the shape, not a proven role. [ELF 2026-08-03] Stored as 17 bytes (16 + NUL)
      at entry +24 and mirrored byte-for-byte by the 0x49C0 builder out of its input record's
      +24 — the same 16-byte text travels with the id in both directions.
