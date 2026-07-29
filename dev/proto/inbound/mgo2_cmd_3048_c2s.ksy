meta:
  id: mgo2_cmd_3048_c2s
  title: "MGO2 0x3048 — get character list (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd37c58` (`li r4,12360` = `0x3048` at
  `0xd37c50`), sender `0xd37bf0`. Seal `bl 0xd5c828` at `0xd37c64` with no intervening write
  primitive; flush `0xd37c74`; wait slot `0x0e` (`li r4,14` at `0xd37c7c`). [ELF]

  Confirms PROTOCOL.md "Request payload is not read" — there is nothing to read. [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x3048 — get character list"
seq: []
