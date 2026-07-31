meta:
  id: mgo2_cmd_4128_c2s
  title: "MGO2 0x4128 — get post-game info (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd3a98c`; the seal `bl 0xd5c828` is the next
  call, no write primitive between, sealed length 0. Wait slot `0x1a` (`li r4,26`). [ELF]

  PROTOCOL.md documents only the `0x4129` reply (`0x8b` bytes); it does not state the request
  shape. The ELF settles it: there is no request payload, so the server must key the results
  card off the connection's selected character alone. [ELF]
doc-ref: dev/docs/PROTOCOL.md "0x4128 — get post-game info"
seq: []
