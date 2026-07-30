meta:
  id: mgo2_cmd_4442_s2c
  title: "MGO2 0x4442 — 0x4440-family push notification (server -> client)"
  endian: be
doc: |
  Parser 0xD52878, dispatcher stub 0xD394B4. Reads EXACTLY ONE u32 (0xD5CC64 at 0xD528D4) and
  then calls 0xD33CD8 with event id 0x31 (49) and the u32 as its value -- the same "fire a UI
  event" helper 0x43F2..0x43F5 and 0x4802 use. It does NOT touch the status/result setters
  (0xD32E08 / 0xD32E70) for subsystem 0x54, which is what 0x4441 does.

  So this id is not the tail of the 0x4440 reply; it is an unsolicited notification the server may
  push.

  **What event 0x31 renders, traced 2026-07-26** (while tracing chat -- 0x30 and 0x31 land in the
  same consumer, so the chat trace answered this for free). The consumer is 0xC9FEF0 (and its
  callback twin 0xCA0D50), the chat-window handler. Its very first test is
  `cmpwi r29,0x31 ; beq -> 0xCA0060` -- event 0x31 takes an early branch that:

  - builds a **canned system line from two string-table ids** (0x201B and -0x2D1) and posts it via
    0x7FA780;
  - touches **none** of the three chat display fields (netctx+0x114C8 flag / +0x114CC speaker /
    +0x114D0 text) that the 0x30 branch fills.

  So 0x4442 posts a fixed, server-triggered system message into the chat window -- text from the
  client's own string table, not from us. That is why its payload is one bare u32 and carries no
  text: there is nothing for us to supply but the trigger.

  [UNKNOWN] still: which strings 0x201B and -0x2D1 resolve to (the string table was not dumped),
  and therefore what the message actually says. That is the remaining question, and it is
  answerable from the binary without a client. Also [UNKNOWN] whether the u32 selects between
  messages -- the parser forwards it as the event value, but the 0xCA0060 branch was not traced far
  enough to show it being read.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
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
  - id: notification
    type: u4
    doc: |
      Payload of UI event 0x31, forwarded verbatim by the parser [ELF 0xD528D4].

      Renamed from `result` 2026-07-26: the 0x31 handler (0xCA0060) posts a canned system line into
      the chat window and does not drive the status/result setters for subsystem 0x54 the way
      0x4441 does, so "result" was the wrong reading of what this word is for. Whether the value
      selects between messages or is ignored is [UNKNOWN] -- see the top-level doc.
