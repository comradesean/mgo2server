meta:
  id: mgo2_cmd_4b66_c2s
  title: "MGO2 0x4b66 — clan/GHQ 512-byte text write (client -> server)"
  endian: be
doc: |
  512-byte payload: a single fixed-width text block, zero-padded by construction. Same
  shape as 0x4B64, four times wider.

  Evidence (ELF, retail BLUS30109): sender 0xD57B40. The prologue takes (session, char*),
  zeroes a 513-byte stack buffer at 1328 (`memset(buf, 0, 0x201)` at 0xD57B84), and — if the
  pointer is non-NULL — checks `strlen(str) <= 512` (0xDCC7F8 then `cmplwi 512` at 0xD57BB4;
  over-length returns -24 and sends nothing) before `strcpy`ing it in (0xDCC680). A NULL
  pointer is legal and yields an all-zero block. Builder `bl 0xD5CF40` at 0xD57C1C
  (`li r4,0x4b66` at 0xD57C18), the single write `0xD5D0AC(pkt, buf, 0x200)` at 0xD57C30,
  seal `bl 0xD5C828` at 0xD57C3C, flush `bl 0xD34CC0` at 0xD57C4C.

  Preconditions: session != NULL, and 0xD57750 true (session clan record at
  `session_ctx+0x1AA0` non-NULL with id != 0), else -1201. No status-byte gate. On success
  the flow state advances via `0xD32E08(session, 110, 1)`.

  Note this is the largest single field in the family and comfortably the largest text slot:
  512 bytes with no character-class validation. Reading [INFERRED]: a long free-text clan
  notice or bulletin, written back wholesale, scoped by session rather than by an id on the
  wire. Structural only — never observed live, not answered by this server.
seq:
  - id: text
    type: str
    size: 512
    pad-right: 0
    encoding: UTF-8
    doc: |
      [ELF] Exactly 512 bytes on the wire; content is a string of at most 512 characters,
      remainder guaranteed zero by the `memset` at 0xD57B84 — hence `pad-right: 0` rather
      than a terminator, which a full-length value would not have. Encoding is a guess: no
      charset evidence was read, and a 512-byte notice is exactly where a multi-byte
      encoding would matter, so treat it as open.
