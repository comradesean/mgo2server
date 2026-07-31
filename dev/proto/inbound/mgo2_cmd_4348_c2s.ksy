meta:
  id: mgo2_cmd_4348_c2s
  title: "MGO2 0x4348 — unidentified in-match command (client -> server)"
  endian: be
doc: |
  **Empty payload — confirmed from the ELF.** Builder function `0xD4A834`; `bl 0xD5CF40` at
  `0xD4A8A4` (`li r4,0x4348` at `0xD4A89C`), seal `0xD5C828` at `0xD4A8B0`, flush `0xD34CC0`
  at `0xD4A8C0`. No write primitive between builder and seal, and the sender takes no payload
  argument (only the context in `r3`, null-checked at `0xD4A83C`). Not encrypted.

  Listed in `COMMANDS.md` as an unanswered gap in the in-match/host family. `PROTOCOL.md`
  notes only that mgo2-server *names* `0x4348` "host pass" (tier 4, disregarded). Since the
  frame carries no bytes at all, whatever it means is carried entirely by the connection
  context — a bare notification. Reply is `0x4349` (parsed by the client per COMMANDS.md).
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq: []
