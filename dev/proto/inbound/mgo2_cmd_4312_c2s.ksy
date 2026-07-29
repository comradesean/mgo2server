meta:
  id: mgo2_cmd_4312_c2s
  title: "MGO2 0x4312 — get game details (client -> server)"
  endian: be
doc: |
  **Four bytes.** Evidence: builder call site `bl 0xd5cf40` at `0xd413c0`. One write
  primitive: `bl 0xd5c9bc` (write-u32) at `0xd413d0` from stack `1416(r1)`. Seal immediately
  after; wait slot `0x24` (`li r4,36`). [ELF]

  **This retires a PROTOCOL.md caveat.** That section says of the request: "That is what echo
  and mgo2-server parse and it matches the reply's echo of the id, but **the sender has not
  been located in the binary**". It is located: `bl 0xd5cf40` at `0xd413c0`, one u32 and
  nothing else, so the four-byte read the handler performs is correct on tier-1 evidence
  rather than on reference agreement. [ELF]

  The 372-byte-plus-players reply `0x4313` (parser `0xD44388`) is server -> client and is not
  described here.
doc-ref: dev/docs/PROTOCOL.md "0x4312 — get game details"
seq:
  - id: game_id
    type: u4
    doc: |
      [ELF] The selected game's id. The `0x4313` reply must echo it: if a game is currently
      selected the client requires the reply's id field to match.
