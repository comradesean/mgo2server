meta:
  id: mgo2_cmd_4a11_s2c
  title: "MGO2 0x4A11 - Tournament/Survival entrant-table rows (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); mgo2_cmd_4a24_s2c.ksy is canonical for the event record. **0x4A11 fills
  that record's entrant table** - the 128-entry, 52-byte-stride array at event record +0x0F0.

  TIER. Post-launch content; no available client build exercises 0x4A11, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.** No capture backs any of it.

  DESTINATION PROVEN, NOT INFERRED. The parser takes `addis r9,r31,1` / `addi r27,r9,-9032` =
  **session+0xDCB8** (0xD51F84-0xD51F8C) as the list header and writes each record at
  `header + 8 + 52*index` = session+0xDCC0 + 52*index (0xD52104-0xD52118). The 0x4A24 event
  record is session+0xDBD0 and its entrant table is +0x0F0 = **session+0xDCC0**. Same address,
  same stride - a struct-offset bijection, the 0x4905/0x4909 standard, not a resemblance.
  So the header is event record +0x0E8 (a validity magic, set to -1 by 0x4A10 at 0xD5224C and
  cleared by 0x4A12) and +0x0EC (the running row count).

  0x4A10 / 0x4A11 / 0x4A12 ARE ONE TRIPLE. 0x4A10's parser (0xD52170, `cmpwi 0x4A10`) echo-
  checks a u32, then `memset(session+0xDCB8, 0, 6664)` and writes count 0 and magic -1 -
  **begin list**. 6664 = 8 + 52*128, which independently pins the table at 128 entries.
  0x4A11 appends rows. 0x4A12's parser is 0xD51D54 (`cmpwi 0x4A12`) - end of list.
  The append is gated by `halves[0]` at event record +0x0D6 (0xD520E8): rows past that cap are
  parsed and dropped, not rejected.

  SHARED RECORD WITH 0x4A33 - TESTED, AND THE ANSWER IS "SAME TYPE, DIFFERENT INSTANCE".
  Prove-or-refute was run the way the brief asked, and it splits:
    * Same TYPE, proven: the two parsers' read sequences are instruction-for-instruction
      identical (0xD51FD4.. vs 0xD525B4..), both memset a **52-byte** stack record, both copy
      it out as 32+20 bytes with `lswi`/`stswi`, both bound the append with a u16 at
      `ctx+0x0D6` and both key the write on the leading u16 times 52. Map once, apply to both.
    * Different INSTANCE, proven: 0x4A11's base is the fixed session displacement above.
      0x4A33's is `lwz r9,6404(session+0x10000)` then `addis r9,r9,2` / `addi r27,r9,-22232` =
      **`*(u32*)(session+0x11904) + 0x1A928`** (0xD52540-0xD52570) - a pointer dereference into
      a separate allocation, not a displacement off the session. This is the 0x4212/0x4682
      outcome for the destination.
    * And that second instance is identified: `*(session+0x11904) + 0x1A840` is exactly the
      base 0x4A31 parses into, and 0x4A31 shares 0x4A24's parser and layout. So there are **two
      instances of the 7296-byte event record**, and 0x4A11 fills the entrant table of the one
      embedded in the session while 0x4A33 fills the entrant table of the heap one.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39890,
  parser 0xD51F2C.
  A SIZE-DRIVEN LIST: the loop is fronted by the length-aware call 0xD5CEB0 at 0xD51FD4
  (`cmpwi r3,-1` -> exit), so the record count is however many fit in the payload - there is no
  count field, and the packet carries N records back to back exactly like 0x4902 does.

  RECORD LENGTH IS NOT CONSTANT - see `name2_present` below. 45 bytes only when its bit 1 is
  set; 29 bytes when it is clear. The `repeat: eos` above is therefore correct but the fixed
  45-byte reading that used to be written here was not.
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
    doc: "[ELF] size-driven (0xD51FD4). 45 bytes when `name2_present` bit 1 is set, 29 when it is clear; a short record desyncs the rest of the packet rather than erroring."
