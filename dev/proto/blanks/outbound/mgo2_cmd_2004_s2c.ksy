meta:
  id: mgo2_cmd_2004_s2c
  title: "MGO2 0x2004 — lobby-list end (server -> client)"
  endian: be
doc: |
  Closes the gate lobby list (reply 3/3 to `0x2005`). Parser arm 0xd36438, GATE dispatcher
  0xd361e8.

  **The parser reads no bytes**: `READ_BEGIN` (0xd5c844) immediately followed by `READ_END`
  (0xd5c858), then `notify(event 10, state 2)` at 0xd32e08 — the completion that releases the
  lobby-list wait — and `marker = 0` (stw at `0(r31)`), closing the list.

  Guard: `lwzu r0,1872(r31); cmpwi r0,0; beq -> bail(-73)` — the marker must be non-zero, i.e.
  `0x2002` must have run first. Sending `0x2004` without `0x2002` is silently dropped and the
  wait never completes.

  Same contradiction with PROTOCOL.md as `0x2002`: documented as "4 bytes: 00000000", actually
  unread.
doc-ref: dev/docs/PROTOCOL.md "0x2005 — get lobby list"; dev/docs/LOBBIES.md
seq:
  - id: unknown_body
    size-eos: true
    doc: "[ELF] Not read (0xd36438). We send `00 00 00 00`."
