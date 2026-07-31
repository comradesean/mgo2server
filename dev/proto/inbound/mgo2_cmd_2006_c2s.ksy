meta:
  id: mgo2_cmd_2006_c2s
  title: "MGO2 0x2006 — unidentified gate/lobby-layer request (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd36968` (`li r4,8198` = `0x2006` at
  `0xd36960`), sender `0xd36900`. Seal `bl 0xd5c828` at `0xd36974` with no intervening write
  primitive; flush `0xd36984`; wait slot `0x0b` (`li r4,11` at `0xd3698c`). [ELF]

  COMMANDS.md lists `0x2006` under "misc — lobby-layer / isolated" gaps, with no shape.
  This settles the request side: it takes no payload, and the client **does** register a wait
  slot, so it blocks on a reply. The sender is a near-identical sibling of `0x2005`'s
  (`0xd369d0`) — same prologue, same guards (`bl 0xd3614c`, `bl 0xd367f0`), consecutive in the
  binary, differing only in the id and the slot. That makes it a second gate list-style
  request whose reply id is not established here. [ELF]

  **[UNKNOWN]** what it asks for. No `0x2007` builder exists on the send side; the reply is
  presumably one of the `0x2002`-`0x200b` parsers, which is not decided from the send side
  alone.
doc-ref: dev/docs/COMMANDS.md "Unmodelled subsystems" (misc block)
seq: []
