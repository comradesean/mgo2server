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
  / 24576. In-match code compares that level against a per-entry requirement byte. A finer ladder
  at `0x6FCBF8` (0, 1, 16, 23, 31, 35, 38, 45, 47, 51, 63, 70, 73 -> levels 1..13) is used by other
  screens; which applies where is not established.

  **We send 25 skills; the client indexes at least 86.** Reads of this array name skills 0, 6, 7,
  13, 17, 34, 50, 51, 52, 54, 55, 85 and 86 — flags for 6/13/17/34/85, experience for 50/51/52/54
  /86 — while `LoadoutWriter` advertises 1..25. Everything above 25 is permanently level 0, flag 0
  for our clients, and what those gates control has never been checked. Skill 34's flag alone has
  nine readers (from 0x5934C8).

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
          into the record, so it is not padding. **This is the field the client's per-skill gates
          test** — skill 6 at 0xC7F6D8/0xC83D04, 13 at 0x8830E8, 17 at 0x897320, 34 at nine sites
          from 0x5934C8, 85 at 0xD8E7C0. We send 0 for every skill, so every one of those gates
          sees "not set". Whether it means owned, unlocked, new or equipped is unestablished.
