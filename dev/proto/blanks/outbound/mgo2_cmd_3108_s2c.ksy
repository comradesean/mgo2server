meta:
  id: mgo2_cmd_3108_s2c
  title: "MGO2 0x3108 — check-character-name result (server -> client)"
  endian: be
doc: |
  Parser arm **0xd37154** (ACCOUNT dispatcher 0xd37074). Reads exactly one u32 (primitive
  0xd5cc64 at 0xd37180), then `notify(event 18, state 2)` at 0xd32e08 and `notify(event 18,
  value)` at 0xd32e70. Nothing else is read.

  ### This closes a flagged item

  PROTOCOL.md states twice (the `0x3108` reply section, and flagged item 2 of its summary) that
  "**the reply shape is inferred, not read** — the `0x3108` arm itself was never disassembled. It
  works, so the risk is low, but it is a guess." It is no longer a guess: the arm is at 0xd37154,
  it is a single u32, and the inference from the sibling result packets was correct. Request-status
  id 18 (0x12) also matches what OBSERVED.md recorded for it.

  Reminder from PROTOCOL.md, unchanged and still important: this reply is **not optional**. With
  nothing sent back the client waits ~40s, never sends `0x3101`, and fails `0A41:FFFFFF60`.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x3108 — 4 bytes"; dev/docs/OBSERVED.md
seq:
  - id: result
    type: u4
    doc: |
      [ELF] Wire 0x00. The whole payload. 0 for "name available"; PROTOCOL.md lists the same
      rejection codes `0x3102` uses. Signedness is not recoverable from the primitive (it
      assembles four bytes with no sign handling).
