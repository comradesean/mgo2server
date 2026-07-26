meta:
  id: mgo2_cmd_3107_c2s
  title: "MGO2 0x3107 — check character name (client -> server)"
  endian: be
doc: |
  **16 bytes.** Evidence: builder call site `bl 0xd5cf40` at `0xd37d5c`
  (`li r4,12551` = `0x3107` at `0xd37d58`), sender `0xd37cc0`. One write primitive:
  `bl 0xd5d0ac` (write-blob) at `0xd37d70` with `r5 = 16` and `r4 =` the sender's second
  argument (a `char*`). Seal `0xd37d7c`, flush `0xd37d8c`, wait slot `0x12` (`li r4,18`).
  [ELF]

  Two guards run on the name **before** the packet is built, and both are worth knowing
  because they bound what the server can ever receive:
  `bl 0xdcc7f8` (strlen) at `0xd37d20` with `cmplwi cr7,r3,16` — a name of strlen > 16 is
  rejected locally (returns -24, nothing sent) — and `bl 0xd32dd0` at `0xd37d34`, a
  client-side character-set validator; a zero return also aborts before the builder. [ELF]

  Confirms PROTOCOL.md "Confirmed from the binary as 16 bytes of name". [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x3107 — check character name"
seq:
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: |
      [ELF] Copied as a raw 16-byte blob from the candidate string, so the tail past the
      terminator is whatever the client's name buffer held — treat everything after the first
      NUL as padding, not data. strlen <= 16 is enforced client-side, which means a
      16-character name arrives with **no** terminator inside the field.
