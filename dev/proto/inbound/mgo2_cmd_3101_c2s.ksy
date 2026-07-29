meta:
  id: mgo2_cmd_3101_c2s
  title: "MGO2 0x3101 — create character (client -> server)"
  endian: be
doc: |
  **43 bytes exactly (0x2b).** Evidence: builder call site `bl 0xd5cf40` at `0xd37e88`
  (`li r4,12545` = `0x3101` at `0xd37e84`), sender `0xd37de0`-ish. The write primitives between
  the builder and the seal (`bl 0xd5c828` at `0xd38088`) are, in order:

    * `bl 0xd5d0ac` (write-blob, `r5 = 16`) at `0xd37e9c`, source = the sender's struct pointer
      `r31 + 0`;
    * nine `bl 0xd5c8a0` (write-u8), `0xd37eb0`..`0xd37f3c`, sources `r31 + 0x11 .. r31 + 0x19`;
    * one `bl 0xd5c9bc` (write-u32) at `0xd37f64`, source `r31 + 0x1c`;
    * fourteen `bl 0xd5c8a0` (write-u8), `0xd37f78`..`0xd3807c`, sources
      `r31 + 0x20 .. r31 + 0x2d`.

  16 + 9 + 4 + 14 = **43**. Flush `bl 0xd34cc0` at `0xd38098`; wait slot `0x0f`
  (`li r4,15` at `0xd380b0`). [ELF]

  This settles PROTOCOL.md's open caveat: "The exact appearance length the client sends is
  **not** confirmed; we require at least 27 readable bytes and read exactly 27." It is exactly
  27, and the payload is exactly 43. [ELF]

  It also sharpens the four mystery bytes. PROTOCOL.md's `readAppearance` records "+9, 4,
  **skipped, purpose unknown**". The ELF shows those four bytes are written by a **single
  write-u32 call**, from a naturally 4-aligned source offset (`r31 + 0x1c`) sandwiched between
  two runs of u8s — so they are one 32-bit quantity, not four independent bytes. [ELF]

  Two guards run before the builder, identical to `0x3107`'s: `bl 0xdcc7f8` (strlen) with
  `cmplwi cr7,r3,16` at `0xd37e4c`..`0xd37e58`, and the character-set validator
  `bl 0xd32dd0` at `0xd37e60`. A name that fails either is never sent. [ELF]
doc-ref: dev/docs/PROTOCOL.md "0x3101 — create character"
seq:
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: |
      [CONFIRMED] Copied as a raw 16-byte blob; strlen <= 16 enforced client-side, so a
      16-character name has no terminator inside the field.
  - id: appearance
    type: appearance_create
    doc: "[ELF] 27 bytes. Field order is confirmed by `0x4130`, which names the same sequence."
types:
  appearance_create:
    doc: |
      27 bytes. Named per PROTOCOL.md's `readAppearance`; the ordering is corroborated by
      `0x4130`, which carries the same fields in the same order under names.
    seq:
      - id: gender
        type: u1
        doc: "[CONFIRMED] appearance+0."
      - id: face
        type: u1
        doc: "[CONFIRMED] appearance+1."
      - id: upper
        type: u1
        doc: "[CONFIRMED] appearance+2."
      - id: lower
        type: u1
        doc: |
          [CONFIRMED] appearance+3. Skipped by our reader for years on an inherited claim that
          the original discarded it; the claim was wrong and it is read now. `0x4130` carries
          the same field one slot after `upper`.
      - id: face_paint
        type: u1
        doc: "[CONFIRMED] appearance+4."
      - id: upper_color
        type: u1
        doc: "[CONFIRMED] appearance+5."
      - id: lower_color
        type: u1
        doc: "[CONFIRMED] appearance+6."
      - id: voice
        type: u1
        doc: "[CONFIRMED] appearance+7."
      - id: pitch
        type: u1
        doc: "[CONFIRMED] appearance+8."
      - id: unknown_09
        type: u4
        doc: |
          [UNKNOWN] appearance+9..+12. **One u32, not four loose bytes** — written by a single
          `bl 0xd5c9bc` at `0xd37f64` from the 4-aligned source `r31+0x1c`, while every
          neighbouring field uses the u8 writer. Skipped by our reader; the write path emits
          four zeros in the corresponding slot of `0x3049`/`0x4122`, so nothing is known to be
          lost — and nothing confirms that either. Log it on the next character creation: a
          nonzero value here would immediately be a finding.
      - id: head
        type: u1
        doc: "[CONFIRMED] appearance+13."
      - id: chest
        type: u1
        doc: "[CONFIRMED] appearance+14."
      - id: hands
        type: u1
        doc: "[CONFIRMED] appearance+15."
      - id: waist
        type: u1
        doc: "[CONFIRMED] appearance+16."
      - id: feet
        type: u1
        doc: "[CONFIRMED] appearance+17."
      - id: accessory1
        type: u1
        doc: "[CONFIRMED] appearance+18."
      - id: accessory2
        type: u1
        doc: "[CONFIRMED] appearance+19."
      - id: head_color
        type: u1
        doc: "[CONFIRMED] appearance+20."
      - id: chest_color
        type: u1
        doc: "[CONFIRMED] appearance+21."
      - id: hands_color
        type: u1
        doc: |
          [CONFIRMED] appearance+22. The second field that was wrongly skipped at creation;
          `0x4130` names it as the byte after `chest_color`.
      - id: waist_color
        type: u1
        doc: "[CONFIRMED] appearance+23."
      - id: feet_color
        type: u1
        doc: "[CONFIRMED] appearance+24."
      - id: accessory1_color
        type: u1
        doc: "[CONFIRMED] appearance+25."
      - id: accessory2_color
        type: u1
        doc: "[CONFIRMED] appearance+26."
