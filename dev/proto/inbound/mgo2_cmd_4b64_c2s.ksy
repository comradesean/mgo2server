meta:
  id: mgo2_cmd_4b64_c2s
  title: "MGO2 0x4b64 — set clan description (client -> server)"
  endian: be
doc: |
  **Set the clan description** — the field the client labels **Clan Comment**. 128-byte
  payload: a single fixed-width text block, zero-padded by construction. Reply is `0x4b65`,
  a bare u32 result.

  [CONFIRMED 2026-07-27] Live: typing a comment into **Clan Comment** and confirming sent
  exactly this, 128 bytes and nothing else. Its sibling `0x4b66` sent 512 bytes when **Clan
  Notice** was set the same way. So the family's two text writes are the family's two text
  fields, at the sizes their struct offsets predicted:

  | command | width | struct offset | screen |
  | --- | --- | --- | --- |
  | 0x4b64 | 128 | `T+0x67A` | Clan Comment (description) |
  | 0x4b66 | 512 | `T+0x700` | Clan Notice |

  **Correction.** This was previously [INFERRED] — "some clan free-text slot", the edit
  counterpart to 0x4b00's second field by width alone. It is now confirmed, and the same
  capture settles the corresponding profile field: `0x4b21`'s `T+0x700` was recorded as an
  unknown "long text block or packed table" and is the notice.

  The description is also what `0x4b00` sends at creation time from `arg+0x67A`, and what
  `0x4b21`/`0x4b81` echo back at `T+0x67A` — one struct offset, four commands.

  No id on the wire: the server scopes the write by session, and enforces leader-only itself
  (the client's own gate here is weaker — see the preconditions).

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
  `session_ctx+0x1AA0` non-NULL with id != 0), else -1201. **No status-byte gate**, so the
  client will send this for a plain member or even a pending applicant; leader-only is the
  server's rule to enforce, and it does. On success the flow state advances via
  `0xD32E08(session, 109, 1)`.
seq:
  - id: description
    type: str
    size: 128
    pad-right: 0
    encoding: UTF-8
    doc: |
      [CONFIRMED 2026-07-27] The clan description / Clan Comment. Exactly 128 bytes on the
      wire; the content is a string of at most 128 characters with the remainder guaranteed
      zero by the `memset` at 0xD57CEC — hence `pad-right: 0` rather than a terminator,
      which a full-length 128-character value would not have.

      No character-class validation, unlike the clan name, so this is free text. Encoding is
      a guess — no charset evidence was read; the server reads it as ISO-8859-1.
