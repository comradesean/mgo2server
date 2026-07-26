meta:
  id: mgo2_cmd_4a24_s2c
  title: "MGO2 0x4A24 - unmapped 0x4Axx full-record reply (server -> client)"
  endian: be
params:
  - id: group_count
    type: u2
    doc: |
      NOT A WIRE FIELD. The client takes the `groups` count from its own state (the u16 at
      obj+0x0DC, read at 0xD4FEF0), which is `halves[3]` of this same layout as most recently
      stored. Declared as a parameter so a spec reader cannot mistake it for a length prefix.
doc: |
  UNMAPPED SUBSYSTEM. Nothing in PROTOCOL.md or OBSERVED.md describes 0x4A24.

  Evidence: dispatcher 0xD38804, entry stub 0xD398F0 (which sets `li r4,0x4A24` and tail-calls the
  shared parser), parser 0xD4FB80.

  0x4A24 AND 0x4A31 SHARE ONE PARSER, 0xD4FB80, and it accepts no other id (`cmpwi 0x4A24` /
  `cmpwi 0x4A31` at 0xD4FBE4/0xD4FBF4, everything else bails). The id only selects which
  client object is validated (cr4 at 0xD4FC3C) - the READ SEQUENCE IS THE SAME FOR BOTH, so the
  two payload layouts are identical by construction, not by resemblance.

  THE BIG CAVEAT: the length of the `groups` array is NOT on the wire. The outer loop bound is
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
seq:
  - id: result
    type: u4
    doc: |
      [ELF] read at 0xD4FC70. MUST be 0: non-zero branches to 0xD50140, straight past RD_END,
      and NOTHING else in the payload is read. This is the one established field here.
  - id: obj_id
    type: u4
    doc: "[ELF] read at 0xD4FC94, validated against the open client object (0xD4FCCC / 0xD4FD08); mismatch aborts. [UNKNOWN] which id."
  - id: unknown_0x08
    type: u1
    doc: "[UNKNOWN] read at 0xD4FD2C -> obj+0x0D4."
  - id: halves
    type: u2
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] eight u16, read by eight unrolled calls 0xD4FD48-0xD4FE0C into obj+0x0D6, +0x0D8,
      +0x0DA, +0x0DC, +0x0DE, +0x0E0, +0x0E2, +0x0E4. Index 3 (obj+0x0DC) is the value the
      `groups` loop bound is later taken from. [UNKNOWN] meanings.
  - id: unknown_0x19
    type: u4
    doc: "[UNKNOWN] read at 0xD4FE24 and widened to 64 bits at obj+0x1BF0 - the widening is what a time_t looks like on this target (compare mgo2_cmd_4902.ksy open_time), but that is a guess, not a trace."
  - id: unknown_0x1d
    type: u4
    doc: "[UNKNOWN] read at 0xD4FE48 -> obj+0x1BF8."
  - id: unknown_0x21
    type: u1
    doc: "[UNKNOWN] read at 0xD4FE64 -> obj+0x1BFC."
  - id: unknown_0x22
    type: u1
    doc: "[UNKNOWN] read at 0xD4FE80 -> obj+0x1BFD."
  - id: text
    size: 64
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[INFERRED] 64-byte raw read (0xD4FEA4) -> obj+0x1BFE. Width certain; string role from the width alone."
  - id: groups
    type: group
    repeat: expr
    repeat-expr: group_count
    doc: |
      [ELF] outer loop 0xD4FEB8-0xD4FF04, stride 16 into obj+0x1AF0, bound `halves[3]` READ
      FROM CLIENT STATE at obj+0x0DC (0xD4FEF0), not from this packet's parse buffer. See the
      caveat in the top-level doc.
  - id: words
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: "[ELF] exactly 8 u32, loop 0xD4FF0C-0xD4FF3C (`cmpdi r29,8`) -> obj+0x1C40 + 4*i. Fixed count."
  - id: flags
    type: u1
    doc: "[ELF] 1-byte raw read (0xD4FF50) expanded bit by bit into a flags word; each bit a distinct boolean. [UNKNOWN]."
  - id: unknown_after_flags
    type: u1
    doc: "[UNKNOWN] read at 0xD50050 -> obj+0x005."
  - id: block
    type: block_204
    doc: "[ELF] the shared 204-byte sub-record, read by 0xD4364C (called at 0xD5006C). Same block 0x4A00 embeds."
  - id: trailing_words
    type: u4
    repeat: expr
    repeat-expr: 6
    doc: "[ELF] six u32, unrolled 0xD50088-0xD50114 -> obj+0x1C64, +0x1C68, +0x1C6C, +0x1C70, +0x1C74, +0x1C78. [UNKNOWN] meanings."
types:
  group:
    doc: "[ELF] 16 bytes: four u32, read by the inner loop at 0xD4FECC (`cmpwi r29,3`)."
    seq:
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 4
        doc: "[UNKNOWN] four u32 per group."
  block_204:
    doc: |
      [ELF] The 204-byte sub-record read by the shared helper 0xD4364C, which several ids in
      this family embed. Enumerated read-by-read from 0xD4364C-0xD43BC0. Size is certain; every
      meaning is [UNKNOWN]. Kept as one type so the ids that embed it stay byte-exact.
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
      - id: text_0x32
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] 16-byte raw read (0xD43730) -> block+0x32. Width certain; string role from the width and 0xD5D018's NUL behaviour only."
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
