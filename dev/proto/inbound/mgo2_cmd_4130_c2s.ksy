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
  - id: echoed_from_4131_60
    type: u1
    doc: |
      [CONFIRMED as an echo, ELF 2026-08-01; renamed from `unknown_1d`] wire 0x1d, source **+60**
      — a lone u8 from a source offset 20 bytes past the skill-level array, so it is structurally
      unrelated to it despite being adjacent on the wire. **Meaning still [UNKNOWN]; the fate is
      now closed: this byte is server-authored, stored, and handed straight back.** Nothing on the
      client ever chooses it.

      **The struct is named.** Two of the three callers of the `0x4130` sender `0xD3BB28` pass
      `0xD3A094(session) + 7648` (`addi r4,r4,7648` at `0x91D73C`, `addi r4,r3,7648` at
      `0x9CB4E8`), so `r31` is **`profile + 7648`** and this field is **`profile + 7708`**. The
      third caller, `0x93E7C0`, passes a screen-local copy at `screen+108`.

      **The only writer is the reply parser.** `0x4131`'s parser runs `r27 = profile + 7648`
      (`addi r27,r31,7648` at `0xD3EDBC`) and reads the packet field by field into it, ending
      `+60` (`addi r4,r27,60` at `0xD3F0F4`, `bl 0xd5cb8c` = read-u8), `+64` (u32), `+68` (128-byte
      comment), `+197`. So the server's byte lands here and this command sends it back unchanged.
      That upgrades the old note "`0x4131` writes a zero in the corresponding slot" from a
      statement about our current output to a statement about the *mechanism*: it is zero because
      we send zero.

      **The client's own change detector skips it, which is the load-bearing observation.**
      `0x93E5B4`-`0x93E720` is the "has the player edited anything?" comparator that gates the
      send. It compares the working copy against the stored one at offsets **0..8**, **16..29**,
      then a five-iteration loop over **+30+i**, **+35+i** and a u32 at **+40+4i** — i.e. it
      enumerates every field the personal-info screen can edit, including the five-slot arrays,
      and **never touches +60**. A byte the editor's own equality test excludes is a byte the
      editor does not own.

      The same comparator incidentally sizes the region between the arrays and this field: **+40
      to +59 is a five-element u32 array** (`lwz r0,40(r11)` with `r5` stepping by 4, `0x93E77C`),
      read by the `0x4131` parser through `0xd5cc64` at `0xD3F0DC`. So `+60` is the byte
      immediately after that array, not padding inside it.

      Searches run, and their limits: `,7708(rN)` has twelve hits image-wide and **none** in the
      MGO code ranges (they are libc-band `stw`/`sthu` at `0x559D0`-`0x56750`, `0x412DC0`,
      `0xE00D78`, `0xE6B3AC`, `0xF32C78`, `0xF32EDC`, `0xF4AD98`, `0xF4AFFC`); `addi rX,rY,7708`
      has none anywhere. Both edges are justified by the struct being addressed as a fixed
      displacement off the profile pointer everywhere else in this file. What that does **not**
      cover is a reader working from the `screen+108` copy, where the field would appear at
      `screen+168`; that alias was not swept.
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    doc: |
      [CONFIRMED] wire 0x1e..0x9d, source +68. Persisted; echoed back at `0x4131` offset 0x36
      and rendered on the player card (`0x4221` / `0x4103`, fingerprint-confirmed).
