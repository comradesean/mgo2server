meta:
  id: mgo2_cmd_43f2_s2c
  title: "MGO2 0x43f2 — automatch game id push (server -> client)"
  endian: be
doc: |
  **The game the cohort is to join.** 4 bytes, pushed on channel 60.

  **It is a one-shot.** Processing it *unregisters channel 60*, so nothing pushed afterwards reaches
  the screen — in particular `0x43f3` is only ever reachable *before* this.

  ## It must go to the HOST as well as the joiners

  This was removed from the host once, on the theory that a host who had just created the game did
  not need to be told to join it. That was a regression: the host then **never left the
  "automatching successful" screen**. The client's own error table had already said so — error 4945
  exists on the host's event-45 path, which only makes sense if the host expects this push.

  The failure is asymmetric, which is what decides it: a spurious push to a host who has already left
  is parsed and dropped, while omitting it parks the host at state 13 forever.

  A client that receives this with **no preceding `0x43f1`** takes the joiner branch, because its
  host id is still 0 and the `hostId == myId` test fails. That is a reading of the control flow
  (event 45 stores the id and goes to state 11) and **has not been observed** — slot-in, the only
  flow that would produce it, is parked.

  ## Evidence

  Parser **`0xD5B588`**, reached from the GAME dispatcher `0xD387C8` (compare tree `0xD38804`) via
  the stub at `0xD39D7C`. It resolves the subsystem object with `0xD3F7B0`, checks the header id
  (`cmpwi 0x43F2` at `0xD5B5E0`), opens the reader (`0xD5C844`), reads **exactly one u32**
  (`0xD5CCD8` at `0xD5B600`) into `obj+0x90`, closes the reader, then reloads `obj+0x90` and calls
  `0xD33CD8` with **UI event 45 (`0x2D`)** and that value, followed by `0xD5B41C` (the screen/state
  poke shared with `0x43F3` and `0x43F4`).

  Note this family does **not** use the status/result setters `0xD32E08` / `0xD32E70` — it is a push
  path, not a request/reply transaction, which is why nothing completes and nothing times out.

  **The parser has no zero/nonzero branch on the value**, so it is not a result code; the id is
  simply taken at face value.

seq:
  - id: game_id
    type: u4
    doc: |
      [CONFIRMED] The game to join. Also stored at `gameObj+144`.

      **Do not send this until the elected host's `0x4310` and `0x4316` have landed**, or the id
      names a game whose rule and map are still 0 — `createGame` commits the row before
      `applyHostSettings` runs, in a separate `try`. The server observes the create via a
      notification hook rather than polling, precisely to close that window.
