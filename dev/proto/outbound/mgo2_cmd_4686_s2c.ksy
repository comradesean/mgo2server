meta:
  id: mgo2_cmd_4686_s2c
  title: "MGO2 0x4686 — match-detail record(s) (item packet of the 0x4684 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Item packet of the 0x4684 match-detail triple (0x4685 start {u32 result} / 0x4686 items /
  0x4687 end {u32 result}). The start/end u32 is a RESULT CODE, not a count — 0 required in
  both (nonzero → dialog 1034:%08X; handlers 0xd3abc8/0xd3aacc, same shape as the 0x4681
  family, ELF-traced 2026-07-23). Requested with the u32 entry id of a 0x4682 list row.
  Records packed back to back, parser 0xd3b42c reads to end of payload and the client counts
  them itself; table caps at 32, 93 bytes each on the wire (struct stride 0x60).

  ## [ELF 2026-08-02] THE CONSUMER WAS FOUND — five of the six fields are now named

  The old header said "every LABEL is unestablished ... No reference payload exists (all upstreams
  stub this empty). Awaiting live fingerprint." **That is superseded.** The client renders this
  table on screen and every field reaches an element whose name the developers wrote themselves,
  so the naming is tier 1 and no capture is needed to get this far.

  **Destination.** The parser computes
  `table = *(u32*)(session + 0x10000 + 6404) + 0x20000 + 29724` (`0xD3B47C`-`0xD3B488`), which is
  `{u32 status; u32 count; record[32]}`: `count` at `table+4` is bounds-checked against 31
  (`0xD3B58C`) and each record is appended at `table + 8 + count*96` (`mulli r3,r3,96` at
  `0xD3B594`) by a 96-byte `memcpy` from a zeroed stack staging block. **Records are 96 bytes in
  memory and 93 on the wire** — the three lost bytes are the client's own NULs after the two
  strings (at `+0x44` and `+0x55`) and one tail pad.

  **Accessor and consumers.** `0xD3A138` returns `table` (or 0 when `table+0` is zero). It has
  exactly **one** caller, `0x91DA48`. Image-wide, `mulli rX,rY,96` returns exactly **seven** sites:
  the two parser appends, two accessors, and **three consumers** — `0x918D00`, `0x91D080`,
  `0x91DB54` — which are three clones of one painter and inline `table + 8 + i*96` rather than
  calling the accessor. All three resolve the same element-name tables, so they render the same
  screen in three states.

  **The screen.** A four-row table; `r22` (the row count, from `0xD3F68C`) is clamped to 4 at
  `0x91DB24`, and `screen+156` is the first record index, so this is a paged view of the 32-record
  table. Per row the painter sets five cells, and every element hash resolves out of the client's
  own name dictionary:

  | cell | element | source |
  | --- | --- | --- |
  | date | `STRING_low1_DATE` .. `STRING_low4_DATE` | `record+0x00` |
  | column 1 | `STRING_low_<row>_1` | `record+0x04`, the 64-byte text, passed raw |
  | column 2 | `STRING_low_<row>_2` | `record+0x45`, the 16-byte name, via `0xAF70F0` |
  | column 3 | `STRING_low_<row>_3` | derived from `record+0x56` and `record+0x58` |
  | column 4 | `STRING_low_<row>_4` | `record+0x5C`, as a bare number |

  Text cells go through `0x943120(screen+108, elementHash, text, 0)`; the number cell through
  `0x943B00(screen+108, elementHash, value, 0)`. The hash arrays live at `0xE1377C+1512` (the four
  DATE elements) and `0xE1377C+1528`/`+1560` (the sixteen `STRING_low_R_C` elements), reached as
  `lwz r29,-32748(r30)` with the module TOC `r30 = 0xFF04E8`.

  Result strings come from the resource group **`mgo2_res_myscore`** (hash `0x1AB3B6`), which is
  this screen's own group and is the developers' name for it.

  ## 0x4686 AND 0x4b75 SHARE THIS TABLE — same address, not merely the same shape

  `0xD3B42C` (this command) and `0xD55E40` (`0x4b75`, the clan twin) are instruction-for-instruction
  identical apart from `cmpwi r0,18054` vs `cmpwi r0,19317` and branch displacements, and both
  compute the destination as the **same expression off the same session argument**:
  `*(u32*)(session+0x10000+6404) + 0x20000 + 29724`. `addi rX,rY,29724` occurs at exactly **12**
  sites image-wide, in two mirrored groups of six (`0xD3A150`/`0xD3AB20`/`0xD3AC1C`/`0xD3B488`/
  `0xD3F650`/`0xD3F6A8` and `0xD544A8`/`0xD54F84`/`0xD55080`/`0xD55E9C`/`0xD5A158`/`0xD5A1B0`), and
  the single initialiser `stw r28,29724(r9)` at `0xD3462C`. So this is one object, not two of one
  layout — whichever of the two lists arrived last is what the screen shows. `0x4686` is the
  better-evidenced twin because the finished consumer is on this side; `0x4b75`'s twin accessor
  `0xD3F634` has zero callers and is dead.

  **`0x4682` is NOT a shared layout — asked and refused.** The tempting inference is that the
  match-history row and the match-detail row are the same record; they are not, and the test is the
  base rather than the shape. `0x4682`'s parser `0xD3B5FC` computes
  `*(u32*)(session+0x10000+6404) + 0x20000 + 27924` (`0xD3B654`), **1,800 bytes below** this one,
  with a 25-byte record and a 64-row cap. Same session pointer, different table, different stride.
  The bijection that does hold is with `0x4b75`, above.

  Field POSITIONS were read from the parser and are unchanged; the LABELS below are new.
