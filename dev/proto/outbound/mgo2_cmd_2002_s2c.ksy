meta:
  id: mgo2_cmd_2002_s2c
  title: "MGO2 0x2002 — lobby-list start (server -> client)"
  endian: be
doc: |
  Opens the gate lobby list (reply 1/3 to `0x2005`). Parser arm 0xd36260, GATE dispatcher
  0xd361e8.

  **The parser reads no bytes.** The arm calls `READ_BEGIN` (0xd5c844) and then `READ_END`
  (0xd5c858) back to back with nothing in between; its whole effect is to reset the list at
  `ctx+0x750`: `count = 0` (stw at `4(r28)`) and `marker = -1` (stw at `0(r28)`). The `-1`
  marker is what `0x2003` and `0x2004` require in order to run at all.

  Guard: `lwzu r31,1872(r28)` then `cmpwi r31,0; bne -> bail(-73)` — the list marker must
  already be **0** (i.e. no list in progress) or the packet is rejected.

  Contradiction with PROTOCOL.md (recorded, not resolved): PROTOCOL.md's `0x2005` table gives
  `0x2002` as "4 bytes: 00000000 (result, GameError.NONE)". The four bytes are harmless but
  they are **not read** — unlike `0x2009` and `0x4211`, the sibling start packets in other
  triples, which do read one u32. See also dev/proto/README.md's note that the list start/end
  packets are "a single u32 result code": true for the `0x46xx` triples, false for `0x2002`.
doc-ref: dev/docs/PROTOCOL.md "0x2005 — get lobby list"; dev/docs/LOBBIES.md
seq:
  - id: unknown_body
    size-eos: true
    doc: |
      [ELF] Not read. We send `00 00 00 00`; the parser at 0xd36260 never opens it. Kept as we
      send it because it is what the list end (`0x2004`) also carries and changing it proves
      nothing.
