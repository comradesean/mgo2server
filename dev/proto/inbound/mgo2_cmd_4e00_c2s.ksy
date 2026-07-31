meta:
  id: mgo2_cmd_4e00_c2s
  title: "MGO2 0x4e00 — isolated tail subsystem, no payload (client -> server)"
  endian: be
doc: |
  EMPTY PAYLOAD — zero bytes after the 24-byte transport header, established positively
  from the ELF, not left unmapped.

  Evidence (ELF, retail BLUS30109): sender 0xD5B05C, signature (session) only. Builder
  `bl 0xD5CF40` at 0xD5B0CC (`li r4,0x4e00` at 0xD5B0C4) is followed immediately by the
  seal `bl 0xD5C828` at 0xD5B0D8 and the flush `bl 0xD34CC0` at 0xD5B0E8 — no serializer
  call in between (none of 0xD5C86C/0xD5C8A0, 0xD5C8D4/0xD5C918,
  0xD5C95C/0xD5C9BC/0xD5CA1C, 0xD5CA7C, 0xD5CADC, 0xD5D0AC). The builder memsets its
  1024-byte buffer and resets the cursor, so the sealed length is 0.

  Preconditions: session != NULL plus the two generic connection checks (0xD38504,
  0xD3844C) — nothing else. On a successful flush the flow state advances via
  `0xD32E08(session, 90, 1)`.

  Nearby, at 0xD5B134 — the next function after this sender — is a reader that requires an
  inbound id of **0x4E20** (`cmpwi r0,20000` at 0xD5B1BC). Whether it answers *this* id is
  [UNKNOWN]: sender/parser adjacency is not reliable in this binary (the 0x4B90 sender at
  0xD55CDC is followed by a reader for 0x4B75). COMMANDS.md files 0x4E00 under "misc /
  isolated" on the send side and 0x4E10..0x4E23 as a small unimplemented tail on the receive
  side, which is consistent with, but does not establish, a 0x4E00 -> 0x4E20 pairing.

  Never observed live; not answered by this server. As a bare argument-less request its
  reply must be scoped entirely by session state, and per CLAUDE.md an unanswered command
  normally stalls the client with FFFFFF60 — so this one needs a reply traced before the
  menu that sends it is reachable, and a bare ack may well not satisfy it (the 0x4510
  precedent).
seq: []
