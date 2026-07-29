meta:
  id: mgo2_cmd_43c8_c2s
  title: "MGO2 0x43c8 — start round (client -> server)"
  endian: be
doc: |
  Builder function `0xD40C40` = `f(ctx, u32 a, u8 b)` (`stw r4,1416(r1)` at `0xD40C70`,
  `stb r5,1424(r1)` at `0xD40C6C`); `bl 0xD5CF40` at `0xD40CB8` (`li r4,0x43C8` at `0xD40CB4`).
  Writes `0xD5C9BC` (u32) at `0xD40CC8` then `0xD5C8A0` (u8) at `0xD40CD8`; seal `0xD5C828` at
  `0xD40CE4`, flush `0xD34CC0` at `0xD40CF4`. Not encrypted. **Total payload 5 bytes.**

  This is the id the client actually sends; `0x43CA` has no builder at all. `PROTOCOL.md`
  records the same `{u32, u8}` shape and the 2026-07-23 renumbering of our handler pair to
  `0x43C8`/`0x43C9`, and — importantly — that the `0x43C8` request is "two config bytes, not an
  id": the start-round reply's token is stored at `session+0x57D8+0x32F8` and provably never
  reaches this builder. Neither field is validated in `0xD40C40`.
  ## The u32 carries the instructor rating

  Live 2026-07-26, two runs of the same combat-training flow varying only the star rating the
  student awards: **5 stars produced `00000005 21`, 3 stars produced `00000003 21`.** Single
  variable, matching both times, so the first field is the rating — at least on this path. The
  caller at `0xA36160` (`bl 0xD40C40`) passes both fields from bytes of one object: the u32 from
  `obj+113` and the u8 from `obj+112`, which is why a "rating" fits a u32-shaped argument.

  That does **not** retire the "start round" name outright: the same builder has one caller and
  the id genuinely is what a round start would use, so it is either overloaded or was never the
  round-start command. Our handler still treats it as `START_ROUND`; see BACKLOG.

  ## Both fields are dialog answers, and the u8 tracks the recognition prompt

  ELF, 2026-07-26. The sole caller `0xA36160` loads both arguments out of one 2-byte dialog result
  buffer at `*(r31+108)`:

      a35b0c  lbz r0,0(r9)      ; result byte 0 -> r31+112
      a35b10  stb r0,112(r31)
      a35b14  lbz r11,1(r9)     ; result byte 1 -> r31+113
      a35b1c  stb r11,113(r31)
      ...
      a36160  lbz r4,113(r31)   ; -> the u32 on the wire   (rating)
      a36164  lbz r5,112(r31)   ; -> the u8  on the wire

  So neither field is "config": both are answers the player gave, and both are single bytes at
  source — the u32 is a byte widened to fit the builder's u32 argument. `r31` is the state object
  of the post-graduation dialog sequence, the same one whose gate at `0xA359A4` decides whether the
  recognition prompt (stage `n002a` string 3099) is shown before the rating prompt (string 3105).

  Five live samples, and the u8 is fully decoded — it is the answer to the prompt that runs before
  the rating screen, plus a bit saying whether that prompt appeared at all:

  | run | stars | payload | recognition prompt |
  | --- | --- | --- | --- |
  | earlier | 5 | `00000005 21` | not shown |
  | 2026-07-27 01:28 | 3 | `00000003 21` | not shown |
  | 2026-07-27 02:40 | 5 | `00000005 01` | shown, **YES** |
  | 2026-07-27 03:27 | 5 | `00000005 00` | shown, **NO** |
  | 2026-07-27 03:27 | 1 | `00000001 01` | shown, **YES** (different character) |
  | 2026-07-27 04:43 | 1 | `00000001 00` | shown, **NO** |
  | 2026-07-27 04:43 | 5 | `00000005 21` | not shown — server sent a saved instructor in `0x4122` |

  The last row is the round trip closing: that character had recognised this instructor earlier, the
  server sent the saved instructor in `0x4122` wire `0xf1`, and the client suppressed the prompt —
  so the field both raises and withholds it, and a saved instructor now survives a login. `0x21`
  appearing a third time, again only when the prompt never ran, is further evidence it is stale
  buffer contents rather than a defined value.

  **[CONFIRMED] `0x00` = no, `0x01` = yes.** Only bit 0 is defined. The `0x21` seen on the two runs
  where the prompt never ran is **not** a "not asked" flag — the ELF shows the dialog result buffer
  is simply never written on that path, so `0x21` is stale memory that happened to be there twice.
  Either way the test is the same, and the trap is worth stating: `(answer & 0x20) == 0` looks like
  the natural rule and is **wrong**, because it reads a declined prompt (`0x00`) as a recognition.
  Only `answer == 0x01` is a yes.

  **The instructor's client sends a different command.** `0x43A6` (builder `0xD40D40`, `li r4,17318`
  at `0xD40DB0`, u32 body, reply slot 48) is sent from the graduate action `0x27E050` on the
  *instructor's* machine, right after it sets the graduated bit `entry[8] |= 0x00010000`; its u32 is
  character-record field 332. So the flow is two commands from two different clients: `0x43A6` the
  instructor's "I graduated them", `0x43C8` the student's rating and recognition answer.

  **Eligibility is an in-session timer on the instructor's machine, and we are never asked.**
  `0x6D8BB0` scans 24 roster slots each tick (instructor-only via `0x26E958`, in-round via
  `0x6EBA90`) and fires the approval event `0x16002A` — the "%s - Approved for graduation" strings
  3087/3093 — once a per-slot accumulator passes **5,400,000** (`0x6D8C10`), provided the slot is
  occupied (`entry[1] <= 2`) and not already graduated (`entry[8] & 0x10000`). The accumulator is
  zeroed the moment the slot empties (`0x6D8CA8`), so it is session time, not lifetime.
  [Threshold PROVED; units INFERRED — the same frame-delta source drives dialog timers elsewhere,
  which reads as milliseconds and therefore 90 minutes. That sits awkwardly against the ~30 minutes
  observed live, so the unit is the open question, not the constant.]

  Two further results from the same runs:

  - **The client does not check level or play time.** `rawr` was shown the prompt with 428
    experience (level 3, under the 500 threshold) and **zero** accumulated play time, then answered
    yes. The player lore that a student must be level 4 with 20 hours is therefore not a client-side
    precondition in this build; the only gate ever found on this prompt is the saved-instructor
    field from `0x4122`. [PROVED by observation — the confirming case would have been the prompt
    being withheld from a character failing both requirements, and it was not withheld.]
  - The rating is independent of the answer: 5 stars accompanied a "no" and 1 star a "yes".

  **Consequence for the server, once confirmed.** This is how we learn a student saved their
  instructor, and we currently parse the byte and throw it away. The client stores the decision in
  `profile+0x32F8`, which is RAM only — on the next login we send `0x4122`'s `saved_instructor` as
  0 and the client forgets. Persisting the answer (and echoing it back in `0x4122`) is what makes
  "cannot be erased once saved" actually true on this server.
