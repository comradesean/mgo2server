meta:
  id: mgo2_cmd_2007_s2c
  title: "MGO2 0x2007 — gate reply, single u32 (server -> client)"
  endian: be
doc: |
  Parser arm 0xd36498, GATE dispatcher 0xd361a4 (compare tree at 0xd361e8). Reads **exactly one u32** (primitive 0xd5ccd8 at
  0xd364c4) into a scratch, then `std`s it as a 64-bit value to `ctx+0xDD8` (3544) and fires
  `notify(event 11, state 2)` at 0xd32e08.

  Undocumented everywhere: `0x2007` appears in neither PROTOCOL.md, OBSERVED.md nor LOBBIES.md,
  and COMMANDS.md does not list it among the replies we send. Its request side is presumably
  `0x2006`, which COMMANDS.md lists as a sendable-but-unanswered "lobby-layer / isolated" gap.
  So: layout known, meaning not.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: unknown_00
    type: u4
    doc: |
      [UNKNOWN] Wire 0x00. The only field. Stored to `ctx+0xDD8` widened to 64 bits (`lwz` then
      `std` at 0xd364d4/0xd364dc), which is the sole clue to its use — the widening means the
      client keeps it in a 64-bit slot, not a bitfield or a result code compared against
      constants. No error branch: any value is accepted and the wait for event 11 completes.
