meta:
  id: mgo2_cmd_4b04_c2s
  title: "MGO2 0x4b04 — clan/GHQ request with no payload (client -> server)"
  endian: be
doc: |
  EMPTY PAYLOAD — zero bytes after the 24-byte transport header. This is not an unmapped
  layout: the ELF shows no payload write at all.

  Evidence (ELF, retail BLUS30109): sender 0xD575FC. Builder `bl 0xD5CF40` at 0xD57680
  (`li r4,0x4b04` at 0xD57678 — corrected 2026-07-26 from 0xD5767C, which is the following
  `mr r3,r31`) is followed *immediately* by the seal `bl 0xD5C828` at
  0xD5768C and the flush `bl 0xD34CC0` at 0xD5769C — no call to any of the serializers
  (0xD5C86C/0xD5C8A0 u8, 0xD5C8D4/0xD5C918 u16, 0xD5C95C/0xD5C9BC/0xD5CA1C u32,
  0xD5CA7C u64, 0xD5CADC string, 0xD5D0AC fixed blob) in between. The builder memsets its
  1024-byte buffer and sets the cursor to 0, so the sealed length is 0.

  Preconditions: session != NULL, and 0xD5709C true — the session clan record at
  `session_ctx+0x1AA0` must exist with id != 0 and status byte == 2; otherwise the sender
  returns -1203 (0xFFFFFB4D) and sends nothing. On a successful flush the client advances
  its flow state with `0xD32E08(session, 93, 1)`.

  So this is a pure "do the thing / send me the thing" trigger whose entire argument is the
  server-side session: the server must know which clan the caller means. A bodied reply is
  therefore likely (compare 0x4510, where a bare ack did not satisfy the client), but the
  reply id is not discoverable from the sender.

  Reading [INFERRED]: clan / GHQ family, gated on status == 2. Never observed live and not
  answered by this server.
seq: []
