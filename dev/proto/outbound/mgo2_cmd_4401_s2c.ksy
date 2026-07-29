meta:
  id: mgo2_cmd_4401_s2c
  title: "MGO2 0x4401 — in-game chat line to display (server -> client)"
  endian: be
doc: |
  **This is the chat line the client displays.** 0x4400 is the in-game chat send (capture-proven
  2026-07-26) and this is its delivery: the server must push one of these to EVERY player in the
  game, INCLUDING the sender, because the client has no local echo — the 0x4400 caller falls
  straight into its epilogue at 0xCA0A98 without touching the display record, and this parser is
  the only producer of that record in the whole binary. Confirmed live: four messages typed with
  no handler installed, none of which appeared in the sender's own chat window.

  OFFSET CORRECTION 2026-07-26: the stores below were recorded as ctx+0x14C8/0x14CC/0x14D0. The
  parser does `addis r9,r28,1` at 0xD52C74 first, so they are +0x114C8/+0x114CC/+0x114D0 on the
  global net-session object (0x2810E0). The un-adjusted offsets match only unrelated objects,
  which is why the consumers were missed on the first pass.

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
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

seq:
  - id: speaker_chara_id
    type: u4
    doc: |
      The speaking character's id — the same value the server put at offset 0x000 of that
      character's 0x4101. [ELF 0xD52C3C] read, stored at +0x114CC, forwarded as the value of UI
      event 0x30. The consumer at 0xC9FFD8 walks all 24 roster slots comparing it against
      entry+0x60 to resolve who spoke; unmatched leaves the speaker slot 0xFF and the line renders
      unattributed rather than being discarded, so a wrong id looks like a rendering bug, not a
      protocol error. Plain big-endian binary, not ASCII decimal (0xD5CCD8 is a 4x lbzx/shift
      loop).

      This field was previously labelled `result` and [INFERRED] to be a result code from its
      position. That was wrong.
  - id: text
    type: strz
    encoding: ISO-8859-1
    doc: |
      [ELF 0xD52C58] NUL-terminated, read by the delimiter reader 0xD5CE34 with delimiter 0 into
      a 129-byte buffer, then copied to +0x114D0.

      **Byte 0 is the channel as an ASCII digit and is mandatory** — the consumer does
      `digit - 0x30` at 0xC9FF94 into the display record's channel field and takes the message
      from byte 1 via `strncpy(dst, payload+5, 0x7F)` at 0xC9FFEC. Omit it and the first character
      of every message is eaten and the channel comes out as garbage. Echo the digit the sender
      sent in 0x4400, not that request's coarse `kind` byte — they differ for channels 2 and 3.

      So: `'0'+channel`, then up to 127 bytes of message, then the terminator. Total at most 129
      bytes including the NUL — the same capacity as the 0x4400 blob it relays.
