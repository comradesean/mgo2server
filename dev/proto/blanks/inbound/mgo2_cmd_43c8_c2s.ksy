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
doc-ref: dev/docs/PROTOCOL.md "0x43ca is never sent — the client sends 0x43c8"
seq:
  - id: rating_or_config
    type: u4
    doc: |
      [CONFIRMED on the training path] 0x00. First argument, written verbatim. Observed carrying
      the **instructor rating** — 5 and 3 in two runs that varied only the stars awarded. Explicitly
      **not** a round/game token (ELF-proven, see doc). Whether it means something else on a
      non-training round is untested.
  - id: unknown_04
    type: u1
    doc: "[UNKNOWN] 0x04. Second argument, written verbatim. Observed as 0x21 (33) in both training runs, unchanged while the rating varied."
