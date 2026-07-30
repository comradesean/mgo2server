meta:
  id: mgo2_cmd_43f3_s2c
  title: "MGO2 0x43f3 — unidentified in-match notification (server -> client)"
  endian: be
doc: |
  Parser 0xD5B4D0, dispatcher stub 0xD39D8C. One of the four 0x43Fx ids in the in-match
  subsystem the client sends 0x43E0 / 0x43E2 into (COMMANDS.md).

  Reads EXACTLY ONE u32 (0xD5CCD8 at 0xD5B52C) into a stack temp, then calls 0xD33CD8 with UI
  event id 0x2E (46) and the u32 as its value, then 0xD5B41C (a screen/state poke shared with
  0x43F2 and 0x43F4).

  [UNKNOWN] what event 0x2E renders: the ELF gives the width and the event number, nothing about
  meaning, and neither PROTOCOL.md nor OBSERVED.md mentions this id. We have never sent it.

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
  - id: result
    type: u4
    doc: |
      Payload of UI event 0x2E. Meaning [UNKNOWN]. [ELF 0xD5B52C]
