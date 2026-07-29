meta:
  id: mgo2_cmd_4b04_c2s
  title: "MGO2 0x4b04 — disband clan, no payload (client -> server)"
  endian: be
doc: |
  **Disband the clan.** EMPTY PAYLOAD — zero bytes after the 24-byte transport header, and
  that is a positive result rather than an unmapped layout: the ELF shows no payload write
  at all. Reply is `0x4b05`, a bare u32 result.

  [CONFIRMED 2026-07-27] Leader-only, and the whole request is the session: the server
  resolves *which* clan from the caller's own membership, because nothing on the wire says.

  Evidence (ELF, retail BLUS30109): sender 0xD575FC. Builder `bl 0xD5CF40` at 0xD57680
  (`li r4,0x4b04` at 0xD57678 — corrected 2026-07-26 from 0xD5767C, which is the following
  `mr r3,r31`) is followed *immediately* by the seal `bl 0xD5C828` at 0xD5768C and the flush
  `bl 0xD34CC0` at 0xD5769C — no call to any of the serializers (0xD5C86C/0xD5C8A0 u8,
  0xD5C8D4/0xD5C918 u16, 0xD5C95C/0xD5C9BC/0xD5CA1C u32, 0xD5CA7C u64, 0xD5CADC string,
  0xD5D0AC fixed blob) in between. The builder memsets its 1024-byte buffer and sets the
  cursor to 0, so the sealed length is 0.

  Preconditions: session != NULL, and 0xD5709C true — the session clan record at
  `session_ctx+0x1AA0` must exist with id != 0 and **status byte == 2**, i.e. the caller is
  the leader; otherwise the sender returns -1203 (0xFFFFFB4D) and sends nothing. That
  client-side gate is why a non-leader disband never reaches the server, and the server
  enforces the same rule again rather than trusting it.

  On a successful flush the client advances its flow state with `0xD32E08(session, 93, 1)`.

  **Refusal.** A disband inside the cooldown is refused with -1205, which the client renders
  as "A fixed amount of time must pass in order to disband the clan." (dispatcher
  `0xA7E74C`, error table `0x106D714`). The cooldown itself is **operator policy**, not
  protocol — 168 hours here, matching character deletion; the orphaned countdown strings
  (17312/17318) that would have shown the remaining time are reachable from nothing in this
  build, so -1205 says the same thing without the number.
seq: []
