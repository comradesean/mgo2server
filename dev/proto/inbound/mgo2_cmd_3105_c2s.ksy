meta:
  id: mgo2_cmd_3105_c2s
  title: "MGO2 0x3105 — delete character (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd3798c`
  (`li r4,12549` = `0x3105` at `0xd37988`), sender `0xd37918`. One write primitive:
  `bl 0xd5c86c` (write-u8) at `0xd3799c` from stack `1416(r1)` (the `r4` argument, spilled at
  `0xd37944`). Seal `0xd379a8`, flush `0xd379b8`, wait slot `0x11` (`li r4,17`). [ELF]

  The sender is byte-for-byte the same shape as `0x3103`'s, including the `cmplwi cr7,r0,7` /
  `bgt` bound at `0xd37968`..`0xd37978`. So the request is identical to select-character, as
  PROTOCOL.md says. [CONFIRMED from the binary]
doc-ref: dev/docs/PROTOCOL.md "0x3105 — delete character"
seq:
  - id: index
    type: u1
    doc: |
      [ELF] Index into the `0x3049` grid; client-side bound 0..7. Our server clamps
      out-of-range to the **last** character here rather than the first — **operator policy**
      inherited from a comment, and unreachable given the client-side check.
