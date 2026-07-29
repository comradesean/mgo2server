meta:
  id: mgo2_cmd_4131_s2c
  title: "MGO2 0x4131 — update-personal-info reply (server -> client)"
  endian: be
doc: |
  Reply to `0x4130`. Parser **0xd3c3dc** (GAME dispatcher 0xd38804, trampoline 0xd390e0), wait
  slot 25 (0x19).

  `u32 result` first; **non-zero skips the whole body** (0xd3c470 `cmpwi r0,0; bne -> 0xd3c6f0`),
  so an error reply is legitimately four bytes (`C0FFEE02`, `C0FFEE01`). On zero the parser reads
  into a stack scratch and, only after a clean parse, `memcpy`s **200 bytes** from scratch+0 into
  the character record (0xd3c714).

  ### Two corrections to PROTOCOL.md

  1. **The parser reads 182 bytes, not 186.** PROTOCOL.md's table ends with
     "`0xb6` | 4 | u32 | face-paint colour unlock mask — `0xffffffff`, all colours". There is no
     read after the 128-byte comment: the arm goes straight from 0xd3c6e0 (the comment) to
     `READ_END` at 0xd3c6f4. Those last four bytes are **never parsed**. Harmless (we send them
     and the client ignores them), but the reply's true length is 182 and the "unlock mask" has no
     evidence behind it in this direction.
  2. **Five skill slots, not four** — the same correction as `0x4122`. The three loops are
     `cmpdi/cmpw` against scratch bounds giving exactly 5, 5 and 5 iterations
     (0xd3c644 -> scratch+30..34, 0xd3c66c -> scratch+35..39, 0xd3c694 -> scratch+40..59 as u32s),
     followed by a single u8 at scratch+60. PROTOCOL.md's "4 skills / zero / 4 levels / zero /
     4 x u32 / 5 zero" covers the identical 31 bytes with the padding in the wrong places.

  The scratch layout is the **same struct `0x4122` writes** (`ctx+30136`): 19 clothing bytes at
  struct +2..+6 and +16..+29, skills at +30, levels at +35, experience at +40, the odd u8 at +60,
  the comment at +68. Note the first group lands at struct **+2**, i.e. it fills appearance bytes
  2..6 only — bytes 0, 1, 7 and 8 (the create-time-only appearance fields) are deliberately not
  touched by an outfit change.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4131 — 186 bytes"
seq:
  - id: result
    type: u4
    doc: "[ELF] Wire 0x00. Zero gates the entire body; the client wants its own values back rather than a bare result code, which is why this reply is not a four-byte sibling."
  - id: body
    type: echo_body
    if: result == 0
    doc: "[ELF] Present only when result == 0."
types:
  echo_body:
    seq:
      - id: clothing_a
        size: 5
        doc: |
          [ELF] Wire 0x04 -> struct +2..+6, five separate u8 reads. Per PROTOCOL.md's `0x4130`
          request order: upper, lower, face paint, upper colour, lower colour. That these land at
          appearance index 2 is the parser's own statement, and it matches: indices 0/1 are the
          create-only fields.
      - id: clothing_b
        size: 14
        doc: "[ELF] Wire 0x09 -> struct +16..+29, fourteen separate u8 reads. Head, chest, hands, waist, feet, accessory 1, accessory 2, head colour, chest colour, hands colour, waist colour, feet colour, accessory 1 colour, accessory 2 colour."
      - id: skills
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: "[ELF] Wire 0x17 -> struct +30 + i. **Five**. Echoed back from the request; PROTOCOL.md notes the server does not persist them."
      - id: skill_levels
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: "[ELF] Wire 0x1c -> struct +35 + i. Five."
      - id: skill_experience
        type: u4
        repeat: expr
        repeat-expr: 5
        doc: |
          [ELF] Wire 0x21 -> struct +40 + i*4. **Five** u32s, 20 bytes — per-skill experience for
          the equipped slots, in the same order as `skills`.

          PROTOCOL.md recorded this as "fixed `0x600000`, as in `0x4122`", and we sent that
          constant until 2026-07-29. It is inherited and was never explained: `0x600000` is
          `0x6000 << 8`, i.e. **256x the client's legal maximum of 24576**, and the validator at
          `0x93E418` ZEROES any record above that instead of clamping. It was inert rather than
          correct — the range check runs on the `0x4129` roster, which we do not send, and
          `0x600000 >> 13` clamps to level 3 like any large value, so every equipped skill simply
          rendered as maxed.

          Now the stored value from `chara_skill`, through the same floor-and-clamp helper `0x4122`
          uses. **The two must agree** because they write the SAME destination (`struct +40 + i*4`),
          so whichever arrived last wins.

          What is NOT established: **no reader of `struct +40` has been identified.** Whether any
          screen renders per-skill experience is unknown, and the case for keeping the two packets
          consistent is correctness, not a rendering claim.

          Level is derived, never sent: `min(experience >> 13, 3)` at `0x6FC580`.
      - id: unknown_35
        type: u1
        doc: "[UNKNOWN] Wire 0x35 -> struct +60. The lone byte after the experience array, matching `0x4122`'s `unknown_6a`."
      - id: comment
        size: 128
        type: str
        encoding: ISO-8859-1
        doc: |
          [ELF] Wire 0x36 -> struct +68, fixed 128. Echoed back; this is the only field of the
          request that is persisted alongside the appearance.

          **THE PAYLOAD ENDS HERE — 182 bytes.** [ELF `0xD3C3DC`] the parser's last read is this
          128-byte block at `0xD3C6E0` and it falls straight into READ_END at `0xD3C6F4` with no
          read in between. Total consumed 4+19+5+5+20+1+128 = 182.

          We wrote **186** until 2026-07-29, the extra u32 being an `0xffffffff` labelled
          "face-paint colour unlock bitmask". Nothing reads it — no instruction in the text span
          touches the struct slots those bytes would occupy. The label was not merely unevidenced
          but impossible: face paint is a SINGLE byte at struct `+4`, so a one-bit-per-colour mask
          has no colour axis to apply to. Inherited from a reference server with the value.

          Over-sending was harmless, which is why it survived: READ_END (`0xD5C858`) does no length
          check, and the read helpers bound the cursor against the 1024-byte receive buffer rather
          than the payload, so the parser never knows how long the packet was.

          Note what `0x4131` deliberately does NOT carry, unlike `0x4122`: chara_id (struct +64),
          rank (+197), the emblem flag and the saved instructor. It is an appearance-only echo, and
          its 200-byte memcpy-in/memcpy-out pair PRESERVES those slots rather than overwriting
          them.
