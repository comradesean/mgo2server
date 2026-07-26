meta:
  id: mgo2_cmd_4b00_c2s
  title: "MGO2 0x4b00 — clan/GHQ create (client -> server)"
  endian: be
doc: |
  144-byte payload: a 16-byte fixed field followed by a 128-byte fixed field. Both are
  written by the fixed-length blob serializer 0xD5D0AC (a bounded `memcpy` of exactly r5
  bytes into the packet buffer), so the widths are the *field* widths, not string lengths —
  whatever trailing bytes the source buffer holds go on the wire.

  Evidence (ELF, retail BLUS30109): sender 0xD579AC. Builder `bl 0xD5CF40` at 0xD57A9C
  (`li r4,0x4b00` at 0xD57A98), then
  `0xD5D0AC(pkt, arg+0x004, 0x10)` at 0xD57AB0 and
  `0xD5D0AC(pkt, arg+0x67A, 0x80)` at 0xD57AC4,
  then the seal `bl 0xD5C828` at 0xD57AD0 and the flush `bl 0xD34CC0` at 0xD57AE0.

  The sender takes (session, ptr) and validates the pointed-at struct before building:
  `strlen(arg+0x004)` must be > 2 and <= 16, and the string must pass the character-class
  check 0xD32DD0 (the same validator the 0x4B90 and 0x4B42 senders apply to their 16-byte
  name field — i.e. this is a *user-typed name*); `strlen(arg+0x67A)` must be <= 128.
  Any failure returns -24 (0xFFFFFFE8) and sends nothing. It also requires 0xD57750: the
  session clan record at `session_ctx+0x1AA0` must be non-NULL with id != 0, else -1201.

  On a successful flush the client advances its flow state with `0xD32E08(session, 92, 1)`.

  Reading [INFERRED]: a create/register call for the clan/GHQ family — a validated
  16-character name plus a 128-character free-text block. Not capture-proven, and this
  server neither answers nor has ever seen it.
seq:
  - id: name
    type: str
    size: 16
    encoding: UTF-8
    doc: |
      [ELF] Exactly 16 bytes, `memcpy`'d from `arg+0x004`. The caller-side string is length
      checked (3..16) and character-class checked (0xD32DD0) before the packet is built, so
      the field carries a user-typed name; whether the client zero-fills the tail is a
      property of the caller's buffer and is [UNKNOWN] from here. Encoding is a guess —
      no charset evidence was read.
  - id: description
    type: str
    size: 128
    encoding: UTF-8
    doc: |
      [ELF] Exactly 128 bytes, `memcpy`'d from `arg+0x67A`. Only `strlen <= 128` is checked
      — no character-class check, so freer text than `name`. Purpose [UNKNOWN]; a
      description/motto slot is the structural reading given the width and the lack of
      validation. Note 0x4B64 sends a lone 128-byte block and 0x4B66 a lone 512-byte one,
      which look like the edit counterparts.
