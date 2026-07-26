meta:
  id: mgo2_cmd_43c4_c2s
  title: "MGO2 0x43c4 — in-match enumerated command (client -> server)"
  endian: be
doc: |
  Builder function `0xD40E2C` = `f(ctx, u32 arg)`; `bl 0xD5CF40` at `0xD40EA8`
  (`li r4,0x43C4` at `0xD40EA4`). One `0xD5C9BC` (u32) write at `0xD40EB8` from `r1+1416`,
  seal `0xD5C828` at `0xD40EC4`, flush `0xD34CC0` at `0xD40ED4`. Not encrypted.
  **Total payload 4 bytes.**

  Worth more than the other single-u32 senders: this one **range-checks its argument**.
  `0xD40E3C`/`0xD40E44`/`0xD40E64` compute `arg - 1` and abort when `(unsigned)(arg-1) > 4`, so
  the client only ever sends **1, 2, 3, 4 or 5**. That makes the field an enumeration, not an
  id — which rules out the "character id" reading the rest of the `0x43xx` family invites.
  Five values in an in-match host command is suggestive (mode? team? round outcome?), but no
  capture exists and nothing is asserted here.

  No `valid:` constraint per `dev/proto/README.md` — the range is documented, not enforced, so a
  first capture outside it reads as a finding rather than a parse error. Reply `0x43C5`.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: unknown_00
    type: u4
    doc: "[ELF] 0x00 — width and position exact; **[UNKNOWN] meaning**, but constrained to 1..5 by the sender's own guard at `0xD40E44` (`cmplwi cr6, arg-1, 4`; `bgt` skips the whole send)."
