meta:
  id: mgo2_cmd_4b73_c2s
  title: "MGO2 0x4b73 — clan applicant list request (client -> server)"
  endian: be
doc: |
  **The pending-applicant list.** 4-byte payload: the clan id, unsigned big-endian. The reply
  is a start/items/end triple: `0x4b74` start, `0x4b75` entries (93 bytes each — `{u32 id,
  char text[64], char name[16], u8, s32, u32}`), `0x4b76` end. As with every triple in this
  protocol, the start and end packets carry a **result code, never a count**.

  ## The client does not use this — applications arrive as MAIL

  [CONFIRMED 2026-07-27] Clan applications are delivered to the leader as **mail**: mailbox
  type `0x10` on `0x4820`, where type `0x0f` is ordinary mail. There is no applicant-list
  command anywhere in the client's clan flow, which is why the client has never been
  observed to send this one, and why building the approve/decline path around a roster fetch
  was looking for a screen that does not exist. The leader reads a mail and answers it with
  `0x4b30` (accept) or `0x4b32` (decline), both keyed by the applicant's character id.

  That does not make this command dead — it exists in the binary and the server answers it
  in the shape its parser demands — but it does mean an empty triple is the normal answer
  and that no clan screen depends on it.

  The applicant record's 64-byte text field is sent as zeros: `0x4b42` carries only a clan
  id, so an application has no message attached anywhere on the wire, and there is nothing
  found yet that would write one.

  Evidence (ELF, retail BLUS30109): sender 0xD56354. Builder `bl 0xD5CF40` at 0xD563C8
  (`li r4,0x4b73` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only.

  On a successful flush the client advances its flow state with `0xD32E08(session, 112, 1)`.
  The sender does not name the reply id.
seq:
  - id: clan_id
    type: u4
    doc: |
      [INFERRED] The clan whose pending applications are wanted — by shape and by the
      company it keeps, **not** capture-proven, because the client has never been seen to
      send this command at all (applications come as mail). Position and width exact
      (unsigned, 0xD5C9BC); the caller's u32 verbatim, unvalidated by the sender.

      Restricting the answer to the caller's own clan would be **operator policy**, not a
      wire rule — nothing in the request or the sender enforces it.