doc-ref: dev/docs/PROTOCOL.md "0x43ca is never sent — the client sends 0x43c8"
seq:
  - id: rating_or_config
    type: u4
    doc: |
      [CONFIRMED on the training path] 0x00. First argument, written verbatim. The **instructor
      rating**: 5, 3 and 5 across three runs, matching the stars awarded every time. Sourced from
      byte 1 of the dialog result buffer (`0xA35B14`/`0xA36160`), so it is a u8 value in a u32
      field — only 1..5 is reachable on this path. Explicitly **not** a round/game token
      (ELF-proven, see doc). Whether it means something else on a non-training round is untested.
  - id: unknown_04
    type: u1
    doc: |
      [INFERRED] 0x04. Second argument, written verbatim; byte 0 of the dialog result buffer
      (`0xA35B0C`/`0xA36164`) — the answer to the prompt shown *before* the rating. Observed `0x21`
      on two runs where the recognition prompt never appeared (5 stars and 3 stars) and `0x01` on
      the run where it appeared and was answered YES. Bit `0x20` is the only bit that moves, and it
      moves with the prompt rather than the rating.

      Deliberately still named `unknown_04`: three samples with one single-variable comparison is
      an inference, not a proof, and the confirming observation — a graduation where the prompt is
      answered NO — has not been made. Rename when it has.
