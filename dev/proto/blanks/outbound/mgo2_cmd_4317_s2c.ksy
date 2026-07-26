meta:
  id: mgo2_cmd_4317_s2c
  title: "MGO2 0x4317 — server -> client: create-game result (reply to 0x4316)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4317` at `0xD3895C` -> stub `0xD39200` ->
  parser **`0xD44260`**. Request-status slot **37**.

  PROTOCOL.md's layout (`{s32 result, u32 new game id}`, 8 bytes on success, 4 on failure) is
  ELF-correct, with one detail worth writing down: **both u32s are read before the result is
  tested.** The parser reads `result` (`0xD5CC64`), then `game_id` (`0xD5CCD8`), and only then
  branches — nonzero result goes to the `0xD5BDA0`/`0xD5B41C` error path, zero result stores
  `game_id` at `ctx+0x10000-28936` (the client's current-game id). Either way slot 37 is
  completed with `result`.

  Consequence for the 4-byte failure form PROTOCOL.md documents (`C0FFEE02`, `C0FFEE20`,
  `C0FFEE01`): the second read runs past the payload into stale receive-buffer bytes. That is
  harmless *here* because the value is discarded on the error branch, but it is the same
  unchecked-read behaviour that makes short payloads dangerous elsewhere (the primitives
  bound-check the 1023-byte buffer, not the payload length). **Sending 8 bytes always, with
  game id 0 on failure, costs nothing and removes the read-past.**

  Also of note: COMMANDS.md files `0x4317` twice — once under "replies we send that the client
  parses" and once under "result singles / parsed but never sent". The first is right; the
  second entry is stale bookkeeping, and it is not a result single in any case.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4317"
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD442C0] wire 0x00. 0 = created. Completes request-status slot 37 whatever its value."
  - id: game_id
    type: u4
    doc: |
      [ELF 0xD442D8] wire 0x04. The new game's id, stored at `ctx+0x10000-28936` **only when
      result is 0**. Read unconditionally, so it must be present; on failure its value is
      ignored.