doc-ref: dev/docs/PROTOCOL.md "0x4600 / 0x4680 / 0x4684 — player search and match history"
seq:
  - id: records
    type: detail_record
    repeat: eos
types:
  detail_record:
    seq:
      - id: played_at
        type: u4
        doc: |
          [ELF 2026-08-02] `+0x00`, read with `0xD5CCD8` at `0xD3B4DC`. **Unix epoch seconds, UTC**,
          drawn into the row's `STRING_low<row>_DATE` element. Was `unknown_u32_a` ("id?
          (character?)"), which was wrong.

          The chain, and the reason it is a time and not an id: `0x91DB70` `lwz r0,0(r9)` ->
          `std r0,112(r1)` — the same u32-read / 64-bit-store widening this binary uses for every
          `time_t` (`0x4822`'s `time` at `0xD537B8`, `0x4902`'s open/close times) — then
          `addi r3,r1,112` is handed to `0xDC9358`, which issues `sc 144` (the **timezone**
          syscall, not a clock read), converts the returned minutes to seconds
          (`slwi 6` minus `slwi 2` = x60, `0xDC9390`-`0xDC93A0`) and **adds them to the record's
          value**. The result is formatted by `0xDCC7C8(dst, 128, fmt, tm)` with
          `fmt = "%Y/%m/%d %H:%M:%S"` (`0xE14040`, TOC `-32604`).
          So the wire value is UTC and the client does the local-time conversion itself; nothing
          about "now" enters the value.

          **`0xFFFFFFFF` is the not-set sentinel.** `cmpwi r0,-1` at `0x91DB74` takes a branch that
          skips the whole format and writes the empty string `0xE2C538` (TOC `-32708`) into the
          date cell instead, blanking the column. Zero is *not* special-cased and would render
          1970.
      - id: detail_text
        type: str
        size: 64
        doc: |
          [ELF 2026-08-02] `+0x04`, 64 bytes, read with the block primitive `0xD5D018` (`li r5,64`)
          at `0xD3B4FC`; the client NUL-terminates at `+0x44`, which is why 64+1 bytes of struct
          hold 64 bytes of wire. Was `unknown_str64`.

          **The row's primary text cell**, set straight into `STRING_low_<row>_1` at `0x91DBF8`
          (`addi r5,r24,4`) with no conversion and no formatting — the pointer goes to
          `0x943120` as-is. Widest text field in this family.

          The *destination* is proven; **what the operator is meant to read there is not**. It is
          the only free text a row carries besides the 16-byte `name`, and the screen is a
          tournament/survival result table (see `game_type`), so an event or match title is the
          obvious reading — obvious, and not evidenced, so the name says "detail text" and stops
          there.
      - id: name
        type: str
        size: 16
        doc: |
          [ELF 2026-08-02] `+0x45`, 16 bytes, `0xD5D018` (`li r5,16`) at `0xD3B51C`, NUL at `+0x55`.
          Was `unknown_str16`.

          **Rendered as text into `STRING_low_<row>_2`**, and not raw: `0x91DC1C` calls
          `0xAF70F0(dst = stack+200, src = record+0x45, 97)`, which zeroes a 97-byte buffer,
          `strlen`s the source and runs it through the text converter `0xDEABAC` with mode 29 —
          the same treatment the mailbox and roster painters give a character name. 16 bytes is
          the character-name width used throughout this protocol.

          **Whose name is [UNKNOWN]** — exactly as in `0x4822`'s `name`, the client never asks;
          it prints the string in the column the layout gave it.
      - id: game_type
        type: u1
        doc: |
          [ELF 2026-08-02] `+0x56`, read with `0xD5CB8C` at `0xD3B538`. **The game-type enum, the
          same one `0x4682`'s trailing byte carries**, and it selects how `result_value` is
          rendered. Was `unknown_u8`, and its "no reader" status was an artefact of method: **the
          reader is a pointer walk**, `addi r9,r26,-6` / `lbz r0,0(r9)` off a second row cursor
          `r26 = record+0x5C` (`0x91DC54`), which a displacement-only sweep cannot see.

          ```
          3 -> TYPE_TOURNAMENT           result_value is a FINISHING PLACE
          5 -> TYPE_TOURNAMENT_OFFICIAL  (same arm, 0x91DC60 / 0x91DC68)
          4 -> TYPE_SURVIVAL             result_value is a WIN TALLY
          6 -> TYPE_SURVIVAL_OFFICIAL    (same arm, 0x91DD28 / 0x91DD30)
          anything else -> column 3 is set to the empty string 0xE2C538
          ```

          Those four values are 3, 4, 5 and 6 of the nine-arm match-history game-type table at
          `0x91E5C4` (`TYPE_FREEBATTLE`, Automatching, `TYPE_TOURNAMENT`, `TYPE_SURVIVAL`,
          `TYPE_TOURNAMENT_OFFICIAL`, `TYPE_SURVIVAL_OFFICIAL`, the two Training arms, `TYPE_COOP`)
          — see `mgo2_cmd_4682_s2c.ksy` and `dev/docs/LOBBIES.md`. It is the same enum, restricted
          to the four arms that have a result worth printing: a Free Battle, Automatching,
          Training or Co-op row leaves column 3 blank, which is the correct behaviour and not a
          gap.

          **Not served in v1**, and this is the one place it bites: tournament and survival are
          post-launch content, so the only values this field can honestly take on a release-day
          server are the ones that blank column 3.
      - id: result_value
        type: u4
        doc: |
          [ELF 2026-08-02] `+0x58`, read with `0xD5CC64` at `0xD3B554`, and read back by the
          painter through the same `r26` pointer walk (`addi r9,r26,-4`). Was `unknown_u32_b`.
          **Its meaning is chosen by `game_type`:**

          * `game_type` 3 or 5 — a **finishing place**, switched at `0x91DC7C`:
            `1 -> HISTORY_1ST`, `2 -> HISTORY_2ND`, `3 -> HISTORY_3RD`, `5 -> HISTORY_5TH`,
            **anything else (4 included) -> `"-"`** (`0xE2FC20`, TOC `-32600`). The names are
            resolved as `GetString(hash("mgo2_res_myscore") = 0x1AB3B6, hash(name))`.
          * `game_type` 4 or 6 — a **win tally**, formatted at `0x91DD38`-`0x91DD90` as
            `"%d%s"` (`0xE2DCE0`) with `SURVIVAL_WIN` when the value is `<= 1` and
            `SURVIVAL_WINS` when it is greater. A singular/plural split, which is what fixes this
            as a count rather than an ordinal.

          **`u4` is correct and is not a leftover.** The value is an ordinal place or a count, so
          it is unsigned; the `extsw` before the format call is ABI boilerplate and is not
          evidence of a signed type. (`0xD5CC64` and `0xD5CCD8` are byte-identical primitives —
          see `dev/proto/README.md`; neither is a signed accessor.)
      - id: unknown_5c
        type: u4
        doc: |
          [ELF 2026-08-02] `+0x5C`, read with `0xD5CCD8` at `0xD3B570`; the last field of the
          record and the last four bytes on the wire. Meaning **[UNKNOWN]**, and this is a stated
          **open question**, not an unsearched slot.

          What is known, and why it does not settle it: the painter reaches it through the row
          cursor `r26` (`lwa r5,0(r11)` at `0x91DDE8`) and hands it to
          `0x943B00(screen+108, hash(STRING_low_<row>_4), value, 0)` — the **numeric** element
          setter, not the text one. So it is drawn as a bare decimal in column 4 of every row,
          with **no clamp, no format string, no unit and no switch** — nothing anywhere in the
          image branches on it. All three clones of the painter (`0x918D00`, `0x91D080`,
          `0x91DB54`) treat it identically, so there is no second context to compare against, and
          the column's caption is bound in the layout file rather than in the ELF.

          **What would decide it:** the same experiment `0x4b21`'s `unknown_1b34` needs — serve
          recognisable distinct sentinels in this field and in `result_value` on one row each and
          read the printed captions off the CHECK RECORD screen. We control both inputs.
