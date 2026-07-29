meta:
  id: mgo2_cmd_4100_c2s
  title: "MGO2 0x4100 — character connect (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd3aa64`. The seal `bl 0xd5c828` follows
  immediately with no write primitive between, so the sealed length is 0. Wait slot `0x15`
  (`li r4,21`), which is exactly the slot PROTOCOL.md records state 3 of the `0x946F00`
  machine arming and state 4 waiting on with `1037:FFFFFF60`. [ELF, CONFIRMED]

  The reply is the nine-packet connect burst; those are server -> client and are not
  described here.
doc-ref: dev/docs/PROTOCOL.md "0x4100 — character connect"
seq: []
