meta:
  id: mgo2_cmd_4e10_s2c
  title: "MGO2 0x4e10 — Survival Match List: event record + begin entrant list, 236 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  and its three independent evidence lines are written out in mgo2_cmd_4e00_c2s.ksy. `0x4E10` is
  the **start** of the reply to the client's `0x4E00`: it fills the event record and opens the
  entrant list that `0x4E11` fills and `0x4E12` closes.

  TIER. Survival is post-launch content (Ver. 1.10). No available client build exercises this
  command, so **everything here is tier 1 and cannot be raised to tier 2.** Not served in v1.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5AD5C**, which re-checks the id (`cmpwi r0,19984`) before reading anything.

  ## Destination: the Tournament/Survival event record, proven not inferred

  The parser's one and only destination is `0xD4EA60(session)` = `session + 0x10000 - 9264` =
  **`session+0xDBD0`** (`0xD5ADA0`). That is byte-for-byte the object mgo2_cmd_4a24_s2c.ksy calls
  the **Tournament/Survival event detail record** (`0x4A24`'s arm takes
  `addis r9,r27,1; addi r31,r9,-9264` — the identical two instructions). Every field below lands
  on a slot that file already names, which is why the names transfer: same accessor, same offsets,
  same widths.

  ## It is a list BEGIN, exactly like 0x4A10

  * `0xD5ADD4` requires the list magic at **`obj+0x0E8`** to be **0**, else `-73`.
  * `0xD5B00C` does `memset(obj+0x0E8, 0, 6664)`. 6664 = 8 + 52*128, which independently pins the
    entrant table at **128 rows of 52 bytes** starting at `obj+0x0F0`.
  * `0xD5B01C`/`0xD5B020` then write count 0 at `obj+0x0EC` and magic **-1** at `obj+0x0E8`.

  `0x4A10`'s parser (`0xD52170`) does the same three things on the same object. `0x4E10` simply
  also carries the event record itself, which `0x4A10` does not.

  **CORRECTION (2026-08-02).** An earlier revision of this file said "Sets pending-request slot 90
  to state 1 … and then immediately builds and sends 0x4E00 back (`li r4,19968` into builder
  0xD5CF40 at 0xD5B0CC)", and COMMANDS.md line 189 still says it. **It is wrong in both halves.**
  `0xD5B0CC` lies inside `0xD5B05C`, a *separate* function — the `0x4E00` sender, whose only caller
  is the Survival Match List screen (mgo2_cmd_4e00_c2s.ksy). This parser runs `0xD5AD5C`-`0xD5B058`
  and contains **no** `bl 0xD32E08` and **no** builder call at all. The exchange is
  `0x4E00` (client, arms slot 90) -> `0x4E10` / `0x4E11` / `0x4E12` (server; `0x4E12` closes slot
  90). A server sending `0x4E10` incurs no obligation to answer anything.

  Bulk of the payload is a **204-byte settings block** read by the shared sub-parser
  **0xD4364C**, whose own read sequence was disassembled: a 16-iteration loop of three u1 reads
  (48 bytes, three parallel 16-byte arrays at dest+0/+16/+32), then u1,u1,bytes[16],u1,u1, three
  u4, two u2, two u4, u2, u1,u1, then 18 u4, bytes[2], u2, u4, u1, bytes[2], u1, u2, u2, u4, u1,
  u1, bytes[14] — 204 bytes total, ending at dest+204. That block is NOT expanded here: its
  canonical model is `mgo2_cmd_4313_s2c.ksy`, type `game_settings`, whose field names are
  backed by live capture of the `0x4310` push and the `0x4305` reply (OBSERVED.md).
  `0xD4364C` has nine call sites — `0xD445A4` (0x4313), `0xD48440` (0x4905), `0xD48964`
  (0x4909), `0xD4B244` (0x4987), `0xD4CB08` (0x4950), `0xD5006C` (0x4A24/0x4A31), `0xD51014`
  (0x4A00), `0xD5AF38` (here), `0xD5B78C` (0x43F1). Whether the game-settings semantics carry
  over to a 0x4E10 record is [UNKNOWN]; the byte boundaries are not.

  Wire size: 4 + 2 + 1 + 1 + 204 + 4 + 5*4 = **236 bytes**.

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
  - id: event_id
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_00`] Read at 0xD5ADF4 -> stored with `stw r0,0(r29)`
      to **event record +0x000**. **The Survival event record id**, and the token the rest of the
      exchange is keyed on.

      Struct-offset bijection with mgo2_cmd_4a24_s2c.ksy's `obj_id`: same accessor (0xD4EA60),
      same offset, same width, and the same `-1106` mismatch code guards it from both sides —
      `0x4A24` validates its copy against `team+0x298` (0xD4FCFC), while **`0x4E12` and `0x4E20`
      each re-read a u32 and require it to equal this slot** (0xD5AA48-0xD5AA5C and
      0xD5B220-0xD5B230, both `li r11/r31,-1106`). So a server must echo the value it sends here
      in `0x4E12` and in every subsequent `0x4E20`, or the client drops those packets and the
      screen times out at `5521:FFFFFF60`.

      Note the storage quirk: the slot is a 64-bit word. This `stw` fills the **high** half; the
      `flags_byte` bits below are OR'd into the low half (record +0x004) with `ld`/`std`.
  - id: entrant_count
    type: u2
    doc: |
      [ELF 2026-08-02, renamed from `unknown_04`] Read at 0xD5AE14 -> `sth r0,218(r29)` =
      **event record +0x0DA**. **The number of entrant rows** the `0x4E11` records will fill.

      Two proofs, one local and one by bijection:
        * Local: it is the bound of this subsystem's own row accessor. `0xD5A8B4(session, index)`
          does `lhz r0,218(r28); cmpw r29,r0; blt` before returning `table + 52*index + 8`
          (0xD5A90C-0xD5A920), and `0xD5A810` exposes it to the UI as the list length.
        * Bijection: mgo2_cmd_4a24_s2c.ksy's `halves[2]` is the same offset on the same object and
          is already named **"number of entrants"** — it bounds the `0x4Axx` accessor `0xD51CF4`,
          the display loops at 0x8CC450 / 0x8CDA80 / 0x8CDEB8 / 0x8FB480, and the length of the
          per-entrant status arrays in `0x4A01` and `0x4A20`.

      It is **not** a length prefix for this packet's own bytes and **not** the running row count:
      `0x4E11` bumps a separate counter at +0x0EC. A server that disagrees between the two will
      show rows the accessor refuses to hand out (or vice versa).
  - id: flags_byte
    size: 1
    doc: |
      [ELF] Read as a 1-byte block, then all 8 bits are expanded into the LOW half of the 64-bit
      word at event record +0x000, i.e. into **+0x004** (0xD5AE4C-0xD5AF0C): bit0 -> 0x80000000,
      bit1 -> 0x40000000, bit2 -> 0x20000000, bit3 -> 0x10000000, bit4 -> 0x08000000,
      bit5 -> 0x04000000, bit6 -> 0x02000000, bit7 (sign) -> 0x01000000. All eight bits are used —
      unlike 0x4b21's flags byte, which uses three.

      This bit ladder is also the file's calibration for the `rldicl.` idiom, and it is worth
      keeping: `clrldi. r9,r0,63` = bit 0, `rldicl. r9,r0,63,63` = **bit 1**,
      `rldicl. r9,r0,62,63` = bit 2, … `rldicl. r9,r0,58,63` = bit 6, `extsb`+`bge` = bit 7. That
      ladder is what proves `0x4E11`'s presence bit is 0x02 and not 0x01.

      **[UNKNOWN] meanings, and no reader.** Swept all 22 `bl 0xD4EA60` call sites (which, with
      the `0x4Axx` accessor `0xD51CF4`'s eight, are where every reader of this record lives) for a
      load at displacement 0 or 4, plus any `ld`: **zero** hits at +4 and no `ld` at all. Controls
      that DID come back in the same sweep: `lwz r0,0(r22)` at 0xD5B220 (`0x4E20`'s `event_id`
      echo check) and `lwz r0,0(r27)` at 0xD5ADD4 / 0xD5AA48 (the list magic). `0x4A24` writes
      only +0x000 on this slot and never touches +0x004, so these eight bits are currently inert —
      written by one command, read by none.
  - id: unknown_05
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_07` to match the destination] Read at 0xD5AF1C ->
      **event record +0x005** (`event = 0xD4EA60(session) = session+0xDBD0`). [UNKNOWN] meaning.

      Cross-packet bijection: mgo2_cmd_4a24_s2c.ksy's field at obj+0x005 (read at 0xD50050) and
      `0x4A00`'s `unknown_last` (0xD51148/0xD51154) write **this exact slot**, so it is one field
      shared by three commands.

      **[ELF 2026-08-03] The negative is now chokepoint-complete, not displacement-only:
      written by exactly three commands, read by none.** All 21 `bl 0xD4EA60` sites plus all
      13 direct `addi ...,-9264` materialisations were swept for displacement 5 in load, store
      and addi-pointer form: the only hits are the three parser writes (0xD5AF10 here,
      0xD50044 = 0x4A24, 0xD50900 = 0x4A00). Controls in the identical sweep: disp 212
      (`phase`) finds its readers 0x8F95D8/0xD5B344 and writers, disp 218 (`entrant_count`)
      finds five UI readers — so the sweep reaches both the UI modules and the parser bank.
      Escape check: every in-band `lbz rX,5(rY)` outside those functions is in the read
      primitives at >= 0xD5C1A8 or in modules that never touch the record (a bare
      displacement-5 sweep has 588 hits image-wide, which is exactly why the chokepoint form
      is the argument). A server may send anything here.
  - id: settings_block
    size: 204
    doc: |
      [ELF] 204 bytes consumed by the shared reader 0xD4364C into **event record +0x008**. Layout
      modelled canonically in `mgo2_cmd_4313_s2c.ksy`, type `game_settings`; kept opaque here so
      the copies cannot drift.

      The destination settles the earlier "[UNKNOWN] whether the game-settings meanings carry
      over": it is the same slot `0x4A24` and `0x4A00` fill (0xD5006C, 0xD511B0), and
      mgo2_cmd_4a24_s2c.ksy reads it as **the event's game settings** — rule, map rotation and the
      weapon-restriction bitfield the Survival event runs under. Same object, same offset, same
      reader; the meanings do carry over.
  - id: trailing_word_0
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_d4`] First of **six consecutive u32**, unrolled at
      0xD5AF48-0xD5AFE0 -> event record **+0x1C64, +0x1C68, +0x1C6C, +0x1C70, +0x1C74, +0x1C78**.
      This one goes to +0x1C64.

      Struct-offset bijection with mgo2_cmd_4a24_s2c.ksy's `trailing_words`: same six offsets, same
      widths, same object (`0x4A24` reaches it through the identical `session+0xDBD0` base).
      [UNKNOWN] meanings, and **none of the six has a reader** — see the shared evidence note on
      `trailing_word_5`.
  - id: trailing_word_1
    type: u4
    doc: |
      [ELF] -> event record +0x1C68. See `trailing_word_0` for the bijection and
      `trailing_word_5` for the negative-result sweep.

      **ADJUDICATED 2026-08-02 (third reading): `s4` -> `u4`.** The declaration rested on "SIGNED
      accessor 0xD5CC64", and that rule is dead. Re-derived rather than taken from this file's own
      CORRECTION: 0xD5CC64 (0xD5CC64-0xD5CCD4) and 0xD5CCD8 (0xD5CCD8-0xD5CD48) were compared
      instruction by instruction and are **encoding-identical** — same `lwz r0,1108(r3)`, same
      `cmpwi 1020` bound, same `mtctr 4` byte-assembly loop with `lbzx`/`extsb`/`and 255`/`slw`/
      `stw`, same `addi r9,r9,1`/`stw` cursor bump, same `extsw r3,r11` return. The only differing
      words are the two branch displacements, which differ by exactly the 0x74 function offset. So
      the accessor's address carries no signedness at any width, and no caller supplies it either:
      the sweep on `trailing_word_5` was re-run here and found **zero readers** for all six slots.

      **What the wrong reading mistook for the answer: the callee's address.** This file is its own
      proof — `trailing_word_0` is read at 0xD5AF54 by 0xD5CCD8 and was declared `u4`, while words
      1-5 are read at 0xD5AF70/8C/A8/C4/E0 by 0xD5CC64 and were declared `s4`. Six adjacent slots
      on the same object, split purely by which of two identical functions the compiler emitted.

      `u4` also matches the sibling `mgo2_cmd_4a24_s2c.ksy` `trailing_words` (`type: u4`,
      `repeat-expr: 6`), which writes the same six offsets on the same record. Same four bytes on
      the wire either way. Applies identically to `trailing_word_2` through `trailing_word_5`.
  - id: trailing_word_2
    type: u4
    doc: "[ELF] -> event record +0x1C6C. Same bijection and same sweep as `trailing_word_1`; `s4` -> `u4` on the same adjudication (2026-08-02)."
  - id: trailing_word_3
    type: u4
    doc: "[ELF] -> event record +0x1C70. Same bijection and same sweep as `trailing_word_1`; `s4` -> `u4` on the same adjudication (2026-08-02)."
  - id: trailing_word_4
    type: u4
    doc: "[ELF] -> event record +0x1C74. Same bijection and same sweep as `trailing_word_1`; `s4` -> `u4` on the same adjudication (2026-08-02)."
  - id: trailing_word_5
    type: u4
    doc: |
      [ELF] -> event record +0x1C78, last 4 bytes of the packet. `s4` -> `u4` on the same
      adjudication as `trailing_word_1` (2026-08-02).

      **NONE OF THE SIX HAS A READER.** mgo2_cmd_4a24_s2c.ksy swept 0x8C0000-0x900000 and
      0xD30000-0xD70000 for loads at these six displacements plus the indexed form
      `addi rX,rY,7268`; re-run here binary-wide over the cached disassembly, in both the
      `lwz/lwa/lbz/lhz rX,7268(rY)` form and the `addi rX,rY,7268` pointer-walk form. The only
      matches are the three **writers** — `0xD5007C` (the shared 0x4A24/0x4A31 parser), `0xD5091C`
      (the 0x4A00 family) and `0xD5AF48` (here) — plus stack traffic off r1. Control: the identical
      sweep returns readers for the two slots that bracket this range, obj+0x1C40 (0x8CC41C,
      0x8CDA30) and obj+0x0DA (0x8CC450, 0x8CDA80, 0x8CDEB8, 0x8FB480), so the sweep works and the
      negatives are real.

      **Re-run independently 2026-08-02 (third reading)** over the cached disassembly, matching any
      load or `addi` at displacements 7268/7272/7276/7280/7284/7288 off a non-r1 base: exactly three
      hits per displacement — 0xD5007C, 0xD5091C and 0xD5AF48 (all `addi rX,rY,disp` feeding the
      read primitive's `r4`, i.e. writers) — plus stack traffic at 0xD89D4C-0xD89D54 off r1. The
      control at obj+0x1C40 returned its two readers (0x8CC41C, 0x8CDA30). Negatives reproduce.

      Withdrawn: "the five consecutive signed words look like a score/counter row". There are six,
      not five, they are not evidenced as signed, and the shape carries no information.
