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

      [ELF 2026-08-03] A third, independent confirmation of the whole field order: the
      client's appearance validator `0x93E008` checks each slot against an item-id range, and
      the ranges partition exactly as these fields do — face <= 10, upper 11..21, lower
      22..27, face_paint <= 11, upper/lower_color <= 31, head 28..45, chest 68..85, hands
      46..56, waist 86..101, feet 57..67, accessory1/2 102..123, gear colours <= 31 except
      accessory colours <= 34. **Out-of-range values are replaced with the range's base id**,
      so a bad `chara_gear` row is silently rewritten by the client rather than rejected —
      a hazard to know when a served appearance seems to "correct itself".
    seq:
      - id: gender
        type: u1
        doc: |
          [CONFIRMED] appearance+0.

          [ELF 2026-08-03] **The create screen never writes its staging slot**
          (`createScreen+125`): no store lands on it anywhere in the image, and the appearance
          editor's write set excludes it (its block base is `editorObj+112`, and
          `stb/lbz ...,112(r31)` appears nowhere in `0x92xxxx`). Gender is edited only by the
          profile appearance sub-editor `0x93E008`, clamped to 0/1 at `0x93E06C`-`0x93E07C`,
          which operates on a different object. So at creation this byte, like `unknown_09`,
          carries whatever the 3.97 MB screen allocation left there — worth logging alongside
          it on the next live creation.
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
        doc: |
          [CONFIRMED] appearance+7.

          [ELF 2026-08-03] **On the wire this is the menu index + 7** (`0x88DAAC`-`0x88DAC0`
          adds 7 immediately before the copy-out; `0x888AF8`/`0x88A7A0` subtract it back), and
          the client's own validator accepts only **7..15**, forcing 7 otherwise
          (`0x93E150`-`0x93E168`). Consequence for the server: a `0x4122`/`0x4131` echo
          outside 7..15 is silently rewritten client-side, never rejected.
      - id: pitch
        type: u1
        doc: |
          [CONFIRMED] appearance+8.

          [ELF 2026-08-03] Valid range **0..31, default 15** (validator `0x93E16C`-`0x93E17C`;
          the create screen's constructor also defaults it to 15 at `0x888280`/`0x88828C`).
      - id: unknown_09
        type: u4
        doc: |
          [UNKNOWN value — NO WRITER; the negative is closed, ELF 2026-08-03] appearance+9..+12.
          **One u32, not four loose bytes** — written by a single `bl 0xd5c9bc` at `0xd37f64`
          from the 4-aligned source `r31+0x1c`, while every neighbouring field uses the u8
          writer. Skipped by our reader; the write path emits four zeros in the corresponding
          slot of `0x3049`/`0x4122`.

          The sender `0xd37de4` has exactly one `bl` site, **`0x88DAE0`** (OPD `0x1029020`
          unreferenced, `ET_EXEC`, no `b` tail call). It stages the payload on the stack in two
          string-move pairs — `lswi/stswi` 32 bytes from `r31+108` at `0x88DAC4`-`0x88DAC8`,
          then 16 bytes from `r31+140` at `0x88DAD4`-`0x88DAD8` — one contiguous 48-byte copy
          split only because `lswi` tops out at 32. So `struct[k] = createScreen[108+k]`, and
          the C layout is exactly the 16/9/4/14 the sender reads at `r31+0` / `+0x11..0x19` /
          `+0x1c` / `+0x20..0x2d`: `char name[17]; u8 gender; u8 face..lower_color[6];
          u8 voice; u8 pitch; /*pad 26,27*/ u32 unknown_09; u8 head..accessory2_color[14];
          /*pad 46,47*/`. **This u32 is `createScreen+136..139`.**

          **[ELF 2026-08-03] Nothing writes it — the write set of the staging struct is now
          closed.** The 2026-08-01 sweep's false negative on gender/voice/pitch is resolved:
          the missing writers were never in the editor. voice/pitch are written by the create
          screen's own state machine **`0x88CD2C`** (the 2026-08-01 note's `0x88CD30` is the
          `mflr`; 34 states, inline jump table at `0x88CF00`): `0x88D954`/`0x88D958` (state
          18), `0x88DAC0` (**voice += 7**, state 23, immediately before the copy-out),
          constructor default pitch=15 at `0x88828C`, back-outs `0x888AF8`/`0x88A7A0`
          (voice −= 7); state 15 writes face at `0x88D8E4`; and `0x888B28` (state 9) is a
          third writer of the 20 editor fields. **gender is the correction — see its field.**

          Complete writer enumeration of `createScreen+108..155`: `0x88D330`
          memset(+108,0,17), `0x88D34C` bounded convert, `0x88D35C` trailing-space trim (the
          name); `0x88D8E4` (face); the six voice/pitch sites above; `0x888B28`'s block
          `0x888C5C`-`0x8891B4` and the editor commit `0x929C94`-`0x929D84` (struct 18..23 and
          32..45). **Struct 17, 26, 27, 28..31, 46, 47 have no writer.** Six scans back this;
          the three that close the 2026-08-01 aliasing hole: every store image-wide at
          displacement 124/125/134-139/154/155 (24 hits, zero in `0x88xxxx`, all other-object
          bases); every store image-wide at displacement 16/17/26-31/46/47 — the same bytes
          via a `createScreen+108` alias (54 hits; the only two right-shaped are the
          lookalikes below); and every access to the editor's parked pointer `editorObj+312` —
          22 dereference sites image-wide, all inside `0x929298` (read) and
          `0x929C94`-`0x929D84` (commit), write set = read set = {18..23, 32..45}. `0x922F0C`
          has exactly two callers: `0x88D9EC` (r4 = createScreen+108) and `0x8D9A68` (r4 = 0,
          the profile path).

          So the value on the wire is **whatever the allocation left there**: `createScreen`
          is one 3,966,048-byte heap block (`bl 0xC2D18` at `0x888224`, constructor
          `0x8881E4`) — the structural fact that makes this module legible — and the
          constructor initialises exactly one byte of this struct (pitch). Whether `0xC2D18`
          zeroes is not statically decidable (it dispatches through vtable slot +20 of an
          allocator singleton whose pointer is `.bss` `0x131C760`), so this is either a
          constant zero or four bytes of uninitialised heap. The cheap settling move is
          unchanged — log it on a real character creation — and a nonzero value is now
          diagnostic (uninitialised heap) rather than mysterious.

          Two traps found while looking, worth leaving behind:

          * `0x8841E4`-`0x8842A0` looks exactly like the answer — a long run of `stb` into
            offsets 16..38 of an `r31`, including `stb r0,28(r31)` at `0x884250` — and is
            **not** this struct (re-verified 2026-08-03: `0x88407C`'s object has fields at
            0,2,3,4,8,12,16..38 and a 24-byte string at +306 — an avatar/player-card
            descriptor).
          * The other `createScreen+108` users flagged 2026-08-01 (`0x88EA7C`, `0x88ED68`,
            `0x88FB00`, `0x88FDD0`) are now *proved* to belong to a different screen module:
            they load their object from `lwz r30,-28796(r2)`; the create screen uses
            `-28800`.
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
