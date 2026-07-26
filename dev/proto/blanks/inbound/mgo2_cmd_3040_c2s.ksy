meta:
  id: mgo2_cmd_3040_c2s
  title: "MGO2 0x3040 — unidentified account-lobby request (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd37b70`
  (`li r4,12352` = `0x3040` at `0xd37b6c`), sender `0xd37b00`. One write primitive before the
  seal: `bl 0xd5c8a0` (write-u8) at `0xd37b80`, from stack `1416(r1)` — the sender's `r4`
  argument, spilled at `0xd37b24`. Seal `0xd37b8c`, flush `0xd37b9c`, wait slot `0x0d`
  (`li r4,13` at `0xd37ba4`). [ELF]

  Confirms PROTOCOL.md's correction note: "`0x3040` has a live builder (`0xD37B6C`, one u8) —
  it *can* be sent". Still unanswered by our server and by every reference. [ELF]
doc-ref: dev/docs/PROTOCOL.md "Send-side corrections" (0x3040)
seq:
  - id: index
    type: u1
    doc: |
      [ELF] Range-limited by the sender: `cmplwi cr6,r4,7` at `0xd37b20` and `bgt` to the
      error exit at `0xd37bcc` (returns -24), so the client will never send a value above 7.
      That 0..7 bound is the **same** bound `0x3103` (select character) and `0x3105` (delete
      character) enforce on their one-byte index, and the character grid in `0x3049` is
      likewise eight entries — so this is very likely a character-slot index too.
      **[INFERRED]** from the shared bound and the account-lobby sender neighbourhood
      (`0xd37b00` sits between the `0x3105` sender at `0xd37918` and the `0x3048` sender at
      `0xd37bf0`); the operation it names is **[UNKNOWN]**.
