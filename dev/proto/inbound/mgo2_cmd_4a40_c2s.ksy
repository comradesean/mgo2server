meta:
  id: mgo2_cmd_4a40_c2s
  title: "MGO2 0x4a40 — unidentified subsystem, no payload (client -> server)"
  endian: be
doc: |
  EMPTY PAYLOAD — zero bytes after the 24-byte transport header, established positively
  from the ELF, not left unmapped.

  Evidence (ELF, retail BLUS30109): sender 0xD4F710, signature (session) only. Builder
  `bl 0xD5CF40` at 0xD4F780 (`li r4,0x4a40` at 0xD4F778) is followed immediately by the
  seal `bl 0xD5C828` at 0xD4F78C and the flush `bl 0xD34CC0` at 0xD4F79C — no serializer
  call in between. The builder memsets its 1024-byte buffer and resets the cursor, so the
  sealed length is 0.

  Preconditions: session != NULL plus the two generic connection checks (0xD38504,
  0xD3844C). Unlike 0x4A25 there is NO 0xD4908C context gate — this one is sendable
  whenever the connection is up. On a successful flush the flow state advances via
  `0xD32E08(session, 88, 1)`.

  Nearby, at 0xD4F7E8 — the next function after this sender — is a reader that requires an
  inbound id of **0x4A42** (`cmpwi r0,19010` at 0xD4F834) before iterating records out of the
  packet, so this family's replies are list-shaped. Whether that reader answers *this* id is
  [UNKNOWN]: sender/parser adjacency is not reliable in this binary (the 0x4B90 sender at
  0xD55CDC is followed by a reader for 0x4B75). Confirming the pairing means checking the
  0xD38804 dispatcher arm, not the layout.

  Never observed live; not answered by this server. Since the request carries no arguments,
  its reply has to be scoped entirely by session state.
seq: []
