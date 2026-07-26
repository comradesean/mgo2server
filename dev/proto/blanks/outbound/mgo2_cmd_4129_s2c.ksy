meta:
  id: mgo2_cmd_4129_s2c
  title: "MGO2 0x4129 — post-game info reply (server -> client)"
  endian: be
doc: |
  Reply to `0x4128`. Parser **0xd3c9a8** (GAME dispatcher 0xd38804, trampoline 0xd39080), wait
  slot 26 (0x1a).

  Shape: a 14-byte head, then the **same skill-record loop `0x4125` uses**, into the same table
  (`charTable + 11440 + id*12`), then a 20-byte tail. Total wire size = **34 + 4*count**, which is
  exactly the 34-byte empty readback we send with count 0.

      0xd3ca14  u32       -> scratch (unused further)
      0xd3ca40  u8        -> ctx+30333        <- 0x4122's `rank`
      0xd3ca5c  u32       -> ctx+22776        <- 0x4101's `experience`
      0xd3ca78  u8        -> ctx+35585        <- 0x4101's `unknown_129`
      0xd3ca94  u32 count -> scratch
      0xd3caa8  loop: u8 id, u16 exp, u8      (bottom entry; exits `i >= count` or `i == 128`;
                                               id sign-extended, must be > 0)
      then, in order: u32 -> ctx+35588, u32 -> ctx+22780, u32 -> ctx+23660, u32 -> ctx+29304,
      u16 -> ctx+29326, u8 -> ctx+29325, u8 -> ctx+29360.

  ## The skill records, decoded 2026-07-26

  The loop writes the 12-byte record documented in `dev/proto/mgo2_cmd_4125.ksy`: id at +0,
  experience widened to u32 at +4, flag at +8. **Level is derived, not sent** — `0x6FC580` gives
  `min(exp >> 13, 3)`, so the only reachable levels are 0/1/2/3 at exp 0/8192/16384/24576. The
  flag byte at +8 is what the client's per-skill gates read, including the training check at
  `0x897320` on skill 17; we send 0 for every skill.

  Unlike `0x4125` this parser does **not** memset the array first, so it patches records in place
  and any id it omits keeps whatever `0x4125` established.

  **What makes this command legible is where it writes**, not what it is called: every tail
  destination is a slot some *other* command owns — `ctx+29304` is `0x4122`'s `clan_id`,
  `ctx+29325`/`+29326` are the first two elements of `0x4122`'s unknown prefix, `ctx+29360` is
  `0x4122`'s `emblem_flag`, `ctx+22776`/`+22780` are `0x4101`'s `experience` and `unknown_13e`,
  and `ctx+35585`/`+35588` are `0x4101`'s two unknown singles. So `0x4129` is a **partial
  re-send of the connect-burst character record after a match** — experience, rank, skills and
  the clan block, patched in place. That is a strong hint that `0x4101`'s and `0x4122`'s unknown
  slots at those addresses are match-mutable values (rating, clan standing), not constants.

  This is also where OBSERVED.md's "skill records come from `0x4129`, not `0x4125`" comes from:
  both write the same table, but only `0x4129` is sent after a round.
doc-ref: dev/docs/PROTOCOL.md "0x4128 — post-game info"; dev/docs/OBSERVED.md
seq:
  - id: unknown_00
    type: u4
    doc: "[UNKNOWN] Wire 0x00. Read into scratch and, as far as the trace shows, never stored — no result comparison either. Position exact, meaning unestablished."
  - id: rank
    type: u1
    doc: "[INFERRED] Wire 0x04 -> ctx+30333, the slot `0x4122` fills with `rank`. Name is by destination, not by any read here."
  - id: experience
    type: u4
    doc: "[INFERRED] Wire 0x05 -> ctx+22776, the slot `0x4101` fills with `experience`."
  - id: unknown_09
    type: u1
    doc: "[UNKNOWN] Wire 0x09 -> ctx+35585. Same slot as `0x4101`'s `unknown_129`."
  - id: count
    type: u4
    doc: "[ELF] Wire 0x0a. Skill-record count. We send 0."
  - id: skills
    type: skill_record
    repeat: expr
    repeat-expr: count
    doc: "[ELF] 4 wire bytes each; identical record and identical destination table to `0x4125`."
  - id: unknown_tail_0
    type: u4
    doc: "[UNKNOWN] -> ctx+35588. Same slot as `0x4101`'s `unknown_13a`."
  - id: unknown_tail_1
    type: u4
    doc: "[UNKNOWN] -> ctx+22780. Same slot as `0x4101`'s `unknown_13e`."
  - id: unknown_tail_2
    type: u4
    doc: "[UNKNOWN] -> ctx+23660. Not written by any other command traced so far."
  - id: clan_id
    type: u4
    doc: "[INFERRED] -> ctx+29304, the slot `0x4122` fills with `clan_id`."
  - id: unknown_tail_4
    type: u2
    doc: "[UNKNOWN] -> ctx+29326, the first element of `0x4122`'s 12 x u16 unknown prefix array."
  - id: unknown_tail_5
    type: u1
    doc: "[UNKNOWN] -> ctx+29325, the u8 that opens `0x4122`'s unknown prefix (original value `01`)."
  - id: emblem_flag
    type: u1
    doc: "[INFERRED] -> ctx+29360, the slot `0x4122` fills with `emblem_flag`."
types:
  skill_record:
    seq:
      - id: skill_id
        type: u1
        doc: "[ELF] Sign-extended, must be > 0 (0xd3cb08) or the record is skipped."
      - id: experience
        type: u2
        doc: "[ELF] 2-byte primitive 0xd5cc14, widened into the table record."
      - id: unknown_03
        type: u1
        doc: "[UNKNOWN] Read into the table record; not padding."
