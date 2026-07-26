meta:
  id: mgo2_cmd_3103_c2s
  title: "MGO2 0x3103 — select character (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd37a80`
  (`li r4,12547` = `0x3103` at `0xd37a7c`), sender `0xd37a0c`. One write primitive:
  `bl 0xd5c86c` (write-u8) at `0xd37a90` from stack `1416(r1)` (the `r4` argument, spilled at
  `0xd37a38`). Seal `0xd37a9c`, flush `0xd37aac`, wait slot `0x10` (`li r4,16`). [ELF]

  Confirms PROTOCOL.md exactly, including its "the client bounds-checks the index <= 7 before
  sending" claim: `lbz r0,1416(r1)` / `cmplwi cr7,r0,7` / `bgt` to the error exit at
  `0xd37a5c`..`0xd37a6c`. [CONFIRMED from the binary]
doc-ref: dev/docs/PROTOCOL.md "0x3103 — select character"
seq:
  - id: index
    type: u1
    doc: |
      [ELF] Index into the eight-entry grid last sent by `0x3049`. The client refuses to send
      anything above 7. Our server clamps out-of-range to 0 — **operator policy**, and
      unreachable given the client-side check.
