meta:
  id: mgo2_cmd_4132_c2s
  title: "MGO2 0x4132 — outfit commit (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd3a8b4` (sender `0xd3a844`); seal
  `bl 0xd5c828` immediately after with no write primitive between. Wait slot `0x1b`
  (`li r4,27`). [ELF]

  Confirms PROTOCOL.md, which already records the empty payload and slot `0x1b` from a live
  observation on 2026-07-23. [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x4132 — outfit commit"
seq: []
