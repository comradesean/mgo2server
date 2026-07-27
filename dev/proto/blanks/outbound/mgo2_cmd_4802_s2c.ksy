meta:
  id: mgo2_cmd_4802_s2c
  title: "MGO2 0x4802 — mail-send notification, EMPTY payload (server -> client)"
  endian: be
doc: |
  Part of the send-mail family: `../inbound/mgo2_cmd_4800_c2s.ksy` is the request and
  `mgo2_cmd_4801_s2c.ksy` the reply we actually serve. What distinguishes this second parsed reply
  from `0x4801` is [UNKNOWN]; we have never sent it.

  Second parsed reply id of the 0x4800 send-mail family (with 0x4801). Parser 0xD54090,
  dispatcher stub 0xD394D4. COMMANDS.md lists it under "the rest of the mailbox" —
  parsed but never sent by us. PROTOCOL.md documents no layout for it.

  THE PAYLOAD IS EMPTY. The parser fetches the header (0xD3879C), compares the id
  (cmpwi 0x4802 at 0xD540C8), stores the byte -1 at ctx+0x1554 (0xD540E4) and calls 0xD33CD8
  with UI event id 0x32 (50) and value -1 (li r5,-1 at 0xD540BC, widened at 0xD540D0). No
  stream reader is opened (no 0xD5C844) and no read primitive is called.

  Because the value passed to the UI is the constant -1 rather than anything from the wire,
  this id carries no information beyond its own arrival: a bare notify.
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
  - id: unknown_body
    size-eos: true
    doc: |
      [ELF 0xD54090] Present only to state that nothing is parsed. Expected length 0.
