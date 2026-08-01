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

          **[ELF 2026-08-01] The buffer is located; the writer is not, and the sweep that failed
          to find one is not an elimination.** Recorded in full because the negative half is the
          part that is easy to over-claim.

          The sender `0xd37de4` has exactly one `bl` site, **`0x88DAE0`** (OPD `0x1029020`
          unreferenced, `ET_EXEC`, no `b` tail call). It stages the payload on the stack in two
          string-move pairs — `lswi/stswi` 32 bytes from `r31+108` to `r1+124` at
          `0x88DAC4`-`0x88DAC8`, then 16 bytes from `r31+140` to `r1+156` at
          `0x88DAD4`-`0x88DAD8` — which is one contiguous 48-byte copy split only because `lswi`
          tops out at 32. **So the payload struct is `createScreen + 108`, 48 bytes, and this u32
          is `createScreen + 136`.**

          The appearance editor is `0x922F0C(obj+224, obj+108, obj+352, obj+362)`, called at
          `0x88D9EC`; it parks the payload pointer at `newobj+312` (`stw r25,312(r29)` at
          `0x922FDC`) and every later access goes through `lwz rX,312(rY)`. Enumerating all 25
          such sites in the `0x92xxxx`/`0x93xxxx` band and collecting the offsets each one then
          touches gives the editor's complete write set:

              stores: 18 19 20 21 22 23   32 33 34 35 36 37 38 39 40 41 42 43 44 45
              loads : 18 19 20 32 33 34 35

          i.e. `appearance+1..+6` and `appearance+15..+28`. **Offsets 28..31 — this field — are
          not among them.**

          **That is not yet an elimination, and here is the check that says so.** The same sweep
          also finds no write to offsets **17**, **24** and **25**, which are `gender`, `voice`
          and `pitch` — three fields that demonstrably do get set. So a second writer path into
          this buffer exists and has not been found, and until it has, "the editor never writes
          +28..31" cannot be promoted to "nothing writes +28..31". Per CLAUDE.md, an elimination
          is only valid if the observation that would have confirmed it was actually produced;
          this sweep produced a false negative on three known-good fields in the same buffer, so
          it cannot be trusted on a fourth.

          Two traps found while looking, worth leaving behind:

          * `0x8841E4`-`0x8842A0` looks exactly like the answer — a long run of `stb` into
            offsets 16..38 of an `r31`, including `stb r0,28(r31)` at `0x884250` — and is **not**
            this struct. It copies `profile+7664..7677` then `profile+7648..7656` into an avatar
            descriptor; the offsets coincide, the struct does not.
          * `createScreen+108` is also used as a plain 16-byte name buffer by several other
            screens (`0x88EA7C`, `0x88ED68`, `0x88FB00`, `0x88FDD0` all hand it to the string
            helpers `0x94BB7C`/`0x949F24`), so hits on that address are not evidence about the
            appearance payload.

          The cheap settling move is still the one this note already proposed: log the four bytes
          on a real character creation. What the above adds is that a nonzero value would now have
          a known home to be traced from — `createScreen+136`.
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
