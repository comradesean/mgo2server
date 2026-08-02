meta:
  id: mgo2_cmd_4a24_s2c
  title: "MGO2 0x4A24 - Tournament/Survival event detail record (server -> client)"
  endian: be
params:
  - id: round_count
    type: u2
    doc: |
      NOT A WIRE FIELD. The client takes the `rounds` count from its own state (the u16 at
      obj+0x0DC, read at 0xD4FEF0), which is `halves[3]` of this same layout as most recently
      stored. Declared as a parameter so a spec reader cannot mistake it for a length prefix.
      [ELF] It is the tournament's **round count**: obj+0x0DC is compared against obj+0x0E0
      (the current round) at 0x8CDB3C, and when they differ the screen prints lobby string 773,
      "Round %d of the tournament is complete." The hard ceiling is **8** - the parser memcpys
      exactly 128 bytes out of this array at 0xD50124 and 128/16 = 8 - so a server sending more
      than 8 overruns obj+0x1B70.
doc: |
  THE 0x4Axx SUBSYSTEM IS **TOURNAMENT / SURVIVAL** (identified 2026-08-02, ELF, tier 1), and
  0x4A24 carries its central record: the **event detail card** - name, settings, entrant list
  size, round count, current round, per-round bracket bitmaps and the final standings.
  Not ranking; COMMANDS.md's 2026-07-27 negative on that reading stands. The identification and
  its evidence are written out in full in mgo2_cmd_4a00_s2c.ksy; in brief, the block's only
  three c2s commands are 0x4A25 / 0x4A40 / 0x4A30, whose callers raise dialogs 5522 "Unable to
  cancel Survival.", 5376 "Unable to cancel Tournament." and 5409 "...Unable to acquire
  Tournament list.", and the screen that renders THIS record (getter 0xD4EA60) formats it with
  lobby strings 742 "The championship match has ended.\nWinning team: %s\nYour reward: %d",
  773 "Round %d of the tournament is complete.", 774/775/771/756.

  TIER. Tournament and Survival are post-launch content (Ver. 1.20 and Ver. 1.10). No available
  client build exercises 0x4A24, so **every statement here is tier 1, read from MGO2.elf, and
  cannot be raised to tier 2**. Nothing below is backed by a capture. Mapping is in scope;
  serving it in v1 is not.

  Evidence: GAME dispatcher 0xD387C8 (compare tree at 0xD38804), entry stub 0xD398F0 (which sets `li r4,0x4A24` and tail-calls the
  shared parser), parser 0xD4FB80.

  0x4A24 AND 0x4A31 SHARE ONE PARSER, 0xD4FB80, and it accepts no other id (`cmpwi 0x4A24` /
  `cmpwi 0x4A31` at 0xD4FBE4/0xD4FBF4, everything else bails). The id only selects which
  client object is validated (cr4 at 0xD4FC3C) - the READ SEQUENCE IS THE SAME FOR BOTH, so the
  two payload layouts are identical by construction, not by resemblance.

  SHARED RECORD - SETTLED 2026-08-02. Same layout, **different destinations**; both halves of
  that matter.
    * Same TYPE: one parser, one read sequence, one 7296-byte (0x1C80) struct shape. 0x4A31's
      arm memsets exactly 7296 bytes at 0xD4FCDC before parsing, which pins the size.
    * Different INSTANCE: the base is chosen at 0xD4FBFC-0xD4FC1C. 0x4A24 takes
      `addis r9,r27,1; addi r31,r9,-9264` = **session+0xDBD0** (it has its own getter,
      0xD4EA60). 0x4A31 takes `lwz r9,6404(session+0x10000); addis r9,r9,2; addi r31,r9,-22464`
      = **`*(u32*)(session+0x11904) + 0x1A840`**. Those are not the same address and not the
      same allocation, so this is the 0x4212/0x4682 outcome for the destination even though it
      is the 0x4905/0x4909 outcome for the layout.
    * They are also validated against different ids: 0x4A24's `obj_id` must equal **team+0x298**
      (0xD4FCEC calls the team getter 0xD491F8, 0xD4FCFC reads +0x298, mismatch -> -1106);
      0x4A31's must equal `*(ptr+0x26D08)`, the u32 the client itself put there when it sent
      0x4A30 (0xD50568 writes it, 0xD4FCC8 checks it).
    * Only 0x4A31 consumes a request slot: slot 87, checked at 0xD4FC4C and cleared to state 2
      at 0xD501E8. 0x4A24 checks no slot at all, so **0x4A24 is a server push, 0x4A31 is the
      reply to the client's 0x4A30**.

  0x4A00 IS THE THIRD PARTY, and it is bound to session+0xDBD0 by an identical base
  computation - the 0x4905/0x4909 standard of proof. Its parser tail computes
  `0xD51060: addis r25,r23,1` / `0xD51068: addi r31,r25,-9264`, byte-identical to 0xD4FC18/
  0xD4FC1C above. After parsing its own payload into the team record it RESETS and PRE-FILLS
  this record, and five of its wire fields land in the exact slots 0x4A24 fills from the wire:
  its `new_id`->obj+0x000 (this `obj_id`), its `flags`->obj+0x004 through the same `oris`
  ladder, its `unknown_last`->obj+0x005 (this `unknown_after_flags`), its `block`->obj+0x008
  (this `block`, memcpy 204 bytes at 0xD511B0) and its `unknown_after_block`->obj+0x1BF0
  (this `unknown_0x19`). It also seeds obj+0x1BF8/+0x1BFC/+0x1BFD from team+0x25C/+0x260/+0x261.
  **A server must keep those five consistent between 0x4A00 and 0x4A24** or the id check above
  fails and the client aborts with -1106.

  THE BIG CAVEAT: the length of the `rounds` array is NOT on the wire. The outer loop bound is
  a u16 the client already holds at obj+0x0DC (0xD4FEF0: `lhz r0,220(r9)`), which is the FOURTH
  of the eight u16s this same packet reads into obj+0x0D6..0x0E4 - i.e. the count is taken from
  client state, and if this packet is what most recently wrote that state then it is
  self-describing, but the parser reads the stored copy, not the freshly parsed one. Modelled
  below as a parameter so the dependency is explicit rather than guessed.
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
seq:
  - id: result
    type: u4
    doc: |
      [ELF] read at 0xD4FC70. MUST be 0: non-zero branches to 0xD50140, straight past RD_END,
      and NOTHING else in the payload is read. This is the one established field here.
  - id: obj_id
    type: u4
    doc: |
      [ELF] read at 0xD4FC94 and stored to obj+0x000 (0xD4FD28). **The event record id**, and it
      is validated before anything else is stored: 0xD4FCEC fetches the team record through
      0xD491F8 and 0xD4FCFC compares this against **team+0x298**, aborting with **-1106** on a
      mismatch. team+0x298 is the value 0x4A00 writes (0xD50FA8), so a server must echo here
      exactly what it sent as 0x4A00's `new_id`. It is also the id 0x4A02 / 0x4A22 / 0x4A29
      check (0xD4F050 / 0xD514D0 / 0xD50B88).
  - id: phase
    type: u1
    doc: |
      [ELF] read at 0xD4FD2C -> obj+0x0D4. **The event's phase / status code**, and the field
      that decides which screen the player gets. 0x8F95D8 loads it straight off this record and
      computes `(u8)(phase - 2) <= 8`: in range, the screen state is set to 14; out of range,
      to 26. So values **2..10 are the "live event" states** and everything else falls to the
      other branch. It is also the payload the sibling parser at 0xD50A44 hands to the screen
      event dispatcher 0xD33CD8 as event 21, i.e. the client re-broadcasts it as a
      state-changed notification. The individual code-to-phase assignments are [UNKNOWN] -
      nothing in the binary enumerates them, and no capture can, because no available client
      build reaches this command.
  - id: halves
    type: u2
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] eight u16, read by eight unrolled calls 0xD4FD48-0xD4FE0C into obj+0x0D6, +0x0D8,
      +0x0DA, +0x0DC, +0x0DE, +0x0E0, +0x0E2, +0x0E4. Four of the eight are read back; four are
      not. Sweep behind the negatives: every reader of this record obtains it either from the
      getter 0xD4EA60 (all call sites lie in 0x8CC398-0x8FB88C) or from the fixed session
      displacement in the network library (0xD44DC8-0xD5B1A0), so the swept windows are
      0x8C0000-0x900000 and 0xD30000-0xD70000, filtered to `lhz` because these are u16.
      Controls that DID come back: 0x0DA, 0x0DC, 0x0E0 below, plus obj+0x1BF8/+0x1BFC/+0x1BFD
      and obj+0x1C40. So the sweep works and the empty results below are real.

        [0] obj+0x0D6 - [INFERRED] **entrant capacity / cap on the entrant table.** Read only
            at 0xD520E8 and 0xD526C8, both in sibling 0x4Axx parsers, and in both it is the
            upper bound of an append: `if (halves[0] > count) { count++; store the new 52-byte
            entrant record }`. Reading it as a capacity is the only construction that fits, but
            the two readers write a *different* object's table, so this is inference from the
            use, not a bijection.
        [1] obj+0x0D8 - **no reader.** Nothing loads a u16 from +0x0D8 anywhere in either swept
            window.
        [2] obj+0x0DA - [ELF] **number of entrants**, i.e. the live length of the 128-entry,
            52-byte-stride table at obj+0x0F0. It is the bound of the slot accessor 0xD51CF4
            (`if (index >= halves[2]) return NULL; return obj + 0xF0 + 52*index`) and of the
            display loops at 0x8CC450, 0x8CDA80, 0x8CDEB8, 0x8FB480 and 0xD50A28.
        [3] obj+0x0DC - [ELF] **round count**; see the `round_count` parameter. Also copied to
            the automatch object at +0x0C by the sibling parser at 0xD509E8.
        [4] obj+0x0DE - **no reader.**
        [5] obj+0x0E0 - [ELF] **current round.** It is the `%d` of lobby string 773, "Round %d
            of the tournament is complete." (0x8CDB3C-0x8CDB58), and it selects which row of
            `rounds` the bracket renderer reads (0x8CDC8C, 0x8FB23C). Also copied to the
            automatch object at +0x10 (0xD509F0).
        [6] obj+0x0E2 - **no reader.**
        [7] obj+0x0E4 - **no reader.**

      Note that 0x4A00 zeroes [0]..[5] at 0xD51194-0xD511AC and a sibling parser (0xD519C4)
      writes [0], [1], [6] and [7] - so the four unread ones are live state somewhere, just not
      state this client displays.
  - id: unknown_0x19
    type: u4
    doc: |
      [UNKNOWN] read at 0xD4FE24 and widened to 64 bits at obj+0x1BF0. The widening is what a
      time_t looks like on this target (compare mgo2_cmd_4902.ksy open_time), and a scheduled
      start time would fit a tournament record, but that remains a guess - **no reader at all.**
      Swept 0x8C0000-0x900000 and 0xD30000-0xD70000 for any load at displacement 7152, and
      binary-wide as a backstop: three stores (0xD4FE44 here, 0xD507D4 and 0xD5127C in siblings)
      and zero loads outside stack frames. Control: the same sweep found the readers of
      obj+0x1BF8/+0x1BFC/+0x1BFD immediately below.
      [ELF] Cross-packet bijection: 0x4A00's `unknown_after_block` writes this exact slot
      (0xD5127C, `std r0,7152(r29)` with r29 = session+0xDBD0). Same field, two commands.
  - id: lobby_id
    type: u4
    doc: |
      [ELF] read at 0xD4FE48 -> obj+0x1BF8. **The lobby id** the event runs in. Named by
      struct-offset bijection, not resemblance: 0x4A00's parser tail copies **team+0x25C** into
      this same slot at 0xD511B8, and dev/docs/AUTOMATCH.md already resolved team+0x25C as the
      lobby id (0x43F1 wire +0x04). The same three-field block is copied on to the automatch
      object at 0xD512A8 as +0x04.
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF] read at 0xD4FE64 -> obj+0x1BFC. **The lobby subtype.** Same bijection: 0x4A00 copies
      **team+0x260** here (0xD511C0), which AUTOMATCH.md resolves as the subtype, with
      **3 = Tournament, 4 = Survival, 5 = Official Tournament** (read from the disc string
      resources, section 10). Corroborated from the other direction by the 0x4A25 caller at
      0x8CCD8C, which tests the subtype byte for == 4 to choose between the Survival sentence
      (dialog 5522) and the Tournament one (dialog 5376).
  - id: rule_id
    type: u1
    doc: |
      [ELF] read at 0xD4FE80 -> obj+0x1BFD. **The game rule id**, same enum as 0x4310's rotation
      rule. Bijection: 0x4A00 copies **team+0x261** here (0xD511C8), and AUTOMATCH.md records
      team+0x261 as the rule id, read as a rule at four sites via `strres(0x654515, 2*rule)`.
  - id: lobby_name
    size: 64
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF] 64-byte raw read (0xD4FEA4) -> obj+0x1BFE. **The lobby / event name.** Previously
      typed a string on width alone; it now has positive evidence. 0x4A00 fills the same slot
      without a wire field for it: at 0xD511E4-0xD51214 it walks the client's own lobby list,
      matches each entry's id against obj+0x1BF8 (`lobby_id`), and on a hit memcpys **64 bytes
      from entry+27** into obj+0x1BFE (0xD50F34). A 64-byte field that the client will
      reconstruct from a lobby-list entry's name is a name.
  - id: rounds
    type: round_bits
    repeat: expr
    repeat-expr: round_count
    doc: |
      [ELF] outer loop 0xD4FEB8-0xD4FF04, stride 16 into obj+0x1AF0, bound `halves[3]` READ
      FROM CLIENT STATE at obj+0x0DC (0xD4FEF0), not from this packet's parse buffer. See the
      caveat in the top-level doc.
      [ELF] **One row per round, and each row is a 128-bit bitmap over the entrant table.** The
      bracket renderer at 0x8CDC84 (and its second copy at 0x8FB234) addresses it as
      `obj + 0x1AF0 + 4*(4*halves[5] + slot/32)`, bit `slot & 31` - i.e. row = the current
      round, bit = the entrant's index in the obj+0x0F0 table, which caps entrants at 128 and
      matches the 128x52 = 6656-byte table 0x4A00 clears at 0xD5121C. **Max 8 rows**: the
      parser memcpys exactly 128 bytes of this array to obj+0x1B70 at 0xD50124.
      That second copy is what the renderer diffs against - for adjacent slots i and i+1 it
      requires the bit set in one array and clear in the other before it draws a matchup, so
      the pair encodes a per-round transition. Which of the two is "before" and which is
      "after" is [UNKNOWN]; only the diff is observable.
  - id: standings
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] exactly 8 u32, loop 0xD4FF0C-0xD4FF3C (`cmpdi r29,8`) -> obj+0x1C40 + 4*i. Fixed
      count.
      [ELF] **`standings[0]` is the winning team's id.** Two independent sites - 0x8CC414 and
      0x8CDA2C - scan the 52-byte entrant table for the entry whose id at +0x00 equals
      obj+0x1C40, copy that entry's 32-byte name, and feed it as the `%s` of lobby string 742,
      "The championship match has ended.\nWinning team: %s\nYour reward: %d".
      **`standings[1..7]` have no reader.** Swept both windows for loads at displacements
      7236/7240/7244/7248/7252/7256/7260 and for the indexed form `addi rX,rY,7232`: the only
      hits are the two writers (this parser at 0xD4FF14 and 0x4A28's at 0xD50DCC) plus one
      unrelated struct at 0x412B48ff. Control: the same sweep found both readers of
      `standings[0]` named above. Runner-up placings are the obvious reading of a fixed 8-slot
      array beside a winner, but nothing in this build displays them, so it stays [INFERRED].
      Note also that string 742's `%d` comes from obj+0x1C60, which **this packet does not
      write** - the sibling 0x4A28 does (0xD50E04), which is also the only other writer of
      `standings`.
  - id: flags
    type: u1
    doc: |
      [ELF] 1-byte raw read (0xD4FF50) expanded bit by bit into the 64-bit word at obj+0x000 by
      the `oris` ladder at 0xD4FF60-0xD50044; each bit a distinct boolean. The eight bits all
      land in the single byte **obj+0x004**, bit-reversed - wire bit 0 becomes bit 7 (`oris`
      0x8000), wire bit 7 becomes bit 0 (`oris` 0x0100) - and the `ld`/`std` pair leaves
      obj+0x000..0x003 (the record id) untouched.
      No consumer identified for any of the eight. [UNKNOWN] individually. 0x4A00's `flags`
      byte drives the identical ladder into the identical word (0xD5105C-0xD51144), so whatever
      the bits mean, the two commands must agree on them.
  - id: unknown_after_flags
    type: u1
    doc: |
      [UNKNOWN] read at 0xD50050 -> obj+0x005. **No reader**: swept 0x8C0000-0x900000 and
      0xD30000-0xD70000 for a `lbz` at displacement 5 off any register holding this record, and
      binary-wide for displacement 5; nothing resolves to this object. Control: the same
      windows yield obj+0x0D4's reader at 0x8F95D8 one byte-field away in the same struct.
      [ELF] 0x4A00's `unknown_last` writes this exact slot (0xD51148/0xD51154), so it is one
      field shared by two commands.
  - id: block
    type: block_204
    doc: |
      [ELF] the shared 204-byte sub-record, read by 0xD4364C (called at 0xD5006C) into
      obj+0x008. Same block 0x4A00 embeds - and literally the same destination: 0x4A00 memcpys
      its own copy into obj+0x008 at 0xD511B0. In this subsystem it is **the event's game
      settings**: rule, map rotation and the weapon-restriction bitfield the tournament runs
      under. See mgo2_cmd_4313_s2c.ksy, which remains canonical.
  - id: trailing_words
    type: u4
    repeat: expr
    repeat-expr: 6
    doc: |
      [ELF] six u32, unrolled 0xD50088-0xD50114 -> obj+0x1C64, +0x1C68, +0x1C6C, +0x1C70,
      +0x1C74, +0x1C78. [UNKNOWN] meanings, and **none of the six has a reader.** Swept
      0x8C0000-0x900000 and 0xD30000-0xD70000 for loads at those six displacements, plus a
      binary-wide backstop and the indexed form `addi rX,rY,7268`: the only matches are this
      parser, the sibling parser at 0xD5091C, 0x4E10's at 0xD5AF48, an unrelated struct at
      0x412B80ff, and stack traffic off r1. Control: the identical sweep found the readers of
      obj+0x1C40 and obj+0x1C60, which bracket this range. Written by two commands, read by
      none - so these are the last six fields of the record and currently inert in this build.
types:
  round_bits:
    doc: |
      [ELF] 16 bytes: four u32, read by the inner loop at 0xD4FECC (`cmpwi r29,3`). One round's
      **128-bit entrant bitmap** - bit `n` is entrant `n` of the obj+0x0F0 table. See the
      `rounds` doc for the addressing that proves the bit-per-entrant reading.
    seq:
      - id: bits
        type: u4
        repeat: expr
        repeat-expr: 4
        doc: "[ELF] four u32 = 128 bits, one per entrant slot; word i covers slots 32*i..32*i+31, LSB first (`slw` at 0x8CDCC4)."
  block_204:
    doc: |
      [ELF] The 204-byte sub-record read by the shared helper 0xD4364C. That helper has NINE
      call sites, not just this family: 0xD445A4 (0x4313), 0xD48440 (0x4905), 0xD48964 (0x4909),
      0xD4B244 (0x4987), 0xD4CB08 (0x4950), 0xD5006C (the shared 0x4A24/0x4A31 parser),
      0xD51014 (0x4A00), 0xD5AF38 (0x4E10), 0xD5B78C (0x43F1).
      **CANONICAL MODEL: mgo2_cmd_4313_s2c.ksy, type `game_settings`.** That copy is the
      best-evidenced one - same 204 bytes, same reader, but its field names are backed by live
      capture (the 0x4310 push and the 0x4305 reply, OBSERVED.md). This type is a byte-accounting
      mirror; where the two disagree, 0x4313 wins. Enumerated read-by-read from
      0xD4364C-0xD43BC0.

      ## THE BIJECTION IS PROVEN, AND THE NAMES ARE NOW TRANSFERRED (2026-08-02)

      The old caveat here - "whether the game-settings meanings carry over to a 0x4Axx record is
      [UNKNOWN]" - overstated the doubt about *layout* and understated the one about *liveness*.
      Both halves are now stated precisely.

      **Layout: identical by construction, not by analogy.** 0xD4364C is ONE function. Its
      destination base is `r29`, the block pointer, and every field is written at a literal
      displacement off it. Disassembling 0xD4364C-0xD43BC0 gives exactly this displacement list,
      and it is the same list whichever call site supplied `r29`:

          0..47   3x u8 per iteration, 16 iterations   (0xD4368C / 0xD436B0 / 0xD436D0)
          48 u8   49 u8   50 raw16   66 u8   67 u8   68 u32   72 u32   76 u32
          80 u16  82 u16  84 u32     88 u32  92 u16   94 u8    95 u8
          96..164 u32 x18 (unrolled)
          168 raw2  170 u16  172 u32  176 u8  177 raw2  179 u8
          180 u16   182 u16  184 u32  188 u8  189 u8    190 raw14   = 204 total

      `mgo2_cmd_4313_s2c.ksy` type `game_settings` transcribes the same list from the same
      function. So the two types are the same struct at the same offsets with the same widths;
      there is no wire position at which they could disagree. Field ids below are the canonical
      ones wherever the canonical file draws a boundary this type also draws.

      **Names: tier 2 on the struct, never tier 2 on this packet.** The names come from the
      capture-proven 0x4310 push and 0x4305 reply of the SAME 204 bytes (OBSERVED.md, and the 214
      archived payloads in `../samples/4310/captures.psv`). No available client build sends or
      receives a 0x4Axx command, so nothing here can be raised to tier 2 *for this command*. Read
      every name below as: offset and width [ELF]; name [INFERRED] from a capture of the same
      struct carried by a different command.

      **What deliberately does NOT transfer: the "no reader in the image" verdicts.** The
      canonical file's negatives (block +72, +76, +80, +82, +84, +88, +92, +170, +172) were
      established against the **game-details object**, where the block sits at struct +752 and the
      sweep could use marker offsets 802/818/819/846/847/940/941 to tell that object from every
      other. In this family the block lands somewhere else entirely - the team record at
      team+0x0B0 for 0x4A00, and session+0xDBD0+0x008 / `*(u32*)(session+0x11904)+0x1A840+0x008`
      for 0x4A24/0x4A31 - so those displacements are different numbers and the sweep does not
      carry across. **Liveness is a property of the carrier, not of the layout.** No negative is
      claimed here for any field on the strength of the canonical file's negative; where one is
      claimed below it is claimed for this family's own destination.
    seq:
      - id: triples
        type: triple
        repeat: expr
        repeat-expr: 16
        doc: |
          [ELF] 16 iterations of three u8 reads (0xD4368C / 0xD436B0 / 0xD436D0, bound
          `cmpdi r27,16` at 0xD436D8). The three bytes are stored into three SEPARATE 16-byte
          arrays at block+0x00, block+0x10 and block+0x20 - i.e. the wire is interleaved
          (a[i], b[i], c[i]) and the struct is column-major. Getting this backwards would put
          48 bytes of anything in the wrong place while still parsing.
      - id: unknown_0x30
        type: u1
        doc: |
          [UNKNOWN - meaning] 0xD436F4 -> block+0x30 (block +48). Offset and width [ELF].

          **No name exists to transfer** - the canonical `mgo2_cmd_4313_s2c.ksy` carries this
          byte as `unknown_48` too, so this is a field the whole campaign leaves unnamed rather
          than one this mirror has not caught up with. What IS known travels with the byte and is
          recorded here so the gap is explicit rather than blank:

          - **In the game-details carrier it is published and then read by nothing.** `0x8CA460`
            copies struct+800 to a scratch byte and `0x8CA6F0` publishes the scratch as client
            property-store key 86, an 8-byte record of which only bytes 1 and 5 are ever filled
            (this field and `unknown_0x31`). The two ELF-side readers of those bytes, `0x7F4C98`
            and `0x7F4C50`, are **dead code** - no `bl`, and their OPDs are absent from the GCX
            native table while their immediate neighbours' are present. Full working in
            `mgo2_cmd_43f1_s2c.ksy` under `unknown_48`.
          - **Nothing in the create-game UI writes it**, so it is server-authoritative and simply
            round-trips through the client's own 0x4310.
          - **Capture value: 0x00 in all 214 archived 0x4310 payloads** (`../samples/4310`,
            hex chars 423-424). It has never been observed nonzero.

          Whether any of that holds for a Tournament/Survival record is **not claimed** - see the
          liveness note in the type doc above. The pairing with `unknown_0x31` is structural and
          does carry: they are two elements of one array in every carrier.
      - id: unknown_0x31
        type: u1
        doc: |
          [UNKNOWN - meaning] 0xD43710 -> block+0x31 (block +49). Offset and width [ELF].
          Canonical `unknown_49`; no name exists to transfer.

          Element 1 of the pair described under `unknown_0x30` - `0x8CA468` publishes it as key 86
          byte 5, its only ELF reader `0x7F4C50` is uncalled and unregistered, and no UI widget
          writes it. **Capture value: 0x00 in all 214 archived 0x4310 payloads** (hex chars
          425-426). Same carrier caveat as `unknown_0x30`.
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] 16-byte raw read (0xD43730) -> block+0x32. **Not a string.** An earlier
          revision typed this `str text_0x32`, "string role from the width and 0xD5D018's NUL
          behaviour only" - inferred from width alone, against capture evidence that already
          existed. It is the weapon-restriction bitfield: one bit per item, 1 = locked, byte 0
          bit 0 the master enable, confirmed weapon by weapon (nineteen for nineteen) by the
          2026-07-22 single-variable sweep at 0x4310 wire 0xD5..0xE4 (OBSERVED.md). 0x4310's
          copy of this block starts at wire 0xA3 and 0xA3 + 0x32 = 0xD5. See
          mgo2_cmd_4313_s2c.ksy for the full bit map and the corroborating offsets.
      - id: max_players
        type: u1
        doc: |
          [ELF offset+width 0xD43744 -> block+0x42 (66); name INFERRED from capture]
          **Maximum player count.** Renamed from `unknown_0x42` 2026-08-02 by struct-offset
          bijection with `mgo2_cmd_4313_s2c.ksy` `max_players`, which is capture-proven at 0x4310
          wire 0xE5 (0xA3 + 0x42, no omitted field before it). 214 archived payloads read 0x10 =
          16 in 176 of them, 0x02/0x03/0x11 in the other 38 - i.e. a small player count, which is what
          the name says.
      - id: player_count
        type: u1
        doc: |
          [ELF offset+width 0xD43760 -> block+0x43 (67); name INFERRED from capture]
          **Current player count.** Renamed from `unknown_0x43` 2026-08-02.

          The one live-session field in the block, and the identification is a negative that
          happens to be sharp: 0x4305 (saved settings) and 0x4310 (host push) both omit **exactly
          this byte** and nothing else in this region, which is what a "current" field looks like
          in a saved-settings reply. The client validator at `0x883FB4` rejects zero here in the
          game-details carrier. Whether a Tournament/Survival record validates it is not claimed.
      - id: words_0x44
        type: u4
        repeat: expr
        repeat-expr: 3
        doc: |
          [ELF] 0xD4377C / 0xD43790 / 0xD437AC -> block+0x44, +0x48, +0x4C (68, 72, 76), three
          consecutive u32 reads through the same primitive 0xD5CCD8.

          **The array id is kept, but the three elements are individually identified** by
          bijection with `mgo2_cmd_4313_s2c.ksy` - splitting the declaration is not permitted
          here, so the mapping is written out instead:

              words_0x44[0]  block +68  `briefing_time` - capture-proven at 0x4310 wire 0xE6;
                                        the create-game adjuster at 0x8A6D14-0x8A6E74 clamps it
                                        to about [0,30] with a +/-30 jump, and 0x8CA588 publishes
                                        it as property-store key 96.
              words_0x44[1]  block +72  canonical `unknown_72`. **A genuine u32**, not a u8 with
                                        padding: parser 0xD43784 uses the u32 reader and the
                                        0x4310 builder 0xD449C8 the u32 writer. Meaning
                                        [UNKNOWN]. Captures read 0x02000000 in 182 of 214
                                        and 0x00000000 in 32, and that split is exactly the
                                        split of `common_flags_lsb` - the two never disagree.
              words_0x44[2]  block +76  canonical `unknown_76`. [UNKNOWN], and not carried by
                                        0x4310 or 0x4305 at all - this family and 0x4313/0x43F1
                                        are the only ways to set it.
      - id: half_0x50
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD437C8 -> block+0x50 (80). Canonical `unknown_80`; **no name
          exists to transfer**. Width [ELF]: the u16 reader 0xD5CC14, not a u32 half.
          Capture value 0x0000 in all 214 archived 0x4310 payloads.
      - id: half_0x52
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD437E4 -> block+0x52 (82). Canonical `unknown_82`; no name to
          transfer. Width [ELF] **twice**: u16 reader 0xD5CC14 here, and an independent
          compiler-emitted `lhz r3,834(r3)` in the game-details accessor bank at 0x907784 - a
          dead accessor still declares a width. Not carried by 0x4310 or 0x4305.
      - id: word_0x54
        type: u4
        doc: |
          [UNKNOWN - meaning] 0xD43800 -> block+0x54 (84). Canonical `unknown_84`; no name to
          transfer. Width [ELF] u32 reader 0xD5CCD8. Capture value 0x00000000, 214 of 214.
      - id: word_0x58
        type: u4
        doc: |
          [UNKNOWN - meaning] 0xD4381C -> block+0x58 (88). Canonical `unknown_88`; no name to
          transfer. Width [ELF] twice: u32 reader 0xD5CCD8, and `lwz r3,840(r3)` in the dead
          game-details accessor bank at 0x90775C. Not carried by 0x4310 or 0x4305.
      - id: half_0x5c
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD43838 -> block+0x5C (92). Canonical `unknown_92`; no name to
          transfer. Width [ELF] u16 reader 0xD5CC14. Capture value 0x0000, 214 of 214.
      - id: host_stance
        type: u1
        doc: |
          [ELF offset+width 0xD43854 -> block+0x5E (94); name CONFIRMED from the binary's own
          symbol table] **The host stance** - renamed from `unknown_0x5e` 2026-08-02.

          This one is better than an inferred transfer: the client carries a developer name table
          at **0xE1BC48**, nine NUL-padded 20-byte entries reading `HOST_STANCE_EASY`,
          `HOST_STANCE_REAL`, `HOST_STANCE_BEGINNER`, `HOST_STANCE_EVERYONE`, `HOST_STANCE_OTHER`,
          `HOST_STANCE_TRAINING`, `HOST_STANCE_INSTRUCTOR_ENTRY`, `HOST_STANCE_INSTRUCTOR_STARTED`,
          `HOST_STANCE_NONE` - ids 0..8, with the client range-gating the value `cmplwi 9 / bgt`
          at 0xA31230. In the game-details carrier 0x8CA580 publishes it as property-store key 94
          and 0xD49530 copies it into a 0x4302 game-list row at T+0x24, which that spec also calls
          stance. Archived 0x4310 payloads carry 0, 2, 5 and 6.
      - id: level_limit_tolerance
        type: u1
        doc: |
          [ELF offset+width 0xD43868 -> block+0x5F (95); name INFERRED from capture]
          **The level-limit tolerance**, in LEVELS, applied as `base +/- tolerance` around
          `words_0x60[0]`. Renamed from `unknown_0x5f` 2026-08-02.

          Capture-proven at 0x4310 wire 0xF7, immediately before the level-limit base at 0xF8
          (OBSERVED.md 2026-07-22). The game-details carrier corroborates from two directions:
          0x8CA544 publishes it as property-store key 98, right beside key 99 = the base, and the
          game picker at 0x93452C-0x93455C tests a candidate's level against entry+38 as a
          tolerance around entry+40. 211 of 214 archived payloads read 0x16 = 22, the level cap.
      - id: words_0x60
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: |
          [ELF] 18 consecutive u32 reads, 0xD43884 through 0xD43A60 -> block+0x60..+0xA4
          (96..164). Unrolled in the binary, not a loop, so there is no count field.

          **The 1 + 17 split is real and both halves are identified.** The array id is kept
          because splitting a declaration is not permitted here; the mapping is:

              words_0x60[0]   block +96   `level_limit_base`, a u32 in LEVELS. Capture-proven at
                                          0x4310 wire 0xF8 by the 2026-07-22 single-variable
                                          sweep; published as property-store key 99.
              words_0x60[1..17] block +100..+164  the **per-rule timer / round / ticket table**,
                                          in the order SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets,
                                          DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r.

          The ordering is not inherited from a reference server. Two independent sites in this
          binary produce it: 0x8CA470-0x8CA4CC multiplies exactly eight of the seventeen by 60
          before publishing them, and those eight are indices {9,6,4,2,0,11,13,15} - precisely the
          time slots under this ordering, with no count scaled and no time left unscaled; and the
          tournament RULE DETAIL panel at 0x901808 selects the same pairs by an 8-way jump table
          on the record's rule byte and formats them with `%d分` / `%d回` / `%d枚` into widgets
          named `NULL_tournamentrule_time` / `_round` / `_ticket`. That second site reads the
          block through a **0x4909 tournament record**, which is the nearest thing this family has
          to a same-carrier confirmation.

          Note the Sneaking "defeat Snake N times" figure is NOT in this array - it is
          `sneaking_snake_kills` at block+0xBD.
      - id: pair_0xa8
        size: 2
        doc: |
          [ELF] 2-byte raw read (0xD43A80) -> block+0xA8 (168). Read as raw with r5=2, **not** as a
          u16, so the parser draws no boundary between the two bytes; the declaration is kept raw
          for that reason.

          The client itself does split them: in the game-details carrier 0x8CA5C0 and 0x8CA5C8
          load struct+920 and +921 as two separate `lbz` and 0x8CA87C publishes the pair as a
          2-byte property-store record, **key 134**. The canonical file names them
          `unique_red` / `unique_blue`, and that name is **tier 4 and doubtful** - unique
          characters were absent from this build's UI and untestable (OBSERVED.md). The archived
          captures argue against it as a per-team setting: **all 214 read `00 01`**, never any
          other combination, which is a constant rather than a pair of independently chosen team
          values. Meaning [UNKNOWN]; the observed value is not.
      - id: half_0xaa
        type: u2
        doc: |
          [UNKNOWN - meaning] 0xD43A9C -> block+0xAA (170). Canonical `unknown_170`; **no name
          exists to transfer**. Width [ELF] twice: u16 reader 0xD5CC14, and `lhz r3,922(r3)` in
          the dead game-details accessor bank at 0x9074B4. That accessor is separate from the
          indexed getter at 0x907174 which walks `920 + idx`, so this halfword is outside the
          `pair_0xa8` pair rather than a third element of it. Not carried by 0x4310 or 0x4305.
      - id: word_0xac
        type: u4
        doc: |
          [UNKNOWN - meaning] 0xD43AB8 -> block+0xAC (172). Canonical `unknown_172`; no name to
          transfer. Width [ELF] twice: u32 reader 0xD5CCD8, and `lwz r3,924(r3)` in the dead
          game-details accessor bank at 0x90748C. Not carried by 0x4310 or 0x4305.
      - id: common_flags_msb
        type: u1
        doc: |
          [ELF offset+width 0xD43AD4 -> block+0xB0 (176); name ELF-derived] The **most
          significant byte of the 32-bit Common Settings flags word**. Renamed from
          `unknown_0xb0` 2026-08-02.

          The word is the big-endian u32 at struct+928 in the game-details carrier, i.e. this byte
          then `common_ab` then `common_flags_lsb`: bits 31..24 here, 23..16 = `common_ab[0]`,
          15..8 = `common_ab[1]`, 7..0 = the lsb byte. 117 sites image-wide do
          `lwz rX,928(rB)` and bit-test the result, and **every tested bit lies in 8..23**, so no
          bit this byte owns is consumed anywhere. The name says what the byte IS; what a set bit
          would mean is [UNKNOWN].

          The bit-extraction arithmetic, since it is easy to get backwards: the tests are
          `rldicl. rX,r0,sh,63`, which selects LSB index `64 - sh` for the `sh` values 41..56 used
          at 0x8CA2BC-0x8CA420 (so those fifteen tests cover bits 8..21 and 23). Control: `sh=49` gives bit 15, and bit 15 is independently the one
          the create-game team-kill row sets and clears with `ori 32768` / `rlwinm 16,1,31` at
          0x8A5FA0-0x8A5FAC.
      - id: common_ab
        size: 2
        doc: |
          [ELF] 2-byte raw read (0xD43AF4) -> block+0xB1 (177). Renamed from `pair_0xb1`
          2026-08-02. **The two live Common Settings toggle bytes**, `common_a` then `common_b` in
          the canonical file - bits 23..16 and 15..8 of the flags word described under
          `common_flags_msb`. Capture-proven at 0x4310 wire 0x142 / 0x143 (the offsets are
          confirmed; the individual bits are not all identified).

          Kept as one raw 2 because that is how the parser reads it, and because the 0x4310
          builder and the 0x4302 row builder both copy the same two bytes as a unit.

          Archived values: `common_a` is 0x24 in 149 payloads, 0x2c in 63, with 0x25 and 0x34 once
          each; `common_b` is 0x00 in 170 and nonzero in 44, the 26 training-lobby captures among
          them. `common_a` bit 0 is the idle-kick enable - the single capture with
          `common_a = 0x25` is also the single capture with a nonzero `half_0xb4`, 214 for 214.
      - id: common_flags_lsb
        type: u1
        doc: |
          [ELF offset+width 0xD43B10 -> block+0xB3 (179); name ELF-derived] The **least
          significant byte** (bits 7..0) of that same 32-bit flags word. Renamed from
          `unknown_0xb3` 2026-08-02.

          It has its own u8 read here, distinct from the raw-2 covering `common_ab`, and the
          0x4310 builder splits the same way - so the four-byte word is three separate wire
          fields, not one. **Bits 0-7 are never tested** by any of the 117 flag-word sites, and
          the only load of struct+931 in the game-details carrier is the dead accessor 0x9072AC.

          Archived captures read 0x20 in 182 payloads and 0x00 in 32, and the split is **exactly**
          the split of `words_0x44[1]` (0x02000000 vs 0x00000000) - 214 for 214, the two fields
          never disagree. All 26 captures from lobby subtypes 7 and 8 (training) are in the zero
          group, plus six from subtypes 0 and 1. So the byte covaries with something about the
          session despite having no reader, which is a reason to echo it rather than invent it.
          Meaning [UNKNOWN].
      - id: idle_kick
        type: u2
        doc: |
          [ELF offset+width 0xD43B2C -> block+0xB4 (180); name INFERRED from capture]
          **The idle-kick threshold, in MINUTES.** Renamed from `half_0xb4` 2026-08-02.

          The unit is read from the binary, not guessed: in the game-details carrier 0x8CA424
          loads struct+932 and 0x8CA458 multiplies it by 60 before 0x8CA63C publishes it as
          property-store key 76. It is gated by `common_ab[0]` bit 0 - and that gate is confirmed
          by capture, 214 for 214: the one archived payload with `common_a = 0x25` is the one with
          a nonzero value here (3), and all 213 with bit 0 clear read 0x0000.
      - id: team_kill_kick
        type: u2
        doc: |
          [ELF offset+width 0xD43B48 -> block+0xB6 (182); name INFERRED from capture]
          **Team kills tolerated before a kick.** Renamed from `half_0xb6` 2026-08-02.

          Published as property-store key 69 at 0x8CA534/0x8CA608 - and note the client truncates
          there, `stb` after an `lhz`, so its own downstream copy cannot exceed 255 even though the
          wire field is 16 bits.

          **A gating claim that the captures REFUTE, recorded so it is not re-derived.** The
          create-game screen keeps flags-word bit 15 in step with this field (0x8A5F90-0x8A5FB0
          sets it when the count is nonzero and clears it when zero), which invites the reading
          that a clear bit 15 makes a nonzero count inert. It does not: 170 of the 214 archived
          0x4310 payloads carry `common_b = 0x00` - bit 15 clear - **with this field = 3**, and
          the publisher at 0x8CA534 copies the value out with no bit test at all. The invariant is
          local to that one screen. The canonical file's "zeroed when commonB bit 7 is clear" is
          therefore too strong; its `idle_kick` counterpart is not.
      - id: host_ping
        type: u4
        doc: |
          [ELF offset+width 0xD43B64 -> block+0xB8 (184); name ELF-derived, unit UNKNOWN]
          Renamed from `word_0xb8` 2026-08-02. **Not carried by 0x4310 or 0x4305**, so this
          family, 0x4313 and 0x43F1 are the only ways to set it and there is no archived capture
          of it.

          In the game-details carrier the hosted-game row synthesiser 0xD493CC does
          `lwz r0,936(r31)` at 0xD49548 and stores it at the row's T+0x20, which
          `mgo2_cmd_4302_s2c.ksy` calls `ping` and which the game picker at 0x934574-0x934590
          buckets against 20 and 80, preferring lower. **What is proven is the destination slot,
          not a unit** - and whether a Tournament/Survival record feeds that synthesiser at all is
          not claimed here.
      - id: capture_extra_time
        type: u1
        doc: |
          [ELF offset+width 0xD43B80 -> block+0xBC (188); name CONFIRMED from disc strings]
          **Capture Mission "EXTRA TIME"** - extend the round until a victor emerges. Renamed from
          `unknown_0xbc` 2026-08-02.

          A plain toggle: handler 0x8A02B4 is `x = x ? 0 : 1`, drawn as disc string 33 "ON" / 34
          "OFF", row label 507 "EXTRA TIME" under header 498 "Capture Mission", help 541
          *"Enabling this adds extra time to the end of the round until a victor emerges."*
          Published as property-store key 132. Archived captures read 0 in 207 and 1 in 7.
      - id: sneaking_snake_kills
        type: u1
        doc: |
          [ELF offset+width 0xD43B9C -> block+0xBD (189); name CONFIRMED from disc strings]
          **Sneaking Mission "SNAKE"** - how many times Snake must be defeated for Red and Blue to
          win. Renamed from `unknown_0xbd` 2026-08-02.

          It is a count, not a side index: 0x89D7B8 renders it as a number and the create-game
          adjuster 0x8A1AC8 clamps it to [1,5], where a side would be 0/1/2 drawn as a name. Disc
          row label 508 "SNAKE", units 520 "times", help 542 *"Set the number of times Snake must
          be defeated (victory condition for Red and Blue Teams)."* Published as property-store
          key 131. Archived captures read 3 in 175 of 214, then 5 (17), 2 (13) and 1 (9).
      - id: unread_tail
        size: 14
        doc: |
          [ELF] 14-byte raw read (0xD43BBC) -> block+0xBE (190..203). Last field; the block ends at
          0xCC = 204. Renamed from `tail_0xbe` 2026-08-02, matching the canonical file.

          **One raw read, so the parser draws no field boundaries in it at all**, and in the
          game-details carrier the client never reads or writes any byte of it: three touch points
          image-wide, the 0x4310 builder emitting it, the 0x4305 parser reading it, and the
          create-game initialiser memsetting it to zero at 0x89B5E8. All 214 archived payloads
          carry it entirely zero.

          PROTOCOL.md's subdivision of this region - byte-sized timers for Stealth DM, Interval,
          Solo Capture and Race - is a reference-server reading naming modes whose strings do not
          exist on this disc, and is **not** adopted. Splitting it needs live divergence testing,
          which no available build can do for a 0x4Axx command.
  triple:
    seq:
      - id: a
        type: u1
        doc: "[UNKNOWN] -> block+0x00+i"
      - id: b
        type: u1
        doc: "[UNKNOWN] -> block+0x10+i"
      - id: c
        type: u1
        doc: "[UNKNOWN] -> block+0x20+i"
