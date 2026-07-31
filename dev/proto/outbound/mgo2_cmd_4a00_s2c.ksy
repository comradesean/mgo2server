meta:
  id: mgo2_cmd_4a00_s2c
  title: "MGO2 0x4A00 - unmapped 0x4Axx record reply (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes
  0x4A00; COMMANDS.md lists the 0x49xx/0x4Axx/0x4Bxx blocks only as "parsed but never sent".
  Field ORDER and WIDTH below are read out of the client parser and are solid. MEANINGS are
  not - almost every field is [UNKNOWN] on purpose.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39850,
  parser 0xD50E94.
  The largest of the 0x4Axx replies that is not the 0x4A24/0x4A31 pair. It embeds the shared
  204-byte sub-record read by 0xD4364C (see type `block_204`), so a server must emit that block
  byte-exact or every field after it lands in the wrong place.

  0x4A00 WRITES obj+0x298, the value 0x4A02 / 0x4A22 / 0x4A29 later validate their echo id
  against (0xD50FA8 stores it; 0xD4F050 / 0xD514D0 / 0xD50B88 read it back). [INFERRED] from
  the matching offset and direction, not from a capture: 0x4A00 opens the exchange those three
  continue.
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230 and therefore easy to
  miss when reading this parser alone: u32 then u16. Both are validated against the client's
  currently open object for this subsystem (u32 vs obj+0x000 at 0xD4929C, u16 vs obj+0x29C at
  0xD492D4); a mismatch aborts with -1018 (0xFFFFFC06) before another byte is consumed. For
  command id 0x4960 only, 0xD49230 skips both comparisons and just consumes the six bytes.
  Modelled below as `obj_id` + `obj_serial`; the names describe the check, not a proven meaning.
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
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230."
  - id: new_id
    type: u4
    doc: "[ELF] read at 0xD50FA8 and STORED at obj+0x298 - the value the 0x4A02/0x4A22/0x4A29 echo check compares against. Not itself validated here. [UNKNOWN] meaning."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD50FC4 -> obj+0x004."
  - id: blob
    size: 128
    doc: "[ELF] exactly 128 bytes, byte-at-a-time loop 0xD50FD8-0xD51000 (bound base+128). [UNKNOWN] contents."
  - id: block
    type: block_204
    doc: "[ELF] the shared 204-byte sub-record, read by 0xD4364C (called at 0xD51014) into obj+0x0B0."
  - id: unknown_after_block
    type: u4
    doc: "[UNKNOWN] read at 0xD5102C (-> r1+116). Position exact, meaning unestablished."
  - id: flags
    type: u1
    doc: |
      [ELF] read as a 1-byte RAW (0xD5104C, 0xD5D018 len 1) and then expanded bit by bit into a
      64-bit flags word with `oris` (0xD5105C onward) - so each bit is a distinct boolean, the
      same construction as mgo2_cmd_4902.ksy's flags byte. No consumer identified. [UNKNOWN].
  - id: unknown_last
    type: u1
    doc: "[UNKNOWN] last byte, read at 0xD51154. Position exact, meaning unestablished."
types:
  block_204:
    doc: |
      [ELF] The 204-byte sub-record read by the shared helper 0xD4364C. That helper has NINE
      call sites, not just this family: 0xD445A4 (0x4313), 0xD48440 (0x4905), 0xD48964 (0x4909),
      0xD4B244 (0x4987), 0xD4CB08 (0x4950), 0xD5006C (the shared 0x4A24/0x4A31 parser),
      0xD51014 (0x4A00), 0xD5AF38 (0x4E10), 0xD5B78C (0x43F1).
      **CANONICAL MODEL: mgo2_cmd_4313_s2c.ksy, type `game_settings`.** That copy is the
      best-evidenced one - same 204 bytes, same reader, but its field names are backed by live
      capture (the 0x4310 push and the 0x4305 reply, OBSERVED.md). This type is a byte-accounting
      mirror; where the two disagree, 0x4313 wins. Enumerated read-by-read from
      0xD4364C-0xD43BC0. Size is certain; whether the game-settings meanings carry over to a
      0x4Axx record is [UNKNOWN], the byte boundaries are not.
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
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] 16-byte raw read (0xD43730) -> block+0x32. **Not a string.** An earlier
          revision typed this `str text_0x32`, "string role from the width and 0xD5D018's NUL
          behaviour only" - inferred from width alone, against capture evidence that already
          existed. It is the weapon-restriction bitfield: one bit per item, 1 = locked, byte 0
          bit 0 the master enable, confirmed weapon by weapon (nineteen for nineteen) by the
          2026-07-22 single-variable sweep at 0x4310 wire 0xD5..0xE4 (OBSERVED.md). 0x4310's
          copy of this block starts at wire 0xA3 and 0xA3 + 0x32 = 0xD5. See
          mgo2_cmd_4313_s2c.ksy for the full bit map and the corroborating offsets.
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
