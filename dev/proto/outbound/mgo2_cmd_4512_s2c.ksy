meta:
  id: mgo2_cmd_4512_s2c
  title: "MGO2 0x4512 — remove relationship reply (server -> client)"
  endian: be
doc: |
  Reply to 0x4510 (remove relationship). Parser 0xD46B60 (ends 0xD46EAC), dispatcher stub
  0xD39330. A SINGLE packet, not a triple.

  PROTOCOL.md documents 9 bytes with the field order DIFFERENT from 0x4502 — state before id,
  no name — and OBSERVED.md confirms it live. The ELF read order agrees exactly:
  0xD5CC64 u32 (0xD46BEC) -> 0xD5CB8C u8 (0xD46C18) -> 0xD5CCD8 u32 (0xD46C30).

  THE BODY IS CONDITIONAL ON THE LEAD WORD, as in 0x4502: at 0xD46C00 the parser reloads the
  first u32 and `bne -> 0xD46C40`, skipping state and id. Nonzero = 4-byte frame only.

  After the reads the u8 state again selects the UI event index (lbz at 0xD46C4C), and the
  handler then compacts the two relation arrays: the loops at 0xD46DC4 and 0xD46E3C walk 32-slot
  tables (cmpwi 31) removing the deleted id.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C u8, 0xD5CC14 u16, 0xD5CCD8 / 0xD5CC64 u32, 0xD5D018 raw.
doc-ref: dev/docs/PROTOCOL.md "0x4510 — remove relationship"
seq:
  - id: lead
    type: u4
    doc: |
      [CONFIRMED] 0 to carry a body; nonzero terminates the packet after 4 bytes (branch at
      0xD46C00). We send 0. [ELF 0xD46BEC]
  - id: state
    type: u1
    if: lead == 0
    doc: |
      [CONFIRMED] the state REMOVED — 0 friend, 1 blocked. Read BEFORE the id here, the reverse
      of 0x4502. [ELF 0xD46C18]
  - id: target_chara_id
    type: u4
    if: lead == 0
    doc: "[CONFIRMED] target character id. [ELF 0xD46C30]"
