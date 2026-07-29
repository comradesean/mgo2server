meta:
  id: mgo2_cmd_4b66_c2s
  title: "MGO2 0x4b66 — set clan notice (client -> server)"
  endian: be
doc: |
  **Set the clan notice.** 512-byte payload: a single fixed-width text block, zero-padded by
  construction. Same shape as 0x4b64, four times wider. Reply is `0x4b67`, a bare u32
  result.

  [CONFIRMED 2026-07-27] Live: typing into **Clan Notice** and confirming sent exactly this,
  512 bytes and nothing else, while **Clan Comment** sent 0x4b64's 128. So the family's two
  text writes are the family's two text fields, at the sizes their struct offsets predicted:

  | command | width | struct offset | screen |
  | --- | --- | --- | --- |
  | 0x4b64 | 128 | `T+0x67A` | Clan Comment (description) |
  | 0x4b66 | 512 | `T+0x700` | Clan Notice |

  **Correction.** This was previously [INFERRED] as "a long free-text clan notice or
  bulletin" on width alone, and the corresponding field in the profile reply — `0x4b21` at
  `T+0x700` — was recorded as an unknown "long text block or packed table". The same capture
  settles both: it is the notice, it is text, and it is not a packed table.

  The notice is rendered with two companion fields the server must also fill:
  `T+0x904` the date it was set and `T+0x908` the 16-byte name of whoever set it. The
  renderer `0xAAB2D8` has **no conditionals** — it always draws date, author and body — so a
  never-set notice cannot be suppressed and the date must be sent as **-1**, not 0: the
  formatter `0x8843CC` takes a fallback branch at `0x884420` when the value is negative and
  prints the literal `XXXX-XX-XX XX:XX:XX`, whereas `localtime(0)` succeeds and yields
  12-31-1969.

  No id on the wire: the server scopes the write by session, and enforces leader-only itself.

  Evidence (ELF, retail BLUS30109): sender 0xD57B40. The prologue takes (session, char*),
  zeroes a 513-byte stack buffer at 1328 (`memset(buf, 0, 0x201)` at 0xD57B84), and — if the
  pointer is non-NULL — checks `strlen(str) <= 512` (0xDCC7F8 then `cmplwi 512` at 0xD57BB4;
  over-length returns -24 and sends nothing) before `strcpy`ing it in (0xDCC680). A NULL
  pointer is legal and yields an all-zero block. Builder `bl 0xD5CF40` at 0xD57C1C
  (`li r4,0x4b66` at 0xD57C18), the single write `0xD5D0AC(pkt, buf, 0x200)` at 0xD57C30,
  seal `bl 0xD5C828` at 0xD57C3C, flush `bl 0xD34CC0` at 0xD57C4C.

  Preconditions: session != NULL, and 0xD57750 true (session clan record at
  `session_ctx+0x1AA0` non-NULL with id != 0), else -1201. **No status-byte gate**, so
  leader-only is the server's rule to enforce, and it does. On success the flow state
  advances via `0xD32E08(session, 110, 1)`.
seq:
  - id: notice
    type: str
    size: 512
    pad-right: 0
    encoding: UTF-8
    doc: |
      [CONFIRMED 2026-07-27] The clan notice — the largest single text field in the game's
      lobby protocol. Exactly 512 bytes on the wire; the content is a string of at most 512
      characters, with the remainder guaranteed zero by the `memset` at 0xD57B84 — hence
      `pad-right: 0` rather than a terminator, which a full-length value would not have.

      No character-class validation. Encoding is a guess: no charset evidence was read, and
      a 512-byte notice is exactly where a multi-byte encoding would matter, so treat it as
      open. The server reads it as ISO-8859-1.
