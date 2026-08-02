meta:
  id: mgo2_cmd_4e22_s2c
  title: "MGO2 0x4e22 — Survival: per-slot status column for the team record's 8 match slots (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  is in mgo2_cmd_4e00_c2s.ksy. `0x4E22` is a **server push** (no request slot) that rewrites the
  status column of the **team record's 8-slot match table** at `team+0x17C`, stride 28.

  TIER. Post-launch content; no available client build exercises this command, so **everything
  here is tier 1 and cannot be raised to tier 2.** Not served in v1.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5A3F0**, which re-checks the id (`cmpwi r0,20002`) before reading anything.

  Opens with the shared header validator **0xD49230** (u4 + u2, checked against `team+0x00` and
  `team+0x29C` on `team = 0xD491F8(session) = session+0xD928`; mismatch = -1018 and the packet is
  dropped).

  ## !! WIRE LENGTH FLAGGED, NOT CHANGED — 15 bytes, not 8 !!

  **The `seq:` below is short by seven bytes and is knowingly left that way**, per the
  flag-and-adjudicate rule in dev/proto/README.md; do not implement against it until the flag is
  resolved. The parser reads, in order:

  ```
  d5a4a8  bl 0xd49230                      ; u4 + u2  = 6 bytes  (header validator)
  d5a4c8  bl 0xd5cb8c   -> team+0x04       ; u1       = 1 byte
  d5a4d8  addi r29,r1,112                  ; loop cursor
  d5a4ec  bl 0xd5cb8c   -> r29             ; u1
  d5a4e8  addi r29,r29,1
  d5a4f4  addi r0,r1,120
  d5a500  cmpw cr6,r29,r0 ; bne -> 0xd5a4dc  ; 8 iterations, r1+112 .. r1+119
  ```

  `4 + 2 + 1 + 8*1 = ` **15 bytes**. The `std r0,112(r1)` at 0xD5A490 pre-zeroes exactly those
  eight bytes, which is the corroboration. `0x4E23` (0xD5A2B8-0xD5A2D8) and `0x4E21`
  (0xD5A6E8-0xD5A708) contain the identical loop, so all three are 15 bytes.

  The declared `unknown_06` / `unknown_07` pair is therefore the first byte plus *one* of the eight,
  and the remaining seven are missing entirely. This is a `repeat` addition, which the batch rules
  forbid changing unilaterally.

  ## What the eight bytes are

  After RD_END the parser walks the 8-entry, 28-byte-stride table at `team+0x17C` (=380 decimal,
  0xD5A50C-0xD5A588), one entry per wire byte:

  * `entry+0x00 == 0` -> the slot is empty; the byte is skipped.
  * wire byte **non-zero** -> `stb` it to **`entry+0x15`** (0xD5A574).
  * wire byte **zero** -> `memset(entry, 0, 28)` (0xD5A568) — **a zero byte deletes the slot**,
    it does not store a zero status. That asymmetry is the thing a server implementation would
    get wrong.
  * While walking, `entry+0x00` is compared against `*(0xD3A094(session)+0x00)` to remember which
    slot is the local player's (`r25`; sentinel -1 = not found).

  It then fires **UI event 39** with `arg = *(u8*)(team + 384 + 28*r25 + 17)` = the local player's
  own `entry+0x15`, i.e. *"your slot's status just became this"*. If the player is not in the table
  the event is not fired at all.

  **CORRECTION 2026-08-02.** The old note "after memsetting a 28-byte scratch area and comparing
  one of the bytes against 7 and -1" is a misreading of that loop: the `memset` is the slot-delete
  above (not scratch), the `7` is the loop bound `cmpwi cr7,r28,7` at 0xD5A578, and the `-1` is the
  not-found sentinel at 0xD5A58C. Neither is a comparison against a payload byte, so the field doc
  claiming "an enum/index with a sentinel" has no evidence behind it and is withdrawn.

  0x4e21, 0x4e22 and 0x4e23 have byte-identical layouts and identical loops; the parsers 0xD5A600,
  0xD5A3F0 and 0xD5A1D0 differ only in the id compared, the UI event fired (40 / 39 / 41) and one
  extra call in 0x4e23. **Note that `0x4E21` (id 20001, parser 0xD5A600, stub 0xD39D10) has no
  `.ksy` file at all** — reported, not created here, since this batch may only touch seven files.

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
      (`team = 0xD491F8(session) = session+0xD928`); mismatch = -1018 and the packet is dropped.
      mgo2_cmd_491b_c2s.ksy names that slot the **team id**. Same field as `0x4E20.team_id`.
  - id: team_seq
    type: u2
    doc: |
      [ELF 2026-08-02, renamed from `context_seq`] Validated by 0xD49230 against the u16 at
      **`team+0x29C`** (`lhz r0,668(r29)`, 0xD492D4); mismatch = -1018. [UNKNOWN] what increments
      it. Same field as `0x4E20.team_seq`.
  - id: unknown_0x04
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_06`] Read at 0xD5A4C8 -> **`team+0x04`**.
      Struct-offset bijection with `0x4E20.unknown_0x04` and with the same-position byte in
      `0x4E21` (0xD5A6D8) and `0x4E23` (0xD5A2A8) — one field shared by all four commands in the
      block, on the team record rather than on the Survival event record. [UNKNOWN] meaning; no
      reader was looked for, because displacement 4 off a 0x83-site getter is not a filterable
      sweep. Stated as an open question rather than a negative.

      The old claim that this byte "is later compared against 7 and against -1, so it is an
      enum/index with a sentinel" is **withdrawn** — see the CORRECTION in the top-level doc; the
      7 is a loop bound and the -1 a not-found sentinel, neither touching this value.
  - id: slot_status_0
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_07`] **The first of EIGHT per-slot status bytes**, read
      by the loop at 0xD5A4DC-0xD5A508 into r1+112..r1+119, then applied one per entry to the
      8-entry, 28-byte-stride match table at `team+0x17C`: non-zero -> `entry+0x15`, zero ->
      `memset(entry, 0, 28)`.

      **!! THE OTHER SEVEN ARE MISSING FROM THIS SCHEMA — see the WIRE LENGTH flag in the top-level
      doc.** The packet is 15 bytes, not the 8 this `seq:` describes. The remaining seven bytes are
      flagged for adjudication rather than added, because supplying them is a `repeat` change.

      [UNKNOWN] what the status codes mean. Bijection with the same column `0x4A01` and `0x4A20`
      rewrite in bulk on the *entrant* table (`mgo2_cmd_4a01_s2c.ksy`, `entrant_status`) is
      **not** claimed: that column lives at Survival event record +0x0F0 + 52*i + 0x15, a different
      object at a different stride. Same offset-within-record is a coincidence here, and saying so
      is the point — "same layout, different instance" has already caught this protocol four times.
