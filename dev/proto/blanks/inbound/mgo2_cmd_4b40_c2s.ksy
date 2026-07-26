meta:
  id: mgo2_cmd_4b40_c2s
  title: "MGO2 0x4b40 — clan/GHQ request with no payload (client -> server)"
  endian: be
doc: |
  EMPTY PAYLOAD — zero bytes after the 24-byte transport header, established positively
  from the ELF rather than left unmapped.

  Evidence (ELF, retail BLUS30109): sender 0xD578C0. Builder `bl 0xD5CF40` at 0xD57944
  (`li r4,0x4b40` at 0xD5793C) is followed immediately by the seal `bl 0xD5C828` at
  0xD57950 and the flush `bl 0xD34CC0` at 0xD57960, with no serializer call in between
  (none of 0xD5C86C/0xD5C8A0, 0xD5C8D4/0xD5C918, 0xD5C95C/0xD5C9BC/0xD5CA1C, 0xD5CA7C,
  0xD5CADC, 0xD5D0AC). The builder zeroes its 1024-byte buffer and resets the cursor, so
  the sealed length is 0.

  Preconditions: session != NULL, and 0xD57750 true — the session clan record at
  `session_ctx+0x1AA0` must be non-NULL with id != 0 (note: unlike 0x4B04/0x4B30 this does
  NOT require status == 2, so a non-leader can send it); otherwise -1202 (0xFFFFFB4E) and
  no packet. On a successful flush the flow state advances via `0xD32E08(session, 97, 1)`.

  The whole argument is the session's own clan membership, so the server must resolve the
  subject itself. Sibling 0x4B48 is the same shape but explicitly sends the clan id as a
  u32; the pair suggests one of them is scoped by the server and one by the client.

  Reading [INFERRED]: clan / GHQ family. Never observed live; not answered by this server.
seq: []
