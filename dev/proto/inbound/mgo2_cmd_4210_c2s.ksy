meta:
  id: mgo2_cmd_4210_c2s
  title: "MGO2 0x4210 — own player card / overview request (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd3a7dc` (sender `0xD3A7D4`); the seal
  `bl 0xd5c828` is the next call with no write primitive between. Wait slot `0x20`
  (`li r4,32`). [ELF]

  Confirms PROTOCOL.md's note under `0x4220`: "Sibling, not yet observed: `0x4210`
  (sender `0xD3A7D4`, no payload, subsystem `0x20`)". Still unhandled by the server; expects
  the reply triple `0x4211`/`0x4212`/`0x4213`.
doc-ref: dev/docs/PROTOCOL.md "0x4220 — player details" (0x4210 sibling note)
seq: []
