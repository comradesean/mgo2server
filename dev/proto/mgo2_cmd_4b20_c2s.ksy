meta:
  id: mgo2_cmd_4b20_c2s
  title: "MGO2 0x4b20 — clan profile request, own clan only (client -> server)"
  endian: be
doc: |
  **Clan profile request.** 4-byte payload: the clan id, unsigned big-endian. Sent from the
  **Clan Affiliation** screen. Reply is `0x4b21`, a 777-byte profile block on success and
  4 bytes on failure (`0xD58C04` jumps straight to end-read on a nonzero result).

  [CONFIRMED 2026-07-27] The id is the clan id, and the server must echo it back: **the
  client cross-checks `0x4b21`'s `T+0x00` against the clan id it already holds and drops the
  packet on a mismatch.** That single check is what settles the scope of this command — it
  **cannot serve a clan the player is not in**. The non-member path is the separate
  `0x4b80` -> `0x4b81` pair, whose `subject_id` is explicitly *not* cross-checked.

  Answering with a clan we cannot find, or a mismatched id, must therefore be a 4-byte
  failure rather than a zero-filled block; otherwise the screen renders a nameless clan.

  Evidence (ELF, retail BLUS30109): sender 0xD567F0. Builder `bl 0xD5CF40` at 0xD56864
  (`li r4,0x4b20` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only — no clan-record gate, which is consistent with the
  screen being reachable before the record is populated.
  After the flush the u32 is also cached into the global block at `+0x6D00`
  (`stw r0,27904(r9)` at 0xD568C8) — the sibling of the `+0x6D08` slot 0x4A30 writes.

  On a successful flush the client advances its flow state with `0xD32E08(session, 99, 1)`.
  The sender does not name the reply id; `0x4b21` is established from the parser side.

  Family context, now settled: `0x4Bxx` is the clan subsystem. The session carries a clan
  record at `session_ctx+0x1AA0` (accessor 0xD56EDC over the context returned by 0xD3A094),
  shaped {u32 id @0x00, char name[16] @0x04, u8 status @0x15}; the 0x4b42 sender writes all
  three, 0xD57750 gates on id != 0, and 0xD5709C gates on status == 2 (leader). The client
  keeps the same five fields in its profile at +6816 (id), +6820 (name), +6837 (membership
  state: 0 pending, 1 member, 2 leader, 99 none), +6838 (privilege/notification word) and
  +6872 (emblem flag).
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The clan whose profile is wanted — in practice always the
      caller's own, because the reply's echo of this value is cross-checked against the
      client's cached clan id and a mismatched reply is discarded. Position and width exact
      (unsigned, 0xD5C9BC).
