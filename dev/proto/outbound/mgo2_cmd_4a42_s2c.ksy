meta:
  id: mgo2_cmd_4a42_s2c
  title: "MGO2 0x4A42 - Tournament/Survival event list rows (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1). **0x4A42 is the browse list**: one 104-byte row per tournament or
  survival event on offer, which the player scrolls, sorts and picks from. It is a different
  list from 0x4A11/0x4A33 (those are the entrant table *inside* one event).

  TIER. Post-launch content; no available client build exercises 0x4A42, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  WHERE IT LIVES AND WHAT SELECTS FROM IT. The destination is
  `lwz r0,6404(session+0x10000)` / `addis r9,r9,2` / `addi r27,r9,21232` =
  **`*(u32*)(session+0x11904) + 0x252F0`** (0xD4F814-0xD4F84C), header at +0x00/+0x04 and rows
  at header+8+104*i (0xD4FB0C-0xD4FB24). The accessor for that array is **0xD4EBA8**
  (`return head + 8 + 104*index`, bounded by head+4), and it has ten call sites, all in the
  browse screen at 0x8F1930-0x8F45FC.
  The one that closes the loop is **0x8F43E0**: it calls 0xD4EBA8 with the highlighted row,
  reads the row's **+0x00**, and passes it straight to **0xD5048C, the 0x4A30 sender**
  (0x8F43FC). So this list's leading u32 is the event id the client sends back to ask for a
  specific event, and the reply to that is 0x4A31 or the 0x4A32/0x4A33/0x4A34 triple. Together
  with the caller's failure dialog 5409, *"Unable to acquire Tournament list."*, that pins the
  whole flow.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39950,
  parser 0xD4F7E8. This is 0x4A40's list: the 0x4A43 parser (0xD4F390) clears request slot 88,
  which the 0x4A40 sender arms.
  A SIZE-DRIVEN LIST fronted by the length-aware call 0xD5CEB0 at 0xD4F890 (`cmpwi r3,-1`
  -> exit): N records back to back, no count field, exactly the 0x4902 pattern. The client's
  array holds 64 entries (`cmpwi r3,63` at 0xD4FB04); record 65 onward is parsed and dropped.
  Rows are appended in arrival order - unlike 0x4A11/0x4A33 there is no wire slot index.
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
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF] size-driven (0xD4F890). 94 bytes each."
types:
  entry:
    doc: "[ELF] 94 wire bytes."
    seq:
      - id: event_id
        type: u4
        doc: |
          [ELF] read at 0xD4F8A8 -> record+0x00. **The event id**, and the field the whole flow
          turns on: 0x8F43DC-0x8F43FC fetches the highlighted row through 0xD4EBA8, loads this
          word, and hands it to the 0x4A30 sender as its only payload. 0x4A30 then stashes it
          at `*(session+0x11904)+0x26D08`, where 0x4A31's parser echo-checks it (0xD4FCC8).
          One id, three commands - a struct-offset bijection end to end.
      - id: unknown_0x04
        type: u1
        doc: "[UNKNOWN] read at 0xD4F8C4 -> record+0x04. Sits immediately before the name. No reader found among the ten 0xD4EBA8 call sites; controls that did come back in the same sweep are record+0x00, record+0x05 and record+0x4A below."
      - id: event_name
        size: 64
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF] 64-byte raw read (0xD4F8E4) -> record+0x05, reader's NUL at record+0x45.
          **String role is evidenced, not inferred from width**: the browse screen's sort
          routine at 0x8F1950/0x8F1A1C-0x8F1A24 takes `row + 5` as a sort key and compares two
          of them with the string comparator **0xDCC4F0**. Only a string is strcmp'd.
          64 bytes is also the width of the event record's own `lobby_name` (0x4A24 +0x1BFE),
          which is what a browse row would be showing.
      - id: halves
        type: u2
        repeat: expr
        repeat-expr: 7
        doc: |
          [ELF] seven u16, unrolled 0xD4F900-0xD4F9A8, into record+0x48, +0x4A, +0x4C, +0x4E,
          +0x50, +0x52, +0x54. Seven, not eight - the eighth slot in the neighbouring layouts
          has no read here.
          **`halves[1]` (record+0x4A) is the screen's alternate sort key**: 0x8F1980 loads
          `lhz r0,74(row)` and stores it as the sort value on the branch where the name is not
          used, i.e. the list can be ordered by name or by this number. [UNKNOWN] which number;
          entrant count and start time are both the right shape and neither is evidenced.
          The other six have no reader among the ten 0xD4EBA8 call sites.
      - id: unknown_0x53
        type: u4
        doc: "[UNKNOWN] read at 0xD4F9C4 into scratch and then **widened to 64 bits** at record+0x58 (`lwz r0,116(r1)` / `std r0,208(r1)`, 0xD4F9D8-0xD4F9E4). The 32-to-64 widening is what a time_t looks like on this target - the same shape as 0x4A24's `unknown_0x19` at event record +0x1BF0 - so a scheduled start time fits, but no reader was found and it stays [UNKNOWN]."
      - id: unknown_0x57
        type: u4
        doc: "[UNKNOWN] read at 0xD4F9E8 -> record+0x60. No reader."
      - id: unknown_0x5b
        type: u1
        doc: "[UNKNOWN] read at 0xD4FA04 -> record+0x64. No reader."
      - id: unknown_0x5c
        type: u1
        doc: "[UNKNOWN] read at 0xD4FA20 -> record+0x65. No reader."
      - id: flags
        type: u1
        doc: |
          [ELF] 1-byte raw read (0xD4FA40) expanded bit by bit by the `ori` ladder at
          0xD4FA50-0xD4FAF8 into the 64-bit word at record+0x40 - eight distinct booleans,
          bit-reversed exactly as in 0x4A24's `flags` (wire bit 0 becomes 0x8000, wire bit 7
          becomes 0x0100). Last byte of the record. [UNKNOWN] meanings; no reader for any bit.
          Note the ladder here uses `ori`, not `oris`, so the bits land in the LOW half-word of
          record+0x40 rather than the high one - it is NOT the same word layout as 0x4A24's.
