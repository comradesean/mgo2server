meta:
  id: mgo2_cmd_4346_c2s
  title: "MGO2 0x4346 — peer register (client -> server)"
  endian: be
doc: |
  Builder function `0xD42E64`; `bl 0xD5CF40` at `0xD42F10` (`li r4,0x4346` at `0xD42F0C`).
  One payload write — `0xD5C9BC` (u32) at `0xD42F20` — then the seal `0xD5C828`
  at `0xD42F2C` and the flush `0xD34CC0` at `0xD42F3C`. Not encrypted.
  **Total payload 4 bytes.**

  The four peer-register senders are consecutive, near-identical functions in one block —
  `0xD42E64` (0x4346), `0xD42FA8` (0x4344), `0xD43100` (0x4342), `0xD43244` (0x4340) —
  each `f(ctx, u32 arg)` staging `r4` at `r1+1432` and writing it verbatim. Only
  `0x4344` has a second argument. `COMMANDS.md` groups `0x4340`-`0x4346` as
  "peer register" and confirms they are Channel A (the client telling the lobby server about a
  peer event); `PROTOCOL.md` records the pair `0x4440`/`0x4344` firing on a host
  Restart, and `0x4342` firing in the kick teardown, but does not decode any payload.
doc-ref: dev/docs/COMMANDS.md "join and peer-register are Channel A"
seq:
  - id: chara_id
    type: u4
    doc: |
      [ELF] 0x00, width and position exact. **[UNKNOWN] meaning** — the sender's only
      argument, passed straight through with no validation, no range check and no context
      lookup. Named `chara_id` only because every other single-u32 in-match command
      (`0x43A0`, `0x43A6`, `0x43C4`) carries a character id; nothing in `0xD42E64`
      proves it. Trace the callers before relying on the name.
