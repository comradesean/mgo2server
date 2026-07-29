meta:
  id: mgo2_cmd_4a25_c2s
  title: "MGO2 0x4a25 — unidentified subsystem, no payload (client -> server)"
  endian: be
doc: |
  EMPTY PAYLOAD — zero bytes after the 24-byte transport header, established positively
  from the ELF, not left unmapped.

  Evidence (ELF, retail BLUS30109): sender 0xD4F620, signature (session) only. Builder
  `bl 0xD5CF40` at 0xD4F6A8 (`li r4,0x4a25` at 0xD4F6A0) is followed immediately by the
  seal `bl 0xD5C828` at 0xD4F6B4 and the flush `bl 0xD34CC0` at 0xD4F6C4 — no serializer
  call in between (none of 0xD5C86C/0xD5C8A0, 0xD5C8D4/0xD5C918,
  0xD5C95C/0xD5C9BC/0xD5CA1C, 0xD5CA7C, 0xD5CADC, 0xD5D0AC). The builder memsets its
  1024-byte buffer and resets the cursor, so the sealed length is 0.

  Preconditions: session != NULL, the two generic connection checks (0xD38504, 0xD3844C),
  and 0xD4908C must return non-zero — i.e. `session+0x6BA8` must be set — else -1007
  (0xFFFFFC11) and no packet. (Contrast 0x49C2, which requires the *same* slot to be clear.)
  On a successful flush the flow state advances via `0xD32E08(session, 89, 1)`.

  Because the payload is empty the server must resolve the subject from session state alone.
  COMMANDS.md/PROTOCOL.md file 0x4A25/0x4A30/0x4A40 as an unidentified subsystem whose
  server->client side includes lists at 0x4A11/0x4A33/0x4A42; the sibling sender at 0xD4F7E8
  compares an inbound id against **0x4A42**, which is direct evidence that this family's
  replies are list-shaped. Its reply id is not readable from this sender, though.

  Never observed live; not answered by this server.
seq: []
