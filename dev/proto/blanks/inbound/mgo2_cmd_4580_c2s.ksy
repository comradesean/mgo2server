meta:
  id: mgo2_cmd_4580_c2s
  title: "MGO2 0x4580 — bulk roster fetch (client -> server)"
  endian: be
doc: |
  Builder function `0xD4628C` = `f(ctx, u8 state)` (`stb r4,1416(r1)` at `0xD462B8`);
  `bl 0xD5CF40` at `0xD46308` (`li r4,0x4580` at `0xD46304`). One `0xD5C86C` (u8) write at
  `0xD46318`, seal `0xD5C828` at `0xD46324`, flush `0xD34CC0` at `0xD46334`. Not encrypted.
  **Total payload 1 byte.** Confirms `PROTOCOL.md`'s "request a single `{u8 state}`".

  New from the ELF: the sender **range-checks the state** at `0xD462A4`
  (`cmplwi cr6,r0,1`, taken before the send), so this request only ever carries **0 or 1** —
  the two list tabs. `0x4500`/`0x4510` carry the same 0/1 state with no such check.
doc-ref: dev/docs/PROTOCOL.md "0x4580 — bulk roster fetch (answered empty)"
seq:
  - id: state
    type: u1
    doc: |
      [ELF] 0x00. Which list to fetch — **0 friends, 1 blocked**, by continuity with
      `0x4500`/`0x4510` where both values are live-confirmed; the sender's own guard restricts
      it to 0 or 1. Reply is a real triple (`0x4581` start / N x `0x4582` 59-byte entries /
      `0x4583` end). **We now serve real entries** (`HostGameController.listRoster`, 2026-07-26):
      the id and name come from `chara_relation`, and the u16 at record wire 0x14 is set nonzero
      because `0x4583` discards any record where it is zero. The rest of the record is still
      zeroed — see `../outbound/mgo2_cmd_4582_s2c.ksy`. Until 2026-07-26 we answered empty on the
      grounds that the 59-byte record could not be filled honestly.
      No `valid:` constraint, per `dev/proto/README.md`.
