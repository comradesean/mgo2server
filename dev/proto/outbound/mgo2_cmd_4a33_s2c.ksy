meta:
  id: mgo2_cmd_4a33_s2c
  title: "MGO2 0x4A33 - Tournament/Survival entrant-table rows, heap instance (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); mgo2_cmd_4a24_s2c.ksy is canonical for the event record. **0x4A33 fills
  the entrant table of the SECOND instance of that record** - the heap one at
  `*(u32*)(session+0x11904) + 0x1A840`, which is the instance 0x4A31 parses into.

  TIER. Post-launch content; no available client build exercises 0x4A33, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.** No capture backs any of it.

  SAME RECORD AS 0x4A11 - PROVEN, WITH THE DESTINATION SPLIT EXPLICIT. See
  mgo2_cmd_4a11_s2c.ksy for the full write-up; in brief:
    * Same TYPE: the two parsers' read sequences are instruction-for-instruction identical,
      both memset a 52-byte stack record, both copy it out as 32+20 bytes with `lswi`/`stswi`,
      both key the write on the leading u16 times 52 and both bound the append with the u16 at
      `ctx+0x0D6`. Every field name below therefore transfers from 0x4A11 by construction.
    * Different INSTANCE: 0x4A11 writes session+0xDCB8 (a fixed session displacement); this
      parser computes `lwz r9,6404(session+0x10000)` / `addis r9,r9,2` / `addi r27,r9,-22232`
      = **`*(session+0x11904) + 0x1A928`** (0xD52540-0xD52570), a pointer dereference into a
      separate allocation. Two instances of one type, not one shared array.

  0x4A32 / 0x4A33 / 0x4A34 ARE ONE TRIPLE, and it is the reply to the client's 0x4A30.
  0x4A32's parser is 0xD52760 (`cmpwi 0x4A32` at 0xD527BC) - begin. 0x4A33 appends rows.
  **0x4A34's parser is 0xD52398** (`cmpwi 0x4A34` at 0xD52410): it echo-checks a u32, closes
  the list header, and then **clears request slot 87** - `0xD32E3C(session,87)` must read 1,
  `0xD32E08(session,87,2)` at 0xD524A0, `0xD32E70(session,87,0)` at 0xD524B4. Slot 87 is the
  slot the client's 0x4A30 arms (0xD5056C). So **0x4A30 has two legal completions**: the single
  record 0x4A31 (0xD501E8) or this whole 0x4A32/0x4A33/0x4A34 sequence. That also matches the
  0x4A30 caller's failure dialog 5409, *"Unable to acquire Tournament list."*

  READERS: **none, for this instance.** The heap instance has its own accessor family -
  0xD52274 (`getEntry`, bound by ctx+0x0DA), 0xD522D0 (ctx+0x0EC), 0xD52310 (entrant count),
  0xD52350 (list head) - and **all four have zero call sites**. Swept the whole cached
  disassembly for `bl`/`b`/`bc` to each of the four, and separately scanned the raw ELF for
  their addresses as data: each appears exactly once, at 0x1029DD8/0x1029DE0/0x1029DE8/
  0x1029DF0, which is the OPD descriptor table, so there is no indirect call either. Control
  that the sweep is not broken: the identical sweep over the session-instance accessors
  (0xD4EAAC, 0xD4EAD8, 0xD51CF4) returns fourteen call sites, which is where 0x4A11's field
  names came from. The only path that reaches this instance's data is 0xD4EA7C, which
  `memcpy`s the whole 7296-byte record into a UI struct (0x8F20A4, 0x8F44AC) and then reads
  `+0x0D4` (the phase byte) out of the copy.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39920,
  parser 0xD524F4.
  A SIZE-DRIVEN LIST: the loop is fronted by the length-aware call 0xD5CEB0 at 0xD525B4
  (`cmpwi r3,-1` -> exit), so the record count is however many fit in the payload - there is no
  count field, and the packet carries N records back to back exactly like 0x4902 does. The
  append is capped by the u16 at ctx+0x0D6 (0xD526C8); rows past the cap are parsed and dropped.

  RECORD LENGTH IS NOT CONSTANT - see `name2_present` below: 45 bytes only when its bit 1 is
  set, 29 when it is clear.
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
    doc: "[ELF] size-driven (0xD525B4). 45 bytes when `name2_present` bit 1 is set, 29 when it is clear; a short record desyncs the rest of the packet rather than erroring."
types:
  entry:
    doc: |
      [ELF] One row of the heap event record's entrant table. 52 bytes in memory (memset at
      0xD52590-0xD525A8, `li r5,52`); 45 or 29 bytes on the wire. Field-for-field the same
      record as 0x4A11's - see mgo2_cmd_4a11_s2c.ksy, which carries the reader evidence.
    seq:
      - id: slot_index
        type: u2
        doc: |
          [ELF] read FIRST, at 0xD525D0 (-> r1+114), before the word. Do not reorder.
          **NOT a length and NOT part of the stored record** - it is the destination row:
          0xD526D8-0xD526E4 recomputes `header + 52*slot_index`. The count at header+4 is
          incremented separately (0xD526DC/0xD52704).
      - id: entrant_id
        type: u4
        doc: "[ELF] read at 0xD525E8 -> record+0x00. The entrant's (team's) id; zero means the row is empty. Named by the 0x4A11 bijection - this instance's own copy has no reader (see the top-level doc)."
      - id: entrant_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[ELF] 16-byte raw read (0xD52608) -> record+0x04, reader's NUL at record+0x14. The entrant's display name; string role evidenced through the 0x4A11 bijection, where the identical slot is formatted as the `%s` of lobby strings 776/777."
      - id: status
        type: u1
        doc: |
          [ELF] read at 0xD52624 -> record+0x15. Per-entrant status byte. In the session
          instance this exact slot is the one 0x4A01 and 0x4A20 bulk-overwrite one byte per
          entrant (`table + 261 + 52*i`); no equivalent bulk writer was traced for the heap
          instance, so for THIS command the naming rests on the layout bijection alone.
          [UNKNOWN] what the codes mean. Storage quirk: record+0x14..0x17 is a u32 bitfield, so
          this byte occupies bits 16..23 of it.
      - id: name2_present
        type: u1
        doc: |
          [ELF] read at 0xD52640 into stack scratch (r1+112) and **never stored**. A presence
          bitmask whose **bit 1 (0x02) decides whether `name2` is on the wire at all**:
          0xD52650-0xD52658 (`lbz` / `rldicl. r9,r0,63,63` / `beq`) skips the second 16-byte
          read when the bit is clear and sets 0x40 in the u32 at record+0x14 when it is set.
          **The record is therefore variable-length**, 45 bytes or 29. Not expressed in the
          declared layout below because sizes and repeats are evidence and this batch may only
          rename and document; flagged for a structural correction.
      - id: name2
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        if: (name2_present & 0x02) != 0
        doc: "[ELF] second 16-byte raw read (0xD52678) -> record+0x18, NUL at record+0x28. **Conditional** - see `name2_present`. [UNKNOWN] whose name; no reader in either instance."
      - id: unknown_0x28
        type: u1
        doc: "[UNKNOWN] read at 0xD52694 -> record+0x29. No reader in either instance."
      - id: unknown_0x29
        type: u4
        doc: "[UNKNOWN] read at 0xD526B0 -> record+0x2C. Last field of the record; record+0x30..0x33 stays zero. No reader in either instance."
