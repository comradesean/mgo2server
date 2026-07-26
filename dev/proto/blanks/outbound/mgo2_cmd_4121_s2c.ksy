meta:
  id: mgo2_cmd_4121_s2c
  title: "MGO2 0x4121 — chat macros, packets 3/9 and 4/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Parser **0xd3d684** (GAME dispatcher 0xd38804, trampoline 0xd39040). **769 bytes**, sent twice
  per burst (once per macro type). Only two read calls:

      0xd3d6e0  u8       -> scratch  (macro type)
      0xd3d714  fixed[768] -> ctx+27728 + type*768

  **The type byte is bounds-checked and a bad value silently discards the packet:**
  `lbz r4,112(r1); cmplwi r4,1; bgt+ -> 0xd3d738` returns -71 without reading the 768 bytes. So
  type MUST be 0 or 1 — the same failure shape as `0x4105`'s page selector, and worth knowing
  before anyone invents a third macro type.

  The 768 bytes are copied as **one block**, not twelve 64-byte reads: the 12x64 grid PROTOCOL.md
  documents is the game's own interpretation of the region, not a parser structure.
doc-ref: dev/docs/PROTOCOL.md "0x4121 — chat macros, 769 bytes each, two packets"
seq:
  - id: macro_type
    type: u1
    doc: |
      [ELF] Wire 0x00. **Must be 0 or 1** (0xd3d6fc). Selects the destination half of the macro
      region. What the two types mean is not documented anywhere we have.
  - id: macros
    type: str
    size: 64
    encoding: ISO-8859-1
    repeat: expr
    repeat-expr: 12
    doc: |
      [INFERRED] Wire 0x01. The parser copies 768 bytes wholesale; the 12 x 64 split is from
      PROTOCOL.md / `CharacterService.getChatMacros`, which materialises the full 2 x 12 grid so
      the length is fixed even for a character that has never set a macro. `0x4114`, the
      write-back, uses the identical layout and was observed live, which is the strongest support
      for the split.
