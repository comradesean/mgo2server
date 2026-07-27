meta:
  id: mgo2_cmd_4b60_c2s
  title: "MGO2 0x4b60 — transfer clan leadership (client -> server)"
  endian: be
doc: |
  **Hand leadership of the clan to another member.** 4-byte payload: the target **character
  id**, unsigned big-endian. Reply is `0x4b61`, a bare u32 result. Leader only.

  [CONFIRMED 2026-07-27] Same shape as the rest of the leader-only group — 0x4b30 accept,
  0x4b32 decline, 0x4b36 banish, 0x4b60 transfer leadership, 0x4b62 set emblem editor — all
  `{u32 target character id}`. The id names a *character*, not a clan and not a roster row
  index.

  The effect is on the membership states, not on the clan record's shape: the caller drops
  from 2 (leader) to 1 (member) and the target rises from 1 to 2. Those are the values the
  client reads back at `profile+6837`, so both sides have to be told — the caller's own next
  `0x4b47` must report state 1.

  This was another of the four commands once answered with a bare success while the server
  did nothing. It is implemented now, and a target who is not a member returns an error.

  Evidence (ELF, retail BLUS30109): sender 0xD572FC. Builder `bl 0xD5CF40` at 0xD57384
  (`li r4,0x4b60` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL, and 0xD5709C true (clan record present with id != 0 and
  status == 2, i.e. the caller is the leader); otherwise -1203 and no packet. The server
  re-checks leadership rather than trusting that gate.

  On a successful flush the client advances its flow state with `0xD32E08(session, 106, 1)`.
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
      [CONFIRMED 2026-07-27] The character id of the member who is to become leader.
      Position and width exact (unsigned, 0xD5C9BC); the caller's u32 verbatim, unvalidated
      by the sender.
