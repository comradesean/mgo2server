meta:
  id: mgo2_cmd_2005_c2s
  title: "MGO2 0x2005 — get lobby list (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd36a38` (`li r4,8197` = `0x2005` at
  `0xd36a30`), sender `0xd369d0`. The seal `bl 0xd5c828` is the very next call, at
  `0xd36a44`: no write primitive runs, so the payload length is 0. Flush at `0xd36a54`.
  Wait slot `0x0a` (`li r4,10` at `0xd36a5c`, `bl 0xd32e08`). [ELF]

  Confirms PROTOCOL.md "Request payload is empty and is not read". [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x2005 — get lobby list"
seq: []
