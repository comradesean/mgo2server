meta:
  id: mgo2_cmd_4b62_c2s
  title: "MGO2 0x4b62 — grant emblem-editing rights (client -> server)"
  endian: be
doc: |
  **Assign the clan's emblem editor.** 4-byte payload: the target **character id**, unsigned
  big-endian. Reply is `0x4b63`, a bare u32 result. Leader only.

  [CONFIRMED 2026-07-27] Same shape as the rest of the leader-only group — 0x4b30 accept,
  0x4b32 decline, 0x4b36 banish, 0x4b60 transfer leadership, 0x4b62 set emblem editor — all
  `{u32 target character id}`. The id names a *character*, not a clan and not a roster row
  index.

  Where the grant surfaces: the clan profile reply `0x4b21` carries the emblem editor's
  character id at `T+0x6FC`, and the client compares it against its own to decide whether to
  offer "set as the clan's emblem". So this command writes the field that reply reads.

  **It is not a privilege-mask bit.** [CONFIRMED 2026-07-27] The word at `profile+6838` was
  tested as the emblem gate and is not: the commit gate `0xAD409C` tests `ctx+788 & 4`,
  which is set from **membership state 2 alone**, and no privilege bit gates applying an
  emblem. See mgo2_cmd_4b50_c2s.ksy for the experiment and for why that word must be sent
  as zero.

  Evidence (ELF, retail BLUS30109): sender 0xD571FC. Builder `bl 0xD5CF40` at 0xD57284
  (`li r4,0x4b62` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL, and 0xD5709C true (clan record present with id != 0 and
  status == 2, i.e. the caller is the leader); otherwise -1203 and no packet. The server
  re-checks leadership rather than trusting that gate.

  On a successful flush the client advances its flow state with `0xD32E08(session, 107, 1)`.
  The sender does not name the reply id.

  Family context, now settled: `0x4Bxx` is the clan subsystem. The session clan record at
  `session_ctx+0x1AA0` is {u32 id @0x00, char name[16] @0x04, u8 status @0x15}; the client
  keeps the same fields in its profile at +6816 (id), +6820 (name), +6837 (membership state:
  0 pending, 1 member, 2 leader, 99 none), +6838 (privilege/notification word) and +6872
  (emblem flag).
seq:
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The character id to grant emblem-editing rights to — the value
      that comes back in `0x4b21` at `T+0x6FC`. Position and width exact (unsigned,
      0xD5C9BC); the caller's u32 verbatim, unvalidated by the sender.
