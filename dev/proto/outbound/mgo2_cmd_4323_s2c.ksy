meta:
  id: mgo2_cmd_4323_s2c
  title: "MGO2 0x4323 — server -> client: join-failed ack (reply to 0x4322)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4323` at `0xD38974` -> stub `0xD39220` ->
  parser **`0xD40904`**. Request-status slot **39**.

  A bare result ack, and one of the twelve byte-identical 196-byte parsers laid out from
  `0xD3FFD4` to `0xD40904`: verify the id, one `0xD5CC64` u32 read, `0xD32E08(ctx, 39, 2)`,
  `0xD32E70(ctx, 39, result)`. Nothing else is read or stored. Matches PROTOCOL.md ("the reply
  parser at 0xD40904 reads a single u32 result, so 0x4323 is a bare acknowledgement").

  Context worth keeping attached to this id: `0x4322` is what the client sends ~40 s after a
  successful `0x4321` when the peer-to-peer connection to the host never formed (observed live
  2026-07-21). Answering it converts a hang into a clean failure — **it is a symptom handler,
  not a fix**, and the peer link remains the open frontier.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x4322 — join failed"
seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] The only field. 0 = success; the joiner is dropped from the game they failed to enter. [ELF 0xD40960]"
