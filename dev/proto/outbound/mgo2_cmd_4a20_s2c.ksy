meta:
  id: mgo2_cmd_4a20_s2c
  title: "MGO2 0x4A20 - Tournament/Survival round result: one round's bracket bitmap plus the entrant status column (server -> client)"
  endian: be
params:
  - id: blob_len
    type: u4
    doc: "NOT A WIRE FIELD. min(u16 at event record +0x0DA, 128), from client state (0xD51C14). That u16 is `halves[2]`, the entrant count, so the blob is **one byte per entrant**."
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); mgo2_cmd_4a24_s2c.ksy is canonical for the event record. **0x4A20
  advances the bracket by one round**: it sets the current round number, writes that round's
  128-bit entrant bitmap, snapshots the bitmap array, and replaces the whole per-entrant status
  column. Destination is `addi r26,r28,-9264` = **session+0xDBD0**, the same event record
  0x4A24 and 0x4A01 write.

  TIER. Post-launch content; no available client build exercises 0x4A20, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  **STRUCTURAL CORRECTION - `groups` IS NOT REPEATED.** The loop at 0xD51B88-0xD51BC8 runs
  exactly **four** times (`cmpdi cr6,r29,4` at 0xD51BB8) and writes
  `event record + 6896 + (round << 4) + 4*i - 16`. The u16 the schema used to call
  `group_count` is reloaded inside the loop only to recompute that address: it is the **round
  number**, not a count, and it is stored as such at event record +0x0E0 (0xD51B84), which is
  `halves[5]`, `current round`. So the wire carries **one 16-byte row**, always, and the
  declared `repeat-expr: group_count` overstates the packet by 16 bytes per extra round.
  **CORRECTED 2026-08-02** after a third independent pass confirmed it; the field is now
  `round_bitmap`, unrepeated. Reading it the old way would make a server emit N rows for round N
  and desync the blob that follows.

  AFTER THE ROW, the parser does three more things:
    * `memcpy(record+0x1B70, record+0x1AF0, 128)` at 0xD51BCC-0xD51BE4 - the snapshot the
      bracket renderer diffs against (mgo2_cmd_4a24_s2c.ksy, `rounds`). Note the direction:
      destination is the **second** array. Because this happens after the new row is written,
      the two arrays are identical on exit, which means the renderer's diff can only be
      non-empty between updates; whether that is the intent is [UNKNOWN].
    * pushes `halves[3]` and `halves[5]` into the object 0xD3F7B0 returns, at its +0x0C and
      +0x10 (0xD51C44-0xD51C58) - the same two slots 0x4A13 fills directly.
    * fires **event 25** with the record's `phase` byte (+0x0D4) as payload (0xD51CA4-0xD51CB0).

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD398B0,
  parser 0xD51A08.
  TWO different count sources in one packet, which is why they are called out separately:
  the `groups` count IS a wire field (the u16 at 0xD51B64, used as the loop bound at 0xD51B88),
  while the trailing blob's length is NOT (loop 0xD51BF0, bounded by `i < u16 at obj+0x0DA`
  and `i < 128` - 0xD51C08 / 0xD51C14 / 0xD51C1C, client state, same slot 0x4A01 uses).
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230, not by this parser
  directly: u32 then u16, both validated against the client's currently open object for this
  subsystem (0xD4929C and 0xD492D4); a mismatch aborts with -1018 before another byte is read.
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
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230."
  - id: event_id
    type: u4
    doc: "[ELF] read at 0xD51ADC, compared at 0xD51B04 against **event record +0x000**; mismatch aborts with -1106. Same id as 0x4A24's `obj_id`. Not a result code - compared against stored state, never sign-extended into 0xD32E70, and this command consumes no request slot."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD51B18 -> the currently open TEAM record's +0x004 (0xD491F8's object at session+0xD928 - not the event record at session+0xDBD0; the two are adjacent and must not be conflated). No reader traced."
  - id: phase
    type: u1
    doc: "[ELF] read at 0xD51B34 -> **event record +0x0D4**. mgo2_cmd_4a24_s2c.ksy's `phase`, named there from 0x8F95D8 (`(u8)(phase-2) <= 8` picks screen 14 vs 26). It is also this parser's event-25 payload (0xD51CA8). Struct-offset bijection; the old reading as \"a second object's +0x000\" was wrong. [UNKNOWN] what the codes mean."
  - id: half_0x0de
    type: u2
    doc: "[ELF] read at 0xD51B4C (-> r1+114) and stored at 0xD51B80 to **event record +0x0DE** = `halves[4]`. Read BEFORE the round number. [UNKNOWN] meaning: 0x4A24's sweep found no reader for +0x0DE in either window, with `halves[2]`/`[3]`/`[5]` as the controls that did come back."
  - id: current_round
    type: u2
    doc: |
      [ELF] read at 0xD51B64 (-> r1+112) and stored at 0xD51B84 to **event record +0x0E0** =
      `halves[5]`, **the current round**. mgo2_cmd_4a24_s2c.ksy names that slot from two
      readers: it is the `%d` of lobby string 773, *"Round %d of the tournament is complete."*
      (0x8CDB3C), and it selects which row of the bracket bitmap the renderer reads (0x8CDC8C,
      0x8FB23C).
      **It is NOT a count**, and it is no longer named as one: renamed `group_count` ->
      `current_round` on 2026-08-02, when the phantom `repeat-expr` that referenced it was
      removed.
      Inside the loop it is used solely as `round << 4`, the row's byte offset. The row it
      writes is `round - 1` (`addi r4,r4,-16` at 0xD51BA8), so the first round must be sent as
      1, not 0, and 8 is the ceiling - row 8 would start at +0x1B70, which is the snapshot.
  - id: round_bitmap
    type: group
    doc: |
      [ELF] loop 0xD51B88-0xD51BC8, four u32 (`cmpdi cr6,r29,4` at 0xD51BB8), written to
      `event record + 0x1AF0 + 16*(current_round-1)`.

      **CORRECTED 2026-08-02: this was `repeat: expr` / `repeat-expr: group_count`, and it does
      not repeat at all.** One 16-byte row, always. Confirmed by a third independent ELF pass
      after two earlier readings disagreed.

      The trap is specific and worth remembering: the u16 the schema called `group_count` is
      loaded by `lhz r4,112(r1)` — which **is the branch target**, literally the first
      instruction of the loop body, reloaded every iteration. That is exactly what a trip count
      looks like. But it never reaches a compare; it is consumed only by `slwi r4,r4,4` as
      **address arithmetic**, selecting which bracket row to write. The real bound is
      `cmpdi cr6,r29,4`, four instructions before the back-edge.

      So the field is the **round number**, not a count — stored to event record +0x0E0, which
      `mgo2_cmd_4a24_s2c.ksy` names `current round` from two readers.

      Reading it the old way would make a server emit N rows for round N and desync everything
      after. **The general rule this yields**, since this class cannot be swept mechanically: for
      every `repeat-expr` in `dev/proto/`, confirm the named field reaches a **compare**, not
      just address arithmetic.
      **On the wire this occurs exactly ONCE, not `group_count` times** - see the top-level
      correction. One 16-byte row = one round's **128-bit entrant bitmap**, bit `n` = entrant
      `n` of the +0x0F0 table, LSB first; mgo2_cmd_4a24_s2c.ksy's `round_bits` carries the
      addressing proof from the bracket renderer.
  - id: entrant_status
    size: blob_len
    doc: |
      [ELF] byte-at-a-time loop at 0xD51BF0-0xD51C28 into a stack buffer. Length =
      min(event record +0x0DA, 128) = one byte per entrant, NOT a wire field.
      **Each byte is one entrant's `status`**: 0xD51C5C-0xD51CA0 copies byte `i` to
      `table + 261 + 52*i` = entrant row `i`, offset 0x15 - the same field 0x4A11/0x4A33 set
      per row and 0x4A01 replaces the same way. [UNKNOWN] what the codes mean.
types:
  group:
    doc: "[ELF] 16 bytes: one round's 128-bit entrant bitmap."
    seq:
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 4
        doc: "[ELF] four u32 = 128 bits, one per entrant slot; word i covers slots 32*i..32*i+31, LSB first. Read at 0xD51BB0."
