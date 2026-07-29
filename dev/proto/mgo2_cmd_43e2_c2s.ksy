meta:
  id: mgo2_cmd_43e2_c2s
  title: "MGO2 0x43e2 — cancel automatching (client -> server)"
  endian: be
doc: |
  **Cancel the search.** Empty payload — established positively from the ELF, not assumed.

  ## What it is

  [IDENTIFIED 2026-07-28] The blank for this id said only "an argument-less automatch action —
  plausibly the cancel or the enter/leave-queue toggle. **[UNKNOWN: which action.]** No screen has
  been observed sending it." It is the **cancel**, and the client's own error table is what settles
  it: a timeout on this request slot prints *"Unable to **cancel** automatching"* (`0x93D178`) where
  `0x43e0`'s slot prints *"Unable to **start**"* (`0x93CDD4`).

  Confirmed live 2026-07-29 — a player backing out of the search sends it, and the cancel completes
  cleanly.

  ## Answering it is the only way the player sees "Unable to find opponent"

  The client raises error 4934 on a **successful** cancel whose own search timer had already expired
  (`0x93D1D4`). A silent cancel robs the player of the one message that explains the wait.

  Note also that the client **unregisters push channel 60 at state 7** (`0x93D0F8`), *before* it
  sends this. So a match push racing a cancel is parsed and dropped by the client itself — the race
  is harmless by construction rather than by our timing.

  ## Evidence

  Builder `0xD5BBDC`; `bl 0xD5CF40` at `0xD5BC4C` (`li r4,0x43E2` at `0xD5BC44`), seal `0xD5C828` at
  `0xD5BC58`, flush `0xD34CC0` at `0xD5BC68`. **No write primitive between builder and seal**, and
  the sender takes no payload argument beyond the context (null-checked at `0xD5BBE4`). Not
  encrypted. Marks request-status slot **51**.
seq: []
