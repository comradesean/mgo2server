meta:
  id: mgo2_cmd_4380_c2s
  title: "MGO2 0x4380 — quit game (client -> server)"
  endian: be
doc: |
  **Empty payload — confirmed from the ELF.** Builder function `0xD41274`; `bl 0xD5CF40` at
  `0xD412E4` (`li r4,0x4380` at `0xD412DC`), seal `0xD5C828` at `0xD412F0`, flush `0xD34CC0`
  at `0xD41300`. No write primitive between builder and seal; the sender takes no payload
  argument. Not encrypted.

  So the game being left is **connection-implicit** — the same attribution model the `0x4390`
  trace established (nothing in the frame names the game). Reply `0x4381`.
doc-ref: dev/docs/COMMANDS.md "Client -> server (the client SENDS these)"
seq: []
