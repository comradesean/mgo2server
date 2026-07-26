meta:
  id: mgo2_cmd_4401_s2c
  title: "MGO2 0x4401 — result + text reply for 0x4400 (server -> client)"
  endian: be
doc: |
  Parser 0xD52BA8 (ends 0xD52CE8), dispatcher stub 0xD3942C. COMMANDS.md files 0x4401 under
  "result singles" — parsed but never sent. That classification is WRONG: it is not a bare
  result single, it carries a string. This is the reply to 0x4400, itself an unanswered send-side
  gap ("in-match / host family", COMMANDS.md).

  Trace: a 129-byte stack buffer is zeroed (memset, r5=129 at 0xD52C20). Reader opened
  (0xD5C844). One u32 read (0xD5CCD8 at 0xD52C3C) into a separate 4-byte slot. Then 0xD5CE34
  with r5 = 0 (0xD52C58) — the delimiter-terminated string reader: it copies bytes from the
  stream into the 129-byte buffer until it hits the delimiter (0) or the buffer end, NUL-
  terminates, and advances the cursor past the terminator. Reader closed. Then the client
  stores 0xFF at ctx+0x14C8, the u32 at ctx+0x14CC, memcpy's the 129-byte buffer to ctx+0x14D0
  (0xDC95C0, r5=129 at 0xD52C9C), and fires UI event 0x30 (48) with the u32 as its value
  (0xD33CD8 at 0xD52CB0).

  IMPORTANT for any future server implementation of 0x4400: the string is NUL-TERMINATED on the
  wire, not fixed-width — 0xD5CE34 stops on the delimiter byte and consumes it. A fixed 128-byte
  field would only happen to work if it were fully NUL-padded.
seq:
  - id: result
    type: u4
    doc: |
      [ELF 0xD52C3C] u32 read first; stored at ctx+0x14CC and forwarded as the value of UI
      event 0x30. There is no zero/nonzero branch on it in the parser — the string is read
      unconditionally — so "result code" is [INFERRED] from its position and its use as the
      event payload, not proven.
  - id: text
    type: strz
    encoding: ISO-8859-1
    doc: |
      [ELF 0xD52C58] NUL-terminated text, read by the delimiter reader 0xD5CE34 with
      delimiter 0. The destination buffer is 129 bytes, so at most 128 characters plus the
      terminator; a longer string is truncated at the buffer end (the reader also stops there).
      [UNKNOWN] purpose — copied verbatim to ctx+0x14D0 and no consumer was traced.
