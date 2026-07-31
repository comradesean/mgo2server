meta:
  id: mgo2_cmd_4304_c2s
  title: "MGO2 0x4304 — get host settings (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd414c8`; seal `bl 0xd5c828` is the next
  call, no write primitive between. Wait slot `0x22` (`li r4,34`). [ELF]

  Confirms PROTOCOL.md "Empty request". [CONFIRMED]
  The reply `0x4305` (128 bytes empty / `0x163` populated) is server -> client and is the only
  outbound payload this server Blowfish-encrypts; not described here.
doc-ref: dev/docs/PROTOCOL.md "0x4304 — get host settings"
seq: []
