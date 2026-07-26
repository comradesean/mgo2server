meta:
  id: mgo2_cmd_43e2_c2s
  title: "MGO2 0x43e2 — automatch subsystem command (client -> server)"
  endian: be
doc: |
  **Empty payload — confirmed from the ELF.** Builder function `0xD5BBDC`; `bl 0xD5CF40` at
  `0xD5BC4C` (`li r4,0x43E2` at `0xD5BC44`), seal `0xD5C828` at `0xD5BC58`, flush `0xD34CC0`
  at `0xD5BC68`. No write primitive between builder and seal; the sender takes no payload
  argument beyond the context (null-checked at `0xD5BBE4`). Not encrypted.

  It sits in the same code region as `0x43E0` (`0xD5BCB4`, the automatch status fetch), so
  this is the second half of that subsystem — `PROTOCOL.md` records `0x43E0` as "sent on entry
  to the automatching lobby"; `0x43E2` is a bare follow-up notification with no arguments.
  Unanswered today (`COMMANDS.md` gap list); reply id `0x43E3`.
doc-ref: dev/docs/PROTOCOL.md "0x43e0 — automatch status fetch"
seq: []
