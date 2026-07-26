meta:
  id: mgo2_cmd_4b64_c2s
  title: "MGO2 0x4b64 — clan/GHQ 128-byte text write (client -> server)"
  endian: be
doc: |
  128-byte payload: a single fixed-width text block, zero-padded by construction.

  Evidence (ELF, retail BLUS30109): sender 0xD57CA8. The prologue takes (session, char*),
  zeroes a 129-byte stack buffer at 1328 (`memset(buf, 0, 0x81)` at 0xD57CEC), and — if the
  pointer is non-NULL — checks `strlen(str) <= 128` (0xDCC7F8 then `cmplwi 128` at 0xD57D1C;
  over-length returns -24 and sends nothing) before `strcpy`ing it in (0xDCC680). A NULL
  pointer is legal and yields an all-zero block. Builder `bl 0xD5CF40` at 0xD57D84
  (`li r4,0x4b64` at 0xD57D80), the single write `0xD5D0AC(pkt, buf, 0x80)` at 0xD57D98,
  seal `bl 0xD5C828` at 0xD57DA4, flush `bl 0xD34CC0` at 0xD57DB4.

  Because the staging buffer is memset first and copied whole, the trailing bytes are
  guaranteed zero — this field really is a NUL-padded fixed 128-byte string, not a raw blob.

  Preconditions: session != NULL, and 0xD57750 true (session clan record at
  `session_ctx+0x1AA0` non-NULL with id != 0), else -1201. No status-byte gate. On success
  the flow state advances via `0xD32E08(session, 109, 1)`.

  Reading [INFERRED]: the edit counterpart to the 128-byte second field of 0x4B00 (clan
  create) — same width, same absence of a character-class check, and no id on the wire
  because the server scopes it by session. 0x4B66 is the 512-byte sibling. Structural only.

  Never observed live; not answered by this server.
seq:
  - id: text
    type: str
    size: 128
    pad-right: 0
    encoding: UTF-8
    doc: |
      [ELF] Exactly 128 bytes on the wire; content is a string of at most 128 characters,
      with the remainder guaranteed zero by the `memset` at 0xD57CEC — hence `pad-right: 0`
      rather than a terminator, which a full-length 128-character value would not have.
      Encoding is a guess —
      no charset evidence was read. Purpose [UNKNOWN] beyond "some clan free-text slot".
