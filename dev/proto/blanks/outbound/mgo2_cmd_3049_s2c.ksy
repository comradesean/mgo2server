meta:
  id: mgo2_cmd_3049_s2c
  title: "MGO2 0x3049 — character list (server -> client)"
  endian: be
doc: |
  Reply to `0x3048`. Parser arm **0xd3732c** (ACCOUNT dispatcher 0xd37024 (compare tree at 0xd37074)), wait slot 14 (0xe).
  Total **0x1d7 = 471 bytes**, and the grid is **fixed regardless of how many characters exist**:
  the entry loop is `li r24,0 ... cmpwi r24,420; addi r24,r24,60; bne` at 0xd37740 — exactly
  **8 iterations**, count-independent, with no `MORE_DATA?` check anywhere.

  Structure, fully traced:
    * u32 result. **Non-zero skips the entire rest of the packet** (0xd3739c `cmpwi r0,0; bne ->
      0xd3776c`), so an error reply is legitimately four bytes (`C0FFEE02`).
    * three u8 header fields, a 16-byte name, then 8 fixed entries of 52 wire bytes, then a
      32-byte tail.
    * 23 + 8*52 + 32 = 471. Confirms PROTOCOL.md's size and shape exactly.

  Client struct destinations: header at `ctx+21968` (0x55D0), the 16-byte name into `ctx+22492`
  — **the same slot `0x4101` writes its character name into** (`0x4101`'s base is `ctx+22488`,
  name at +4) — entries at `ctx+21972 + n*60`, tail at `ctx+22452`. The entry region is memset to
  480 (= 8*60) bytes before parsing (0xd3737c).

  After `READ_END` the parser scans the 8 entries for the one whose slot byte equals the
  `selected_slot` header field (0xd37778: `lbz r4,2(r27); cmplwi r4,7; bgt -> skip`), so
  `selected_slot` is an index into the *slot numbers*, bounded at 7.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x3048 — get character list"; dev/docs/OBSERVED.md
seq:
  - id: result
    type: u4
    doc: "[CONFIRMED] Wire 0x00. Zero gates everything below; `C0FFEE02` if the connection has not checked in."
  - id: slots
    type: u1
    doc: "[ELF] Wire 0x04 -> ctx+21968. PROTOCOL.md names it `slots`."
  - id: count
    type: u1
    doc: "[ELF] Wire 0x05 -> ctx+21969. Character count. **Not** a repeat count — the 8 entries are read unconditionally."
  - id: selected_slot
    type: u1
    doc: "[ELF] Wire 0x06 -> ctx+21970. Bounded at 7 by the post-parse scan at 0xd3777c."
  - id: selected_name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: "[ELF] Wire 0x07 -> ctx+22492, i.e. the same destination as 0x4101's character name."
  - id: entries
    type: character_entry
    repeat: expr
    repeat-expr: 8
    doc: "[CONFIRMED] Always 8, always read. 52 wire bytes each; 60 bytes per entry in the client struct."
  - id: unknown_1b7
    size: 32
    doc: |
      [UNKNOWN] Wire 0x1b7, fixed 32 bytes -> ctx+22452. PROTOCOL.md flagged item 5 calls this
      "0x3049's 35-byte trailer, with `07` at +4 and `03` at +6" — note the count differs: the
      parser reads **32**, and the 3 extra bytes in that description are the three u8 header
      fields. Contents reproduced from the original; meaning unknown.
types:
  character_entry:
    doc: |
      52 wire bytes -> 60-byte struct entry. Field-by-field read destinations are given as struct
      offsets within the entry; the gaps (struct +1..3, +24, +34/35, +54..55) are never written by
      the parser.
    seq:
      - id: slot
        type: u1
        doc: "[ELF] Wire +0 -> entry +0. Matched against `selected_slot` after the parse."
      - id: chara_id
        type: u4
        doc: "[ELF] Wire +1 -> entry +4."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        doc: "[ELF] Wire +5 -> entry +8 (NUL at +24)."
      - id: appearance_a
        size: 9
        doc: |
          [CONFIRMED] (order per PROTOCOL.md) Wire +21 -> entry +25..+33, nine separate u8 reads
          (0xd37438 .. 0xd37538). Appearance bytes 0-8: gender … pitch, same order as `0x4130`.
      - id: unknown_1e
        type: u4
        doc: |
          [UNKNOWN] Wire +30 -> entry +36. PROTOCOL.md: "The four bytes at +9 remain skipped,
          purpose unknown. They sit where the write path emits four zero bytes, so nothing is
          known to be lost, but nothing confirms that either." Still true.
      - id: appearance_b
        size: 14
        doc: "[CONFIRMED] (order per PROTOCOL.md) Wire +34 -> entry +40..+53, fourteen separate u8 reads. Appearance head … accessory-2 colour."
      - id: unknown_30
        type: u4
        doc: "[UNKNOWN] Wire +48 -> entry +56. Read but never identified; we send zero."