types:
  entry:
    doc: |
      [ELF] One row of the event record's entrant table. 52 bytes in memory (memset at
      0xD51FB0-0xD51FC8, `li r5,52`); 45 or 29 bytes on the wire depending on `name2_present`.
    seq:
      - id: slot_index
        type: u2
        doc: |
          [ELF] read FIRST, at 0xD51FF0 (-> r1+114), before the word. Do not reorder.
          **NOT a length and NOT part of the stored record** - it is the destination row.
          0xD520F8-0xD52108 reloads it and computes `header + 52*slot_index`, so the server
          chooses where in the 128-entry table each row lands. The running count at header+4
          is incremented independently (0xD520FC/0xD52100), which means count and highest
          written slot can disagree if the server is not careful; the accessor 0xD51CF4 bounds
          reads by `halves[2]` (entrant count), not by this.
      - id: entrant_id
        type: u4
        doc: |
          [ELF] read at 0xD52008 -> record+0x00. **The entrant's (team's) id.** Two independent
          readers: 0x8CDD44 / 0x8FB2F4 treat `record+0x00 == 0` as "slot empty" and skip the
          matchup; and 0x8CC414 / 0x8CDA2C scan the table for the row whose +0x00 equals the
          event record's `standings[0]` and print that row's name as the winning team of lobby
          string 742. Both reach the table through the accessor 0xD51CF4, whose base is the
          session-embedded event record - the same instance this parser writes.
      - id: entrant_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF] 16-byte raw read (0xD52028) -> record+0x04, with the reader's NUL landing on
          record+0x14. **String role is evidenced, not inferred from width**: 0x8CDE0C and
          0x8FB3CC pass record+0x04 to the string copier 0xAF70F0 and then to lobby strings
          **776** *"Team %s has won the match."* and **777** *"Team %s has won the match by
          default."* as the `%s`.
      - id: status
        type: u1
        doc: |
          [ELF] read at 0xD52044 -> record+0x15. **Per-entrant status byte**, named by
          struct-offset bijection rather than by a reader of its own: the 0x4A01 parser
          (0xD509F8-0xD50A3C) and the 0x4A20 parser (0xD51C5C-0xD51CA0) each carry a byte array
          one byte per entrant and write it to `table + 261 + 52*i`, and 261 = 0xF0 + 0x15 -
          i.e. exactly this slot for every row. So this byte is the per-row value that those
          two bulk-update commands overwrite wholesale. [UNKNOWN] what the codes mean; nothing
          enumerates them and no capture can reach them.
          Note the storage quirk: record+0x14..0x17 is a u32 bitfield (see `name2_present`), so
          this byte occupies bits 16..23 of that word.
      - id: name2_present
        type: u1
        doc: |
          [ELF] read at 0xD52060 into stack scratch (r1+112) and **never stored**. It is a
          presence bitmask, and **bit 1 (value 0x02) decides whether `name2` is on the wire at
          all**: `lbz r0,112(r1)` / `rldicl. r9,r0,63,63` / `beq` at 0xD52070-0xD52078 skips
          the second 16-byte read entirely when the bit is clear, and sets 0x40 in the u32 at
          record+0x14 when it is set. The other seven bits are read and discarded.
          **This makes the record variable-length** - 45 bytes with the bit, 29 without - which
          the declared layout below does not express. Not changed here because widths, sizes
          and repeats are evidence and this batch may only rename and document; flagged for a
          structural correction. A server that clears bit 1 but still sends 16 bytes of name
          desyncs every following row.
      - id: name2
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF] second 16-byte raw read (0xD52098) -> record+0x18, NUL at record+0x28.
          **Conditional** - see `name2_present`. [UNKNOWN] whose name: no reader was found for
          record+0x18 in either the 0xD51CF4 accessor's eight call sites or the five call sites
          of the list getter 0xD4EAAC, both of which DID yield the readers of +0x00 and +0x04
          named above, so the sweep is working and this negative is real. A team leader's
          handle beside the team name is the shape that fits, but it is not evidenced.
      - id: unknown_0x28
        type: u1
        doc: "[UNKNOWN] read at 0xD520B4 -> record+0x29. **No reader**, same sweep and same control as `name2` above."
      - id: unknown_0x29
        type: u4
        doc: "[UNKNOWN] read at 0xD520D0 -> record+0x2C. Last field of the record. **No reader**, same sweep and same control. Note record+0x30..0x33 is memset to zero and never touched by the wire."
