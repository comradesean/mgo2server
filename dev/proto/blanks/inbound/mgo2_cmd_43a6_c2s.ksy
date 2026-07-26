meta:
  id: mgo2_cmd_43a6_c2s
  title: "MGO2 0x43a6 — in-match single-id command (client -> server)"
  endian: be
doc: |
  Builder function `0xD40D40` = `f(ctx, u32 arg)` (`stw r4,1416(r1)` at `0xD40D6C`);
  `bl 0xD5CF40` at `0xD40DB4` (`li r4,0x43A6` at `0xD40DB0`). One `0xD5C9BC` (u32) write at
  `0xD40DC4`, seal `0xD5C828` at `0xD40DD0`, flush `0xD34CC0` at `0xD40DE0`. Not encrypted.
  **Total payload 4 bytes.**

  No validation of the argument at all — it is staged and written straight through. Meaning
  unestablished: `COMMANDS.md` and `PROTOCOL.md` both list `0x43A6` only as a sendable,
  unanswered gap in the in-match/host family. Reply `0x43A7`.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: unknown_00
    type: u4
    doc: "[UNKNOWN] 0x00. Position and width exact from `0xD40DC4`; meaning unestablished. A character id is the family-wide pattern (`0x43A0`, `0x43C4`) but nothing in `0xD40D40` narrows it."
