meta:
  id: mgo2_cmd_43a6_c2s
  title: "MGO2 0x43a6 — in-match single-id command (client -> server)"
  endian: be
doc: |
  Builder function `0xD40D40` = `f(ctx, u32 arg)` (`stw r4,1416(r1)` at `0xD40D6C`);
  `bl 0xD5CF40` at `0xD40DB4` (`li r4,0x43A6` at `0xD40DB0`). One `0xD5C9BC` (u32) write at
  `0xD40DC4`, seal `0xD5C828` at `0xD40DD0`, flush `0xD34CC0` at `0xD40DE0`. Not encrypted.
  **Total payload 4 bytes.**

  No validation of the argument at all — it is staged and written straight through. Reply `0x43A7`.

  ## Identified 2026-07-27: this is the INSTRUCTOR half of a graduation

  Sole call site `0x27E0E4`, inside the graduate action `0x27E050`, immediately after that function
  sets the "graduated" bit on the target's roster entry:

      27e08c-27e0a0  entry[8] |= 0x00010000          ; the bit 0x6D8C70 tests
      27e0a4         sess = 0x2810E0()
      27e0b0-27e0d4  rec = 0x27EF90((idx & 0xFF) + 1); 0x27F160(rec, 332, 4, &v)
      27e0e4         0xD40D40(sess, v)               -> this command

  Gated on `0x26E958()` (I am the instructor) and `0x26EA58() & 0x2000`. So the argument is
  **character-record field 332** of the graduating student, fetched through the replicated-variable
  accessor `0x27F160`, not a chara id the server assigned. [PROVED as to provenance; the meaning of
  field 332 itself is UNKNOWN — see the live note below.]

  **The graduation flow is two commands from two different machines:**

  | command | sender | carries |
  | --- | --- | --- |
  | `0x43A6` | the **instructor's** client | student's record field 332 |
  | `0x43C8` | the **student's** client | star rating + the recognition answer |

  Live, 2026-07-27: one session graduated two different students back to back and the instructor's
  client sent `00000003` then `00000002` — the students' character ids 3 and 2, in that order. An
  earlier session sent `00000003` for character 3. So **field 332 carries the student's character
  id** [INFERRED, three samples, two of them distinguishing]. Still worth one capture with an id
  above 255 to rule out a slot index that happens to track our small id space.

  Eligibility is decided entirely on the instructor's machine before this is sent: `0x6D8BB0` scans
  24 roster slots per tick and fires approval event `0x16002A` — the "%s - Approved for graduation"
  strings, `n002a` 3087/3093 — once a per-slot accumulator passes `5,400,000` (`0x6D8C10`), zeroed
  when the slot empties (`0x6D8CA8`). Session time, never sent to us, and no level, experience or
  skill check anywhere near it.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: unknown_00
    type: u4
    doc: |
      [UNKNOWN meaning; PROVED provenance] 0x00. Position and width exact from `0xD40DC4`. The value
      is **character-record field 332** of the student being graduated, read via `0x27F160(rec, 332,
      4, &v)` at `0x27E0D4` and passed straight to the builder. Observed `00000003` live while
      graduating character id 3 — consistent with a chara id but not evidence for it, since a second
      graduation of a different student sent the same value. Resolved later the same day: a session
      that graduated two students sent `00000003` then `00000002`, matching character ids 3 and 2 in
      order, so this identifies the **student being graduated** [INFERRED]. A capture with an id
      above 255 would settle whether it is the id itself or a slot index tracking it.
