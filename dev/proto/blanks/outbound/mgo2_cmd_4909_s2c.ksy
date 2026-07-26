meta:
  id: mgo2_cmd_4909_s2c
  title: "MGO2 0x4909 — server -> client: 912-byte detail record (0x49xx clan/GHQ/roster block)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4909` at `0xd38b90` and branches to the
  thunk at `0xd395d8`, which tail-calls the parser at `0xd48674`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  The largest parser in this block. It fills a 912-byte record of its own at ctx+0xD598 —
  NOT the 680-byte clan record the rest of this family shares — so calling it a clan record
  would be a guess; what it describes is [UNKNOWN]. Preconditions: `hdr.command == 0x4909` and request-status
  slot **58** must read as 1 (pending) via `0xD32E3C`, else `-70` and the packet is dropped
  [READ 0xd486d8]. Then a 4-byte result; **nonzero skips every field** and only the request
  slot is completed. On success the destination record is memset to **912 bytes** and filled
  in wire order below. Slot 58 is completed with the result at the end.

  One 204-byte sub-block is read by the shared reader `0xD4364C`. That reader has **nine** call
  sites, not two: `0xD445A4` (0x4313), `0xD48440` (0x4905), `0xD48964` (here), `0xD4B244`
  (0x4987), `0xD4CB08` (0x4950), `0xD5006C` (the shared 0x4A24/0x4A31 parser), `0xD51014`
  (0x4A00), `0xD5AF38` (0x4E10) and `0xD5B78C` (0x43F1). An earlier revision of this file said
  "also read by 0x4950 and 0x4987"; that list was seven short. [ELF, exhaustive `bl 0xd4364c`
  scan of 0xD30000-0xD60000, 2026-07-26]

  **The canonical model of this block lives in `mgo2_cmd_4313_s2c.ksy`, type `game_settings`.**
  That copy is the best-evidenced one: 0x4313's block is the same 204 bytes read by the same
  function, and its field names are backed by live capture of the `0x4310` push and the `0x4305`
  reply (OBSERVED.md). `block_204` below is retained only as a byte-accounting mirror; where the
  two disagree, 0x4313 wins. Whether the game-settings *semantics* apply to a 0x4909 record is
  [UNKNOWN] — the byte boundaries are not.

  Note its leading loop is
  **interleaved**: it reads three bytes per iteration for 16 iterations, scattering them into
  three separate 16-byte arrays in the struct — so on the wire it is 16 triples, not three
  runs of 16.

  Total payload: 4 + 4+1+1+1+1 + 2+16 + 4*4 + 204 + 2*4+4 + 64 + 512 + 4*5 + 4+4 + 1
  = **867 bytes**. Nothing here is confirmed live; no capture of this id exists.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: "[ELF 0xd48700] 0 = success; nonzero skips every field below (4-byte payload)."
  - id: unknown_04
    type: u4
    doc: "[UNKNOWN] first word after the result; T+0x000. Read into a stack slot, then stored after the 912-byte memset."
  - id: unknown_08
    type: u1
    doc: "[UNKNOWN] T+0x004."
  - id: unknown_09
    type: u1
    doc: "[UNKNOWN] T+0x005."
  - id: unknown_0a
    type: u1
    doc: "[UNKNOWN] T+0x006."
  - id: flags
    type: u1
    doc: |
      [ELF 0xd487bc-0xd4888c] Read as a 1-byte raw block, then **bit-reversed** into T+0x007:
      wire bit 0 -> 0x80, 1 -> 0x40, 2 -> 0x20, 3 -> 0x10, 4 -> 0x08, 5 -> 0x04, 6 -> 0x02,
      7 -> 0x01. All eight bits are expanded (unlike the clan-record parser, which expands
      three). Individual meanings [UNKNOWN].
  - id: unknown_0c
    type: u2
    doc: "[UNKNOWN] T+0x008."
  - id: name
    type: str
    size: 16
    doc: "[INFERRED] T+0x00a, 16-byte raw block; name-width by analogy. Width is [ELF 0xd488c0]."
  - id: unknown_1e
    type: u4
    doc: "[UNKNOWN] T+0x020 (stored 64-bit-wide)."
  - id: unknown_22
    type: u4
    doc: "[UNKNOWN] T+0x028."
  - id: unknown_26
    type: u4
    doc: "[UNKNOWN] T+0x030."
  - id: unknown_2a
    type: u4
    doc: "[UNKNOWN] T+0x038."
  - id: block
    type: block_204
    doc: "[ELF 0xd48964] The shared 204-byte block read by 0xD4364C into T+0x040."
  - id: unknown_fa
    type: u2
    doc: "[UNKNOWN] T+0x10c."
  - id: unknown_fc
    type: u2
    doc: "[UNKNOWN] T+0x10e."
  - id: unknown_fe
    type: u2
    doc: "[UNKNOWN] T+0x110."
  - id: unknown_100
    type: u2
    doc: "[UNKNOWN] T+0x112."
  - id: unknown_102
    type: u4
    doc: "[UNKNOWN] T+0x114."
  - id: text_64
    type: str
    size: 64
    doc: "[INFERRED] T+0x118, 64-byte raw block — the same width as the 0x4902 text block. Width is [ELF 0xd48a10]."
  - id: text_512
    type: str
    size: 512
    doc: |
      [INFERRED] T+0x159 — note the odd destination: 64 bytes were written at T+0x118 and
      this lands at 0x159, one byte past 0x158. 512-byte raw block, the widest field in the
      lobby protocol. Text is inferred; the width is [ELF 0xd48a30].
  - id: unknown_346
    type: u4
    doc: "[UNKNOWN] T+0x364."
  - id: unknown_34a
    type: u4
    doc: "[UNKNOWN] T+0x368."
  - id: unknown_34e
    type: u4
    doc: "[UNKNOWN] T+0x36c."
  - id: unknown_352
    type: u4
    doc: "[UNKNOWN] T+0x370."
  - id: unknown_356
    type: u4
    doc: "[UNKNOWN] T+0x374."
  - id: unknown_35a
    type: u4
    doc: "[UNKNOWN] T+0x378 (stored 64-bit-wide)."
  - id: unknown_35e
    type: u4
    doc: "[UNKNOWN] T+0x380 (stored 64-bit-wide)."
  - id: unknown_362
    type: u1
    doc: "[UNKNOWN] T+0x388, last field; the 912-byte record ends at 0x390."
