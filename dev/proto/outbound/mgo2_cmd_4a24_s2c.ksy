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
      0xD4364C-0xD43BC0. Size is certain; whether the game-settings meanings carry over to a
      0x4Axx record is [UNKNOWN], the byte boundaries are not.
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
        doc: "[UNKNOWN] 0xD436F4 -> block+0x30."
      - id: unknown_0x31
        type: u1
        doc: "[UNKNOWN] 0xD43710 -> block+0x31."
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
      - id: unknown_0x42
        type: u1
        doc: "[UNKNOWN] 0xD43744 -> block+0x42."
      - id: unknown_0x43
        type: u1
        doc: "[UNKNOWN] 0xD43760 -> block+0x43."
      - id: words_0x44
        type: u4
        repeat: expr
        repeat-expr: 3
        doc: "[UNKNOWN] 0xD4377C / 0xD43790 / 0xD437AC -> block+0x44, +0x48, +0x4C."
      - id: half_0x50
        type: u2
        doc: "[UNKNOWN] 0xD437C8 -> block+0x50."
      - id: half_0x52
        type: u2
        doc: "[UNKNOWN] 0xD437E4 -> block+0x52."
      - id: word_0x54
        type: u4
        doc: "[UNKNOWN] 0xD43800 -> block+0x54."
      - id: word_0x58
        type: u4
        doc: "[UNKNOWN] 0xD4381C -> block+0x58."
      - id: half_0x5c
        type: u2
        doc: "[UNKNOWN] 0xD43838 -> block+0x5C."
      - id: unknown_0x5e
        type: u1
        doc: "[UNKNOWN] 0xD43854 -> block+0x5E."
      - id: unknown_0x5f
        type: u1
        doc: "[UNKNOWN] 0xD43868 -> block+0x5F."
      - id: words_0x60
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: "[UNKNOWN] 18 consecutive u32 reads, 0xD43884 through 0xD43A60 -> block+0x60..+0xA4. Unrolled in the binary, not a loop, so there is no count field."
      - id: pair_0xa8
        size: 2
        doc: "[UNKNOWN] 2-byte raw read (0xD43A80) -> block+0xA8. Read as raw, not as u16, so treat as two bytes."
      - id: half_0xaa
        type: u2
        doc: "[UNKNOWN] 0xD43A9C -> block+0xAA."
      - id: word_0xac
        type: u4
        doc: "[UNKNOWN] 0xD43AB8 -> block+0xAC."
      - id: unknown_0xb0
        type: u1
        doc: "[UNKNOWN] 0xD43AD4 -> block+0xB0."
      - id: pair_0xb1
        size: 2
        doc: "[UNKNOWN] 2-byte raw read (0xD43AF4) -> block+0xB1."
      - id: unknown_0xb3
        type: u1
        doc: "[UNKNOWN] 0xD43B10 -> block+0xB3."
      - id: half_0xb4
        type: u2
        doc: "[UNKNOWN] 0xD43B2C -> block+0xB4."
      - id: half_0xb6
        type: u2
        doc: "[UNKNOWN] 0xD43B48 -> block+0xB6."
      - id: word_0xb8
        type: u4
        doc: "[UNKNOWN] 0xD43B64 -> block+0xB8."
      - id: unknown_0xbc
        type: u1
        doc: "[UNKNOWN] 0xD43B80 -> block+0xBC."
      - id: unknown_0xbd
        type: u1
        doc: "[UNKNOWN] 0xD43B9C -> block+0xBD."
      - id: tail_0xbe
        size: 14
        doc: "[UNKNOWN] 14-byte raw read (0xD43BBC) -> block+0xBE. Last field; the block ends at 0xCC = 204."
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
