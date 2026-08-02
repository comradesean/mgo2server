meta:
  id: mgo2_cmd_4e12_s2c
  title: "MGO2 0x4e12 — Survival Match List: end of entrant list, one echoed event id (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven:
  everything here is read out of the client parser.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  is in mgo2_cmd_4e00_c2s.ksy. `0x4E12` ends the `0x4E10`/`0x4E11`/`0x4E12` triple and is the
  packet that releases the screen: it closes pending-request slot 90, which the client's own
  `0x4E00` armed.

  TIER. Post-launch content; no available client build exercises this command, so **everything
  here is tier 1 and cannot be raised to tier 2.** Not served in v1.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser **0xD5A9A0**,
  which re-checks the id (`cmpwi r0,19986` = 0x4e12) before reading anything.

  ## CORRECTION 2026-08-02: the s4 is NOT a result code

  The earlier reading — "start and end carry a single RESULT CODE" by analogy with the
  0x4601/0x4602/0x4603 and 0x4681/0x4683 social triples — is **refuted by the parser**. The word
  is an **echo of `0x4E10`'s `event_id`** and it is validated, not published:

  ```
  d5aa30  bl 0xd5cc64                  ; read u32 -> r1+112
  d5aa48  lwz r0,0(r27)                ; r27 = 0xD4EA60(session) = event record +0x000
  d5aa50  lwz r9,112(r1)
  d5aa54  li r11,-1106
  d5aa58  cmpw cr7,r9,r0 ; bne -> return -1106
  ```

  `-1106` (`-0x452`) is the same id-mismatch code `0x4A24` uses for its own echo check
  (mgo2_cmd_4a24_s2c.ksy, `obj_id`) and that `0x4E20` uses at 0xD5B224. So **a non-zero value here
  does not mean "error"; a value that is not `0x4E10`'s `event_id` means the packet is dropped and
  the screen times out at `5521:FFFFFF60`.** There is no error channel in this packet at all — a
  server that wants to report a failed list has to do it through `0x4E10`'s own fields or by not
  opening the list.

  The old note that "the s4 on the wire is checked but not published" was half right and is kept:
  0xD5AA88 passes `r5 = 0` to 0xD32E70, so the request's published result is a literal zero
  regardless. That is what the screen polls for at 0x930CA0 (`0xD330C4(session, 90)`) before
  advancing to state 3; a non-zero there raises `5520:<code>`, but nothing in this packet can make
  it non-zero.

  ## What else it does

  * **Closes the list.** 0xD5AA9C writes `0` to the list magic at event record **+0x0E8**. That is
    the flag `0xD4EAAC` tests before handing the entrant table to the UI (`if [+0x0E8] == 0 return
    ptr`, 0xD4EAC0-0xD4EAD0), so **the table is invisible to every renderer until this packet
    arrives**. `0x4E10` set it to `-1`; `0x4E11` refuses to append unless it is non-zero. The three
    packets are a strict sequence, not three independent pushes.
  * **Closes request slot 90** (0xD5AA74, `0xD32E08(session, 90, 2)`) — the counterpart to the
    `0x4E00` sender's `state = 1` at 0xD5B108. Those two are the only writers of slot 90 in the
    image.
  * **Fires UI event 37** (0xD5AAA0) with `arg = the running row count at event record +0x0EC`
    (`lwz r5,4(r26)`), not with the wire word.

  Nothing else is read; a longer payload would simply be ignored, a shorter one would read
  stale receive-buffer bytes (the readers bound-check the 1023-byte buffer, not the payload
  length — see PROTOCOL.md).

  Read primitives (all confirmed by disassembling the primitive table at 0xD5C844+):
  0xD5CB8C / 0xD5CB54 u1, 0xD5CC14 / 0xD5CBC4 u2, 0xD5CC64 / 0xD5CCD8 u4 (each pair identical
  twins — see the CORRECTION below), 0xD5D018 fixed-size
  byte block of `len` bytes (memcpy + a client-side NUL written at dest[len], so the wire
  consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (returns -1 at end — this is
  what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. An earlier revision added:
  "In each signed/unsigned pair the LOWER address is the signed accessor (proved on the write
  side, where 0xD5C95C uses `sraw` and 0xD5C9BC uses `srw`; and here 0xD5CC64's value is
  reloaded with `lwa`)." **That claim is SUPERSEDED — see the CORRECTION below.** Only the
  `lwa` half of it survives, and it is a fact about the caller, not the primitive.

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

  Request-slot machinery: 0xD32E08(session, slot, state) writes session+0x160+slot*4+8 and
  0xD32E70(session, slot, value) writes session+0x330+slot*4+12 — the client's pending-request
  table (117 slots). A reply that calls these is the terminator of a request; `value` is the
  s4 the packet carried. 0xD33CD8(session, event, arg) is the UI event dispatch instead.

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
    type: s4
    doc: |
      [ELF 2026-08-02, renamed from `result`] The whole payload. **An echo of `0x4E10`'s
      `event_id`**, read at 0xD5AA30 and required to equal the u32 at event record +0x000
      (0xD5AA48-0xD5AA5C); mismatch returns **-1106** and the packet is dropped without closing the
      list or the request slot. See the CORRECTION in the top-level doc for why the old "signed
      result/error code" reading is withdrawn — the value is a transaction token, not a status, and
      the request's published result is a hardcoded 0 either way (0xD5AA88, `r5 = 0`).

      **WIDTH/TYPE FLAGGED, NOT CHANGED.** Declared `s4`; the justification recorded here was
      "the CALLER reloads it with `lwa`", and that is not what the caller does — 0xD5AA50 reloads
      it with `lwz` and compares it with `cmpw` against another `lwz`. Every other schema in the
      family declares this id `u4` (`0x4E10.event_id`, `0x4E20.event_id`, `0x4A24.obj_id`). Same
      four bytes on the wire; raised for adjudication per dev/proto/README.md rather than changed,
      because a *server* must simply echo what it sent and the signedness cannot alter that.