types:
  block_204:
    doc: |
      [ELF 0xD4364C] Shared 204-byte block; nine call sites, listed in the top-level doc.
      **Canonical model: `mgo2_cmd_4313_s2c.ksy` type `game_settings`** — this is a mirror kept
      for byte accounting only. Offsets below are
      relative to the block's own destination. The leading section is **interleaved on the
      wire**: 16 iterations of {u8 -> +0x00+i, u8 -> +0x10+i, u8 -> +0x20+i}, so the wire
      order is triple(0), triple(1) ... triple(15) while the struct holds three 16-byte
      arrays. Every field's meaning is [UNKNOWN]; only positions and widths are established.
    seq:
      - id: triples
        type: triple
        repeat: expr
        repeat-expr: 16
        doc: "[ELF 0xd43678-0xd436e4] 16 wire triples scattering into three 16-byte arrays at +0x00/+0x10/+0x20."
      - id: unknown_30
        type: u1
        doc: "[UNKNOWN] +0x30."
      - id: unknown_31
        type: u1
        doc: "[UNKNOWN] +0x31."
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] +0x32, 16-byte raw block (0xD5D018 r5=16, [ELF 0xd43730]). **Not a
          string.** An earlier revision of this file typed it `str name`, "[INFERRED] name-width
          by analogy" — inferred from the width alone, against capture evidence that already
          existed. This is the weapon-restriction bitfield: one bit per item, 1 = locked, byte 0
          bit 0 the master enable. The 2026-07-22 single-variable sweep confirmed it weapon by
          weapon, nineteen for nineteen, at `0x4310` wire `0xD5`..`0xE4` (OBSERVED.md, "The
          weapon-restriction table, confirmed weapon by weapon"); `0x4310`'s copy of this block
          starts at wire `0xA3`, and `0xA3 + 0x32 = 0xD5`. The mapping is corroborated at six
          other offsets in the same capture — max characters `0xE5` = +66 (direct); then, with
          `0x4310` omitting the same fields `0x4305` omits, briefing `0xE6` = +68, tolerance
          `0xF7` = +95, level-limit base `0xF8` = +96, commonA/B `0x142`/`0x143` = +177/+178.
          16 bytes of ISO-8859-1 text is what a 16-byte bitfield looks like from the width alone.
      - id: unknown_42
        type: u1
        doc: "[UNKNOWN] +0x42."
      - id: unknown_43
        type: u1
        doc: "[UNKNOWN] +0x43."
      - id: unknown_44
        type: u4
        doc: "[UNKNOWN] +0x44."
      - id: unknown_48
        type: u4
        doc: "[UNKNOWN] +0x48."
      - id: unknown_4c
        type: u4
        doc: "[UNKNOWN] +0x4c."
      - id: unknown_50
        type: u2
        doc: "[UNKNOWN] +0x50."
      - id: unknown_52
        type: u2
        doc: "[UNKNOWN] +0x52."
      - id: unknown_54
        type: u4
        doc: "[UNKNOWN] +0x54."
      - id: unknown_58
        type: u4
        doc: "[UNKNOWN] +0x58."
      - id: unknown_5c
        type: u2
        doc: "[UNKNOWN] +0x5c."
      - id: unknown_5e
        type: u1
        doc: "[UNKNOWN] +0x5e."
      - id: unknown_5f
        type: u1
        doc: "[UNKNOWN] +0x5f."
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: "[ELF 0xd43884-0xd43a60] Eighteen consecutive 4-byte reads into +0x60 .. +0xa4. All [UNKNOWN]; no loop in the code, eighteen unrolled call sites."
      - id: unknown_a8
        size: 2
        doc: "[UNKNOWN] +0xa8, read as a 2-byte raw block (not a u16 — 0xD5D018 with r5=2)."
      - id: unknown_aa
        type: u2
        doc: "[UNKNOWN] +0xaa."
      - id: unknown_ac
        type: u4
        doc: "[UNKNOWN] +0xac."
      - id: unknown_b0
        type: u1
        doc: "[UNKNOWN] +0xb0."
      - id: unknown_b1
        size: 2
        doc: "[UNKNOWN] +0xb1, 2-byte raw block."
      - id: unknown_b3
        type: u1
        doc: "[UNKNOWN] +0xb3."
      - id: unknown_b4
        type: u2
        doc: "[UNKNOWN] +0xb4."
      - id: unknown_b6
        type: u2
        doc: "[UNKNOWN] +0xb6."
      - id: unknown_b8
        type: u4
        doc: "[UNKNOWN] +0xb8."
      - id: unknown_bc
        type: u1
        doc: "[UNKNOWN] +0xbc."
      - id: unknown_bd
        type: u1
        doc: "[UNKNOWN] +0xbd."
      - id: unknown_be
        size: 14
        doc: "[UNKNOWN] +0xbe, 14-byte raw block; ends the 204-byte block at +0xcc."
  triple:
    seq:
      - id: a
        type: u1
        doc: "[UNKNOWN] -> array A[i] at block+0x00+i."
      - id: b
        type: u1
        doc: "[UNKNOWN] -> array B[i] at block+0x10+i."
      - id: c
        type: u1
        doc: "[UNKNOWN] -> array C[i] at block+0x20+i."
