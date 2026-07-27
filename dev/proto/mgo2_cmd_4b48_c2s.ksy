meta:
  id: mgo2_cmd_4b48_c2s
  title: "MGO2 0x4b48 — fetch own clan's emblem (client -> server)"
  endian: be
doc: |
  **The client asking for its own clan's emblem.** 4-byte payload: one unsigned u32, read
  out of the client's own cached clan record — NOT a caller argument; the sender takes only
  a session. Reply is `0x4b49`, `{s4 result, byte[768]}` — 772 bytes on success, 4 on error.

  [CONFIRMED 2026-07-27] It appears **only once a character HAS a clan** — it turned up the
  moment `0x4122` first reported a real clan record — and it **blocks character select**:
  with no reply, the character-select screen hangs. That is a good example of the pattern in
  this subsystem: every field we start populating truthfully unlocks a branch that was
  previously dormant, and the newly reachable branch has its own commands to answer.

  ## The 768-byte block is the clan EMBLEM

  **Correction.** This spec's reply was previously described as an opaque block whose
  contents were unknown, and at one point the server filled it with pending applicant names
  on the theory that 768 = 48 x 16 made it a name table. It is not a name table: `0x4b49`'s
  block is copied straight into `profile+6873` (parser `0xD56F24`, `addi r0,r27,57` off the
  clan record at `0xD56EDC`), which is the client's **emblem buffer**. Filling it with text
  was writing text into that buffer.

  What remains true is that neither side inspects it: the parser reads the run with
  `0xD5D018` and NUL-terminates at +768 into a 769-byte buffer, so the server stores and
  returns the 768 bytes verbatim. The *internal* format of the emblem (the pixel or vector
  encoding the emblem editor produces) is still [UNKNOWN] and does not need to be known to
  serve it — the block only ever round-trips between `0x4b50` and `0x4b49`/`0x4b4b`/`0x4b4d`.

  Evidence (ELF, retail BLUS30109): sender 0xD577A4. It calls the accessor 0xD56EDC
  (`session_ctx(0xD3A094) + 0x1AA0`, or 0 if there is no context) at 0xD577D8, requires the
  result non-NULL, and keeps it in r28. Builder `bl 0xD5CF40` at 0xD5783C (`li r4,0x4b48` at
  0xD57838); the single write `bl 0xD5C9BC` at 0xD5784C is passed r4 = r28, and that
  serializer dereferences r4, so the wire value is `*(u32*)(record+0x00)` — the record's id
  field. Seal `bl 0xD5C828` at 0xD57858, flush `bl 0xD34CC0` at 0xD57868.

  Preconditions: session != NULL; the record must exist; and 0xD57750 true (record non-NULL
  with id != 0), else -1202. No status-byte requirement, so a plain member sends it too —
  which is right for a fetch every member's screen needs.
  On success the flow state advances via `0xD32E08(session, 101, 1)`.

  Contrast with the siblings: 0x4b40 is scoped by the caller's clan and sends nothing at
  all; 0x4b4a and 0x4b4c send a clan id chosen by the *screen*, so they can fetch someone
  else's emblem. This one can only ever ask for the caller's own, because the id comes out
  of the caller's own record.
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The caller's own clan id, read from the session clan record at
      `session_ctx+0x1AA0` (offset 0x00) rather than passed in — the same value 0x4b42 sent
      to establish that record and the field 0xD57750 gates on. Position and width exact
      (unsigned, 0xD5C9BC).

      A server may equally resolve the clan from the session and ignore this field; it is
      sent, and it is the client's own cached copy, so a mismatch would mean the client's
      record is stale rather than that the request means something else.
