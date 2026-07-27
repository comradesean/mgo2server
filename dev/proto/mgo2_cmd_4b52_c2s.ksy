meta:
  id: mgo2_cmd_4b52_c2s
  title: "MGO2 0x4b52 — clan roster request (client -> server)"
  endian: be
doc: |
  **The clan member list.** 4-byte payload: the clan id, unsigned big-endian. The reply is a
  start/items/end **triple**: `0x4b53` start, `0x4b54` entries (68 wire bytes each), `0x4b55`
  end.

  [CONFIRMED 2026-07-27] Same triple shape as the social lists (`0x4601`/`0x4602`/`0x4603`),
  and with the same trap: **the start and end packets carry a result code, never a count**.
  Sending a count there produced the live `1032:00000005` error on the social path; the
  client counts the item records itself, from the packet length.

  Two further things learned the hard way about the entries, recorded here because they are
  properties of how the client consumes this request's reply:

  - Members and applicants go out as **one** batch with a per-row flag, not two `0x4b54`
    packets. Sent as two packets both reached the wire and the client rendered only the
    first, so applicants simply vanished. Sent as one batch with the flag set per *batch*
    they appeared as full members. One list with an honest per-row flag is the combination
    that works.
  - The row head is `{u32 chara_id, char name[16], u8 is_member}`, the same {id, name,
    status} shape as the session clan record and the profile block. The remaining 47 bytes —
    two more 16-byte names and three numbers, the game-location fields — are [UNKNOWN] and
    are sent as zero rather than as guesses.

  Evidence (ELF, retail BLUS30109): sender 0xD5652C. Builder `bl 0xD5CF40` at 0xD565A0
  (`li r4,0x4b52` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only — no clan-record gate, so the roster of a clan the
  caller does not belong to can be asked for.

  On a successful flush the client advances its flow state with `0xD32E08(session, 105, 1)`.
  The sender does not name the reply id.
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The clan whose roster is wanted. Position and width exact
      (unsigned, 0xD5C9BC); the caller's u32 verbatim, unvalidated by the sender. The server
      compares it against the caller's own membership to decide whether to include pending
      applicants in the batch — that is **operator policy** (only a leader is shown
      applicants), not a wire rule.
