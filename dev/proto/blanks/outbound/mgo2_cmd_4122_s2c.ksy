meta:
  id: mgo2_cmd_4122_s2c
  title: "MGO2 0x4122 — personal info, packet 5/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Parser **0xd3d02c** (GAME dispatcher 0xd38804, trampoline 0xd39050). **0xf5 = 245 bytes**,
  fully traced 0xd3d0a0 .. 0xd3d630, field by field with no opaque regions.

  Two client struct bases: `r26 = ctx+29304` (0x7278, the clan / personal block) and
  `r28 = ctx+30136` (0x75B8, the appearance-and-skills block). The appearance block is the same
  struct `0x4131` writes into, which is how the two specs cross-check each other.

  ### Correction to PROTOCOL.md: there are FIVE skill slots, not four

  PROTOCOL.md's table reads wire 0x4c..0x6a as `4 x u8 skills`, `u8 zero`, `4 x u8 levels`,
  `u8 zero`, `4 x u32 experience`, `5 bytes zero`. The parser reads the same 31 bytes as three
  loops of **five**:

      0xd3d500  loop x5: u8  -> r28+30 + i     (bound `cmpdi cr6,r31,5`)
      0xd3d530  loop x5: u8  -> r28+35 + i     (bound 5)
      0xd3d560  loop x5: u32 -> r28+40 + i*4   (bound 5)
      0xd3d5a0  u8           -> r28+60

  So PROTOCOL.md's "zero at 0x50" is the **fifth skill id**, "zero at 0x55" is the **fifth skill
  level**, and its "5 bytes zero at 0x66" is the **fifth experience u32** (4 bytes) plus the lone
  u8 at wire 0x6a. Byte counts agree exactly; only the interpretation differs. `0x4131`'s parser
  (0xd3c3dc) has the identical 5/5/5 shape into the same struct offsets, and both agree with
  `0x4103`'s traced tail ("9 x u8 · u32 · 14 x u8 · 10 x u8 · 5 x u32 · u8 · u32 · 128-byte
  comment", PROTOCOL.md) — three independent parsers, all five-wide. Serving zeros in the fifth
  slot is what we already do, so nothing is broken; the field names were wrong.
doc-ref: dev/docs/PROTOCOL.md "0x4122 — personal info, 0xf5 = 245 bytes"
seq:
  - id: clan_id
    type: u4
    doc: "[ELF] Wire 0x00 -> ctx+29304. Always 0 — clans are not modelled. Also rewritten by 0x4129's tail."
  - id: clan_name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: "[ELF] Wire 0x04 -> ctx+29308, fixed 16, NUL at +16. Always empty."
  - id: unknown_14
    type: u1
    doc: |
      [UNKNOWN] Wire 0x14 -> ctx+29325. First byte of what PROTOCOL.md calls the 25-byte unknown
      prefix; the original's value here is `01`. Also rewritten by 0x4129 (its wire +36 u8).
  - id: unknown_15
    type: u2
    repeat: expr
    repeat-expr: 12
    doc: |
      [UNKNOWN] Wire 0x15 -> ctx+29326 + i*2. **Twelve separate 2-byte reads** (0xd5cc14) — the
      remaining 24 bytes of PROTOCOL.md's 25-byte prefix are a u16 array, not opaque padding.
      Reading the original's transcribed prefix as u16s gives
      `0000 000C 0001 0000 0000 0000 0100 0100 0000 0000 0001 ....`; PROTOCOL.md prints it as
      bytes and records no meaning. The first element (ctx+29326) is also rewritten by 0x4129.
  - id: current_time
    type: u4
    doc: "[ELF] Wire 0x2d. Read as u32, widened and stored as u64 at ctx+29352. PROTOCOL.md: current time, Unix seconds."
  - id: appearance_a
    size: 9
    doc: "[CONFIRMED] (order per PROTOCOL.md) Wire 0x31 -> ctx+30136..30144, nine separate u8 reads. Appearance bytes 0-8 (gender … pitch), same order as 0x3049."
  - id: unknown_3a
    type: u4
    doc: "[UNKNOWN] Wire 0x3a -> ctx+30148. PROTOCOL.md: zero, purpose unknown. Sits in the appearance struct between the two appearance groups."
  - id: appearance_b
    size: 14
    doc: "[CONFIRMED] (order per PROTOCOL.md) Wire 0x3e -> ctx+30152..30165, fourteen separate u8 reads. Appearance head … accessory-2 colour."
  - id: skills
    type: u1
    repeat: expr
    repeat-expr: 5
    doc: "[ELF] Wire 0x4c -> ctx+30166 + i. **Five** equipped-skill ids; see the correction in the top-level doc. We fill 4 and leave the fifth zero."
  - id: skill_levels
    type: u1
    repeat: expr
    repeat-expr: 5
    doc: "[ELF] Wire 0x51 -> ctx+30171 + i. Five levels, paired with `skills`."
  - id: skill_experience
    type: u4
    repeat: expr
    repeat-expr: 5
    doc: |
      [ELF] Wire 0x56 -> ctx+30176 + i*4. **Five** u32s, 20 bytes, not four. PROTOCOL.md: fixed
      `0x600000` each — skill progression does not exist.
  - id: unknown_6a
    type: u1
    doc: "[UNKNOWN] Wire 0x6a -> ctx+30196. The single byte after the experience array. Zero."
  - id: chara_id
    type: u4
    doc: "[ELF] Wire 0x6b -> ctx+30200. PROTOCOL.md: \"the original sends the character id here; its purpose is not documented\"."
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    doc: "[CONFIRMED] Wire 0x6f -> ctx+30204, fixed 128. The player's profile comment."
  - id: rank
    type: u1
    doc: "[ELF] Wire 0xef -> ctx+30333. Also rewritten by 0x4129 (its wire +4 u8), which is consistent with a post-game rank update."
  - id: emblem_flag
    type: u1
    doc: "[ELF] Wire 0xf0 -> ctx+29360. PROTOCOL.md: 3 when the clan has an emblem; always 0 here. Also rewritten by 0x4129."
  - id: unknown_f1
    type: u4
    doc: "[UNKNOWN] Wire 0xf1 -> ctx+35536. PROTOCOL.md reproduces the original's suffix as `00 A7 00 0D` = 0x00A7000D and records no meaning."
