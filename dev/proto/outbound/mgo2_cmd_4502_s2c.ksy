meta:
  id: mgo2_cmd_4502_s2c
  title: "MGO2 0x4502 — add/change relationship reply (server -> client)"
  endian: be
doc: |
  Reply to 0x4500 (add / change relationship). Parser 0xD47110 (ends 0xD473B4), dispatcher stub
  0xD39320. A SINGLE packet, not a triple — the client has no 0x4501/0x4503 parser (PROTOCOL.md,
  OBSERVED.md 2026-07-23).

  PROTOCOL.md already documents the 25-byte layout and OBSERVED.md confirms it live
  (`u32 0, u32 id, u8 state, name[16]`). The ELF read order agrees exactly:
  0xD5CC64 u32 -> 0xD5CCD8 u32 -> 0xD5CB8C u8 -> 0xD5D018 raw 16.

  THE BODY IS CONDITIONAL ON THE LEAD WORD. At 0xD471C0 the parser reloads the first u32 and
  branches (`cmpwi 0; bne -> 0xD4721C`) straight to the reader-close, skipping the id, state and
  name entirely. So a nonzero lead word means a 4-byte frame with no body — which is what
  PROTOCOL.md's "nonzero = empty/count-only frame" describes, here confirmed from the binary.

  After the reads the u8 state selects the UI event: 0xD32E08 is called with index
  0x4D + state (0xD47234: `addi r4,r4,77`), so friend and blocked land in different slots.
  A 16-byte name field is read with 0xD5D018, which NUL-terminates at dest[16] — the client
  struct is therefore 17 bytes wide there while the wire is 16.
doc-ref: dev/docs/PROTOCOL.md "0x4500 — add / change relationship"
seq:
  - id: lead
    type: u4
    doc: |
      [CONFIRMED] 0 to carry a body; nonzero terminates the packet after 4 bytes (branch at
      0xD471C0). We send 0. [ELF 0xD471AC]
  - id: target_chara_id
    type: u4
    if: lead == 0
    doc: "[CONFIRMED] target character id. [ELF 0xD471D4]"
  - id: state
    type: u1
    if: lead == 0
    doc: |
      [CONFIRMED] relation state — 0 friend, 1 blocked (both confirmed live, PROTOCOL.md). Also
      selects the UI event index, 0x4D + state (0xD47234). [ELF 0xD471F0]
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    if: lead == 0
    doc: "[CONFIRMED] target character name, NUL-padded. [ELF 0xD4720C, 0xD5D018 with r5=16]"
