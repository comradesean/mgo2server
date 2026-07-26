meta:
  id: mgo2_cmd_4125
  title: "MGO2 0x4125 — skill table, packet 7/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Parser **0xD3CC8C** (GAME dispatcher 0xD38804, trampoline 0xD39070). Promoted from
  `blanks/outbound` 2026-07-26 after the record's meaning was worked out; the wire layout was
  already read from the ELF before that, and the shape is capture-confirmed (104 bytes on every
  connect).

  ## What it actually is

  Not a menu list: a **sparse write into a 128-entry array of per-skill state** in the profile
  block, indexed by skill id. The parser memsets 1536 bytes (128 x 12) at `profile+11444`
  (0xD3CCEC), then applies each record it is sent. Records are scattered, not appended — the
  record with id N lands at `profile + 11444 + N*12` whatever its position on the wire, and any id
  the server omits stays zeroed.

  `0x4129` (post-game results, parser 0xD3C9B0) embeds the same record loop into the same array
  and does **not** clear first. So `0x4125` establishes the table and `0x4129` patches it.

  ## Client-side record (12 bytes at profile + 11444 + id*12)

      +0  u1  id again — nonzero means "this record exists"
      +4  u4  experience, widened from the u2 on the wire
      +8  u1  flag
  +1..+3 and +9..+11 are stack padding the 12-byte copy carries along; nothing reads them.

  **Level is derived, never sent.** `0x6FC580` computes `min(exp >> 13, 3)` from the u2 at
  record+6 — the low half of the widened u32 — so only four levels exist, at exp 0 / 8192 / 16384
  / 24576. In-match code compares that level against a per-entry requirement byte.

  ## Only 17 skills exist

  The array is 128 entries but the game defines **17 skills, ids 1..17**. The list UI checks
  `(id - 1) <= 16` (0x8DC3A8, and again at 0xB3B530/0xB3B5B0); the equip-cost table at vaddr
  0xE11344 is exactly 18 rows of 3 bytes — row = id, column = level, value = skill points, `00 00
  00` terminator at row 18, read straight out of the ELF; and every id-keyed lookup clamps to 17
  (0x6FC528 plus 28 clamp sites). Total equip budget is 4 points (0x8DC7C4).

  Ids 18..127 are addressable by this parser and defined by nothing — they are stored and listed,
  then clamp to row 17 for cost and name. They are not reserved slots. **We currently send 1..25,
  so eight of them are undefined.**

  Names are not in the binary: they are message ids, `name = 100 + 2*id` (resolved via 0x8E0BF0 at
  0x8DB8CC, 0x8DD73C, 0x8DFFA4, 0x8F9B1C) with level descriptions at `179 + 3*id` (+0/+1/+2). Six
  ids are pinned anyway, because 0x6FCD48 maps weapon id to the skill that earns its experience:
  1 Handgun (weapons 2-16), 2 SMG (17-23), 3 Assault Rifle (24-31), 4 Shotgun (36-38),
  5 Sniper Rifle (39-45), 11 Knife (weapon 1). LMGs (32-35) feed no skill.

  ## This arm is the burst's terminal packet

  After `READ_END` it fires `notify(event 21, state 2)` at 0xD3CDF0 — 21 = 0x15, the wait slot
  `0x4100` blocks on. None of the other burst parsers — `0x4101` (0xD3C120), `0x4120` (0xD3D758),
  `0x4121` (0xD3D684), `0x4122` (0xD3D02C), `0x4124` (0xD3CE30) — notifies anything, so **`0x4125`
  is what releases the connect burst** and it must arrive. Any reordering that moves it earlier
  completes the wait before the rest of the burst is parsed.
doc-ref: dev/docs/PROTOCOL.md "0x4125 — skill catalogue, 104 bytes"
seq:
  - id: num_skills
    type: u4
    doc: "[CONFIRMED] Wire 0x00. We send 25. Loop-exit is `i >= count` or `i == 128` (0xD3CDC0), so a larger count cannot overflow the array."
  - id: skills
    type: skill_record
    repeat: expr
    repeat-expr: num_skills
    doc: "[CONFIRMED] 4 wire bytes each; 12 bytes in the client record."
types:
  skill_record:
    seq:
      - id: skill_id
        type: u1
        doc: |
          [CONFIRMED] skill id, and the array index this record is written to. Sign-extended and
          required to be **> 0** (0xD3CD8C) — id 0 and any id with the top bit set are silently
          skipped, which is consistent with the two readers of record 0's id byte treating it as
          absent.
      - id: experience
        type: u2
        doc: |
          [CONFIRMED] experience, read by the 2-byte primitive 0xD5CC14 and zero-extended into the
          record's u32 slot. The client turns it into a level as `min(exp >> 13, 3)`, so 0x6000
          advertises level 3 and 0x2000 level 1. We send 0x6000 for every skill except 17, 20 and
          22, which get 0x2000 — a split inherited from a reference server (tier 4) with nothing
          behind it. Raising skill 17 to level 3 is known NOT to affect training graduation
          (tested live 2026-07-26).
      - id: flag
        type: u1
        doc: |
          [CONFIRMED PRESENT, MEANING UNKNOWN] third byte, landing at record+8. Read (0xD3CD6C)
          into the record, so it is not padding.

          **Exactly one read of this field exists in the binary, and it is skill 17's**, at
          0x897320. In a training lobby (subtype 7 or 8, checked at 0x8972F4) the client requires
          skill 17's record to be **present** (0x897314, id byte nonzero) and its flag to be
          **zero**; that combination selects screen state 1, which is the state that **sends
          0x43d0** (`li r4,8; bl 0xD3A680` at 0x897758). A nonzero flag falls through to
          0x88616C(9/8/12) and state 3, a different screen path.

          So the flag does not enable or disable a menu entry — the 866/867 row at 0x896054 tests
          only that the record exists, not the flag. What it controls is **whether the client asks
          the server for the training parameters at all**. Zero means "ask".

          Nothing in the binary ever writes this byte: it arrives only from 0x4125/0x4129, i.e.
          from us, and no code compares it against anything but zero. As far as the client is
          concerned it is a boolean, and we have only ever sent the "ask" value. What a nonzero
          value would *mean* is unestablished — only what it would *do*, which is stop the training
          fetch.

          An earlier version of this file listed readers for skills 6, 13, 34 and 85; those were
          false positives from matching displacements without checking base registers
          (0x414060-0x41482C is one unrolled 16-stride struct initialiser that accounts for most of
          them). Filtering to functions that actually reach the profile accessor 0xD3A094 leaves
          three hits, all skill 17.
