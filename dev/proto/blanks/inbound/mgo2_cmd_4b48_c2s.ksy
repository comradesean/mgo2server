meta:
  id: mgo2_cmd_4b48_c2s
  title: "MGO2 0x4b48 — clan/GHQ request scoped by the cached clan id (client -> server)"
  endian: be
doc: |
  4-byte payload: one unsigned u32, read out of the client's own cached clan record — NOT a
  caller argument. The sender takes only a session.

  Evidence (ELF, retail BLUS30109): sender 0xD577A4. It calls the accessor 0xD56EDC
  (`session_ctx(0xD3A094) + 0x1AA0`, or 0 if there is no context) at 0xD577D8, requires the
  result non-NULL, and keeps it in r28. Builder `bl 0xD5CF40` at 0xD5783C
  (`li r4,0x4b48` at 0xD57838); the single write `bl 0xD5C9BC` at 0xD5784C is passed
  r4 = r28, and that serializer dereferences r4, so the wire value is `*(u32*)(record+0x00)`
  — the record's id field. Seal `bl 0xD5C828` at 0xD57858, flush `bl 0xD34CC0` at 0xD57868.

  Preconditions: session != NULL; the record must exist; and 0xD57750 true (record non-NULL
  with id != 0), else -1202. No status-byte requirement, so a plain member can send it.
  On success the flow state advances via `0xD32E08(session, 101, 1)`.

  The record is {u32 id @0x00, char name[16] @0x04, u8 status @0x15} at
  `session_ctx+0x1AA0`, written by the 0x4B42 sender (see mgo2_cmd_4b42.ksy) and read by
  every other 0x4Bxx precondition. Structurally, then, this command says "the clan I am in,
  by id" — where 0x4B40 says the same thing with no payload at all. Which of the two the
  server is supposed to trust is [UNKNOWN].

  Reading [INFERRED]: clan / GHQ family. Never observed live; not answered by this server.
seq:
  - id: clan_id
    type: u4
    doc: |
      [ELF] Position and width exact (unsigned, 0xD5C9BC). [INFERRED] "clan id": the id
      field of the session clan record at `session_ctx+0x1AA0` — the same value 0x4B42 sent
      to establish that record and the field 0xD57750 gates on. Structural, not
      capture-proven.
