meta:
  id: mgo2_cmd_4b42_c2s
  title: "MGO2 0x4b42 — clan/GHQ join or apply by id (client -> server)"
  endian: be
doc: |
  4-byte payload: one unsigned u32 — the id taken from the caller's struct. Notable
  finding: the sender also validates a 16-byte NAME string in that struct and does **not**
  put it on the wire; the name is used only to populate a client-side cache after the send.

  Evidence (ELF, retail BLUS30109): sender 0xD585FC. Builder `bl 0xD5CF40` at 0xD586D0
  (`li r4,0x4b42` at 0xD586CC), one write `bl 0xD5C9BC` at 0xD586E0 (unsigned u32, 4 bytes
  MSB first, from `*(u32*)arg+0x00`), seal `bl 0xD5C828` at 0xD586EC, flush `bl 0xD34CC0`
  at 0xD586FC.

  Preconditions on (session, ptr): ptr != NULL; `strlen(ptr+0x04)` > 2 and <= 16; that
  string passes the character-class validator 0xD32DD0; and 0xD57750 true (the session clan
  record at `session_ctx+0x1AA0` non-NULL with id != 0), else -1201. Failures return -24.

  What happens after the flush is the most informative part (0xD58714..0xD58758): the
  client writes into its session context (0xD3A094) at `+0x1AA0`
  — `stw` the sent id at +0x1AA0, `stb` 0 at +0x1AB5 (the status byte), memset 17 bytes at
  +0x1AA4 and `strncpy` 16 bytes of the validated name in. That is exactly the record layout
  {u32 id @0x00, char name[16] @0x04, u8 status @0x15} that every other 0x4Bxx precondition
  reads (0xD57750 checks id, 0xD5709C checks status == 2, 0xD576E4 accepts status 1 or 2).
  So 0x4B42 *establishes* the client's clan association, and it does so with status 0 —
  pending — leaving 1 and 2 to be set from a server reply.

  On success the flow state advances via `0xD32E08(session, 96, 1)`.

  Reading [INFERRED]: join / apply to the clan identified by this id, the name travelling
  only as the local label. Never observed live; not answered by this server.
seq:
  - id: clan_id
    type: u4
    doc: |
      [ELF] Position and width exact (unsigned, 0xD5C9BC), read from `*(u32*)(arg+0x00)`.
      [INFERRED] "clan id": the same value the client immediately caches at
      `session_ctx+0x1AA0`, the field 0xD57750 tests for non-zero as the "am I in a clan"
      gate, and the field 0x4B48 later sends back. The label is structural, not
      capture-proven.
