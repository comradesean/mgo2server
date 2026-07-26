meta:
  id: mgo2_cmd_4130_c2s
  title: "MGO2 0x4130 — update personal info (client -> server)"
  endian: be
doc: |
  **158 bytes exactly (0x9e).** Evidence: builder call site `bl 0xd5cf40` at `0xd3bbb4`.
  The write primitives between it and the seal (`bl 0xd5c828`, after `0xd3bdb0`) are:

    * five `bl 0xd5c8a0` (write-u8), sources `r31 + 2 .. r31 + 6`;
    * fourteen `bl 0xd5c8a0` (write-u8), sources `r31 + 16 .. r31 + 29`;
    * a **five**-iteration loop of `bl 0xd5c8a0`, source `r31 + 30 + i`
      (`cmpdi cr7,r28,5` / `bne cr7,0xd3bd38`);
    * a **five**-iteration loop of `bl 0xd5c8a0`, source `r31 + 35 + i`
      (`cmpdi cr7,r28,5` / `bne cr7,0xd3bd60`);
    * one `bl 0xd5c8a0`, source `r31 + 60`;
    * `bl 0xd5d0ac` (write-blob, `r5 = 128`), source `r31 + 68`.

  5 + 14 + 5 + 5 + 1 + 128 = **158**, which pins PROTOCOL.md's "at least 158 bytes" to exactly
  158. Wait slot `0x19` (`li r4,25`). [ELF]

  **Two refinements over PROTOCOL.md's request table.** It splits the middle as
  "`0x13` 4 x u8 skills 1-4 / `0x17` 1 u8 skipped / `0x18` 4 x u8 skill levels 1-4 /
  `0x1c` 2 skipped". The ELF shows both runs are **five**-element loops over contiguous
  five-slot source arrays (`r31+30..34` and `r31+35..39`), so the wire carries five skill slots
  at `0x13`..`0x17` and five level slots at `0x18`..`0x1c` — the "skipped" bytes at `0x17` and
  `0x1c` are the fifth element of each array, not padding. The remaining "skipped" byte at
  `0x1d` is a separate single u8 from a distant source (`r31 + 60`), so it belongs to neither
  array. [ELF]

  Only the appearance and the comment are persisted; skills and levels are read and echoed back
  in `0x4131` but not stored. **Operator policy / gap**, not protocol.
doc-ref: dev/docs/PROTOCOL.md "0x4130 — update personal info"
seq:
  - id: upper
    type: u1
    doc: "[CONFIRMED] wire 0x00, source +2."
  - id: lower
    type: u1
    doc: |
      [CONFIRMED] wire 0x01, source +3. This field is the strongest evidence that `0x3101`'s
      historic skip of appearance+3 was a bug: the same value arrives here named.
  - id: face_paint
    type: u1
    doc: "[CONFIRMED] wire 0x02, source +4."
  - id: upper_color
    type: u1
    doc: "[CONFIRMED] wire 0x03, source +5."
  - id: lower_color
    type: u1
    doc: "[CONFIRMED] wire 0x04, source +6."
  - id: head
    type: u1
    doc: "[CONFIRMED] wire 0x05, source +16. Start of the fourteen-byte gear/colour run."
  - id: chest
    type: u1
    doc: "[CONFIRMED] wire 0x06, source +17."
  - id: hands
    type: u1
    doc: "[CONFIRMED] wire 0x07, source +18."
  - id: waist
    type: u1
    doc: "[CONFIRMED] wire 0x08, source +19."
  - id: feet
    type: u1
    doc: "[CONFIRMED] wire 0x09, source +20."
  - id: accessory1
    type: u1
    doc: "[CONFIRMED] wire 0x0a, source +21."
  - id: accessory2
    type: u1
    doc: "[CONFIRMED] wire 0x0b, source +22."
  - id: head_color
    type: u1
    doc: "[CONFIRMED] wire 0x0c, source +23."
  - id: chest_color
    type: u1
    doc: "[CONFIRMED] wire 0x0d, source +24."
  - id: hands_color
    type: u1
    doc: |
      [CONFIRMED] wire 0x0e, source +25. The other field `0x3101` historically skipped;
      confirmed live when a character created with 0 gained a real value here.
  - id: waist_color
    type: u1
    doc: "[CONFIRMED] wire 0x0f, source +26."
  - id: feet_color
    type: u1
    doc: "[CONFIRMED] wire 0x10, source +27."
  - id: accessory1_color
    type: u1
    doc: "[CONFIRMED] wire 0x11, source +28."
  - id: accessory2_color
    type: u1
    doc: "[CONFIRMED] wire 0x12, source +29."
  - id: skills
    type: u1
    repeat: expr
    repeat-expr: 5
    doc: |
      [ELF] wire 0x13..0x17, source +30..+34. **Five** slots, from a five-iteration loop — the
      byte our reader documents as "0x17 skipped" is slot index 4 of this array. Slots 0..3 are
      the four equipped skills the UI shows; what slot 4 is for is **[UNKNOWN]** (a fifth
      equip slot the expansion added, or a sentinel). `0x4122` and `0x4131` both carry only
      four skills plus a zero byte in the corresponding place, which is consistent with slot 4
      being sent as 0 today — worth logging rather than assuming.
  - id: skill_levels
    type: u1
    repeat: expr
    repeat-expr: 5
    doc: |
      [ELF] wire 0x18..0x1c, source +35..+39. Five slots, same reasoning as `skills`; the byte
      documented as the first of "0x1c 2 skipped" is slot index 4 here.
  - id: unknown_1d
    type: u1
    doc: |
      [UNKNOWN] wire 0x1d, source **+60** — a lone u8 from a source offset 20 bytes past the
      level array, so it is structurally unrelated to it despite being adjacent on the wire.
      Our reader skips it. `0x4131` writes a zero in the corresponding slot.
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    doc: |
      [CONFIRMED] wire 0x1e..0x9d, source +68. Persisted; echoed back at `0x4131` offset 0x36
      and rendered on the player card (`0x4221` / `0x4103`, fingerprint-confirmed).
