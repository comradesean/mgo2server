meta:
  id: mgo2_cmd_4e23_s2c
  title: "MGO2 0x4e23 — Survival: per-slot status column + teardown of the Survival event record (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  is in mgo2_cmd_4e00_c2s.ksy. `0x4E23` is `0x4E22` **plus a full teardown of the Survival event
  record** — it is the "this Survival event is over, drop everything" push.

  TIER. Post-launch content; no available client build exercises this command, so **everything
  here is tier 1 and cannot be raised to tier 2.** Not served in v1.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5A1D0**, which re-checks the id (`cmpwi r0,20003`) before reading anything.

  Opens with the shared header validator **0xD49230** (u4 + u2, checked against `team+0x00` and
  `team+0x29C` on `team = 0xD491F8(session) = session+0xD928`; mismatch = -1018 and the packet is
  dropped). No request slot.

  ## Wire size: 15 bytes (ADJUDICATED 2026-08-02 — was declared 8)

  The read sequence is `u4 + u2` via 0xD49230, one u1 at 0xD5A2A8, then an **eight-iteration u1
  loop** at 0xD5A2BC-0xD5A2E8 into r1+112..r1+119 (`addi r29,r1,112` at 0xD5A2B8; the single
  `bl 0xd5cb8c` at 0xD5A2CC is re-executed by the backward `bne cr6,0xd5a2bc` at 0xD5A2E8, and
  0xD5CB8C advances the payload cursor at `[ctx+1108]` by one on every call). `4 + 2 + 1 + 8*1 =`
  **15 bytes**.

  The destination bytes are pre-zeroed by a plain **`std r0,112(r1)`** at 0xD5A270 — encoding
  `F8010070`, DS-form low bits `00`, i.e. **not** the `stdu` update form that made `0x4A02` and its
  siblings read a loop bound as a byte count. `addi r0,r1,120` at 0xD5A2D4 is an end address, and
  since the cursor starts at r1+112 the trip count is 8 regardless of how it is read.

  **What the earlier reading mistook for the length:** it counted one `u1` because there is one
  `bl 0xd5cb8c` in the instruction text, i.e. it counted call *sites* rather than *executions*.

  See mgo2_cmd_4e22_s2c.ksy for the full annotated disassembly and for what the eight bytes do
  (per-slot status on the team record's 8-entry, 28-byte table at `team+0x17C`; non-zero ->
  `entry+0x15`, **zero deletes the slot**).

  ## The extra step, and it is not small

  `bl 0xD4EC14` at **0xD5A374**, run after the slot walk and before the UI event. `0xD4EC14` is

  ```
  d4ec14  addis r9,r3,1 ; addi r3,r9,-9264   ; = session+0xDBD0, the Survival event record
  d4ec30  li r5,7296                          ; = 0x1C80
  d4ec3c  bl 0xdd36f8                         ; memset(record, 0, 7296)
  ```

  i.e. it **zeroes the entire 7296-byte Survival event record** — the settings block, the entrant
  count at +0x0DA, the whole 128-row entrant table at +0x0F0, the list magic at +0x0E8 and the six
  trailing words. 7296 is the same size `0x4A31`'s arm memsets at 0xD4FCDC, which is what pins the
  record's length. After `0x4E23` the Survival Match List is empty and the client must send a fresh
  `0x4E00` to repopulate it. `0x4E22` does not do this; that is the whole difference between them.

  Then it fires **UI event 41** with `arg = *(u8*)(team + 384 + 28*myslot + 17)`, exactly as
  `0x4E22` fires event 39 and `0x4E21` fires event 40.

  **CORRECTION 2026-08-02.** "After memsetting a 28-byte scratch area and comparing one of the
  bytes against 7 and -1" is a misreading: the 28-byte memset is the per-slot delete, the 7 is the
  loop bound (`cmpwi cr7,r28,7`, 0xD5A358) and the -1 is the not-found sentinel (0xD5A37C). No
  payload byte is compared against either, so the "enum/index with a sentinel" reading of the field
  below is withdrawn.

  0x4e21, 0x4e22 and 0x4e23 have byte-identical layouts (parsers 0xD5A600, 0xD5A3F0 and 0xD5A1D0
  differ only in the id compared, the UI event fired, and the teardown call above). `0x4E21`
  (id 20001, parser 0xD5A600, stub 0xD39D10) now has its own `.ksy`; the note that it had none is
  stale.

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
      [ELF 2026-08-02, renamed from `context_id`] Validated by 0xD49230 against **`team+0x00`**
      (`team = 0xD491F8(session) = session+0xD928`); mismatch = -1018 and the packet is dropped —
      which, for this command, also means the teardown does not happen. mgo2_cmd_491b_c2s.ksy names
      that slot the **team id**. Same field as `0x4E20.team_id` and `0x4E22.team_id`.
  - id: team_seq
    type: u2
    doc: |
      [ELF 2026-08-02, renamed from `context_seq`] Validated by 0xD49230 against the u16 at
      **`team+0x29C`** (`lhz r0,668(r29)`, 0xD492D4); mismatch = -1018. [UNKNOWN] what increments
      it. Same field as `0x4E20.team_seq` and `0x4E22.team_seq`.
  - id: unknown_0x04
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_06`] Read at 0xD5A2A8 -> **`team+0x04`**.
      Struct-offset bijection with the same-position byte in `0x4E20` (0xD5B240), `0x4E21`
      (0xD5A6D8) and `0x4E22` (0xD5A4C8) — one field shared by all four commands in the block.
      [UNKNOWN] meaning; no reader sweep attempted, because displacement 4 off an 83-call-site
      getter is not filterable. Open question, not a stated negative.

      The "enum/index with a sentinel" claim is withdrawn — see the CORRECTION in the top-level doc.
  - id: slot_status
    type: u1
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 2026-08-02, renamed from `unknown_07` -> `slot_status_0` -> `slot_status`] **EIGHT
      per-slot status bytes**, read by the loop at 0xD5A2BC-0xD5A2E8 and applied one per entry to
      the team record's 8-entry, 28-byte-stride match table at `team+0x17C`: non-zero ->
      `entry+0x15`, zero -> `memset(entry, 0, 28)`.

      **ADJUDICATED 2026-08-02 (third reading).** Was a single `u1` named `slot_status_0`, making
      the packet 8 bytes; it is a fixed 8-element array and the packet is 15. The `_0` is gone
      because there are eight, not one. Derivation and the `std`-vs-`stdu` check are in the
      top-level doc; modelled as `repeat: expr` with a literal count, the same way
      `mgo2_cmd_4a24_s2c.ksy` models `trailing_words`, because the count is compiled in rather than
      carried on the wire.

      [UNKNOWN] what the status codes mean. Deliberately **not** equated with the entrant-status
      column of `0x4A01`/`0x4A20`: that one lives on the Survival event record at
      +0x0F0 + 52*i + 0x15, a different object at a different stride, and matching on
      offset-within-record alone is exactly the "same layout, different instance" trap.
