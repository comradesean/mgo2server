meta:
  id: mgo2_cmd_2009_s2c
  title: "MGO2 0x2009 — news-list start (server -> client)"
  endian: be
doc: |
  Opens the news list (reply 1/3 to `0x2008`). Parser arm 0xd36504, GATE dispatcher 0xd361e8.
  Reads exactly one u32 (primitive 0xd5cc64 at 0xd36540), then branches on it.

  Guard first: `lwzu r0,3552(r27); cmpwi r0,0; bne -> bail(-73)` — the news marker at
  `ctx+0xDE0` must already be 0.

  Then, on the value read:
    * **value == 0** (0xd365a0): `notify(event 12, 0)`, then `marker = -1` and `count = 0`. This
      is the path that **opens the list**; `0x200b` refuses to run unless the marker is -1.
    * value != 0 (0xd3656c): `notify(event 12, state 2)` and `notify(event 12, value)` — i.e. the
      value is handed to the UI as a result/error and the list is *not* opened.

  So the u32 is a result code and **must be zero**, matching what we send. Unlike its sibling
  `0x2002`, this start packet genuinely does read its four bytes.
doc-ref: dev/docs/PROTOCOL.md "0x2008 — get news"
seq:
  - id: result
    type: u4
    doc: |
      [ELF] Wire 0x00. Must be 0 to open the list (0xd36564 `cmpwi r31,0; beq`). A non-zero value
      is forwarded to the UI as an error and the news list never opens — `0x200a` records would
      then be appended to a list `0x200b` cannot close.
