meta:
  id: mgo2_cmd_4e00_c2s
  title: "MGO2 0x4e00 — Survival Match List request, no payload (client -> server)"
  endian: be
doc: |
  **THE 0x4Exx SUBSYSTEM IS THE SURVIVAL MATCH LIST** (identified 2026-08-02, ELF, tier 1), and
  `0x4E00` is its one and only client->server command: *"send me the list of teams currently
  engaged in Survival matches."* The reply is the `0x4E10` / `0x4E11` / `0x4E12` triple on
  pending-request slot 90.

  ## How the block was identified

  Three independent lines, all tier 1:

  1. **The sender's only caller is the screen, and the screen names itself.** `0xD5B05C` has
     exactly **one** `bl` in the whole image, `0x930C08`. That is arm 1 of a ten-way jump table
     (base `0x930B88`, dispatched on a u16 screen state) inside the screen module
     `0x92FDFC`-`0x932AEF`. Every `0x8E0C24(id)` call in that module resolves through disc string
     group `0xF914BF` = "lobby" (set `[2f0293]`, header base 9789 — method in
     dev/docs/AUTOMATCH.md §10), and the module's own strings are:

     | id | text |
     | --- | --- |
     | 806 | `Survival Match List` |
     | 807 | `View info on teams currently\nengaged in Survival matches.` |
     | 808 | `%d wins in a row` |
     | 810 | `DEFENDER / CHALLENGER` |
     | 811 | `-TEAMS-` |

     Sites: 807 at `0x931AB8`, 808 at `0x930270`/`0x931F60`, 810 at `0x9327B0`, 811 at
     `0x9329F4`/`0x932A30`. The neighbouring Tournament List screen is a *different* module
     (`0x8F27E4`-`0x8F4740`, strings 814-823), which is what stops this being a family
     resemblance.

  2. **The data it fills is the Survival event record.** `0x4E10`/`0x4E11`/`0x4E12` write
     `session+0xDBD0` and its entrant table at `+0x0F0` — byte for byte the same object, the same
     128 x 52 table and the same list header (`+0x0E8` magic, `+0x0EC` count) that
     `0x4A10`/`0x4A11`/`0x4A12` write, which mgo2_cmd_4a24_s2c.ksy already settled as the
     **Tournament/Survival event record**. Struct-offset bijection, same accessors
     (`0xD4EA60`, `0xD4EAAC`), not resemblance.

  3. **`0x4E20` writes the Survival ladder record.** Its destination is `0xD3F7B0(session)` =
     `session+0x11558`, at offsets `+0x0C`/`+0x10`/`+0x14`/`+0x18`/`+0x4C`/`+0x50` — exactly the
     participant-A/participant-B win-count/id/name set that mgo2_cmd_43b0_c2s.ksy names and calls
     "the Survival ladder".

  So `0x4Axx` drives the event you are **in**; `0x4Exx` drives the browser that shows the
  Survival matches other teams are in. Same record type, different entry point.

  ## Can the client start this without us? YES — and that is the whole risk

  **Nothing the server sends is required to reach `0x4E00`.** The state machine is driven by the
  screen's own u16 state, not by a UI event, and arm 1 sends the packet unconditionally
  (`0x930C00`-`0x930C08`). If the server never answers:

  ```
  930c48  lwz r9,104(r25) ; addi r9,r9,5 ; cmpwi r9,6000 ; ble -> keep waiting
  930c5c  li r3,5521 ; li r4,-160 ; bl 0x885a08        ; -160 == 0xFFFFFF60
  ```

  `0x885A08(category, code, ctx)` is the error-dialog call, so an unanswered `0x4E00` produces
  **`5521:FFFFFF60`** after ~1200 ticks — the exact stall CLAUDE.md describes. A non-zero result
  in `0x4E12`, or a send failure, produces **`5520:<code>`** instead (`0x930CBC`, `0x930C40`).
  `5520`/`5521` occur at exactly one call site binary-wide (`0x930C68`), so those two categories
  belong to this screen alone.

  **But the screen is gated behind a lobby subtype we do not serve.** The menu entry that opens
  it is chosen at `0x8BC208`:

  ```
  8bc208  lbz r0,660(r21) ; cmpwi r0,4 ; bne -> 0x8bc244
  8bc214  li r3,806  ; 807      ; "Survival Match List"
  8bc244  li r3,816              ; "Tournament List"
  ```

  Byte `660` = `+0x294` on the `0x883F20` object is the **lobby subtype**, and `4` = Survival —
  already established in mgo2_cmd_4a00_s2c.ksy and dev/docs/AUTOMATCH.md §10. [2026-08-03] Its
  two writers are now enumerated: `0x88EDD4`-`0x88EDE8` copies `team+608` (with lobby id from
  `team+604` and rule from `team+609`), and `0x8F9BF0`-`0x8F9C04` copies the same triple from
  `0xD3F7B0(session)+0x08/+0x04/+0x09`. Upstream, `team+608` is written only by the shared
  team-record parser `0xD4AF34` on ids 0x4911/0x4913/0x4987/0x49A1 (read at 0xD4B304) — so
  **subtype 4 must arrive on one of those four commands or the Survival browser menu entry
  never appears**. Survival lobbies
  are Ver. 1.10 content and this server serves none, so today the screen is unreachable and the
  silence is harmless. **That is a deployment gate, not a client-side impossibility**: the day a
  subtype-4 lobby appears in the lobby list, an unanswered `0x4E00` is a hard `5521:FFFFFF60`.
  Record it as a latent hang with a known trigger, not as "cannot happen".

  TIER. Survival is post-launch content. No available client build exercises `0x4E00`, so
  **everything here is tier 1, read from MGO2.elf, and cannot be raised to tier 2.** Not served
  in v1.

  EMPTY PAYLOAD — zero bytes after the 24-byte transport header, established positively
  from the ELF, not left unmapped.

  Evidence (ELF, retail BLUS30109): sender 0xD5B05C, signature (session) only. Builder
  `bl 0xD5CF40` at 0xD5B0CC (`li r4,0x4e00` at 0xD5B0C4) is followed immediately by the
  seal `bl 0xD5C828` at 0xD5B0D8 and the flush `bl 0xD34CC0` at 0xD5B0E8 — no serializer
  call in between (none of 0xD5C86C/0xD5C8A0, 0xD5C8D4/0xD5C918,
  0xD5C95C/0xD5C9BC/0xD5CA1C, 0xD5CA7C, 0xD5CADC, 0xD5D0AC). The builder memsets its
  1024-byte buffer and resets the cursor, so the sealed length is 0.

  Preconditions: session != NULL plus the two generic connection checks (0xD38504,
  0xD3844C) — nothing else. On a successful flush the flow state advances via
  `0xD32E08(session, 90, 1)`.

  **The reply is the 0x4E10/0x4E11/0x4E12 triple, not 0x4E20.** Slot 90 is armed to state 1 here
  and cleared to state 2 by the `0x4E12` parser at `0xD5AA74` — those are the only two writers of
  slot 90 in the image. The earlier note guessing a `0x4E00` -> `0x4E20` pairing from parser
  adjacency (`0xD5B134` follows this sender) is **withdrawn**: `0xD5B134` is `0x4E20`, it consumes
  no request slot at all (it ends at `0xD33CD8(session, 36, ...)`), and it is a server push.

  **COMMANDS.md correction owed (reported, not edited here).** Its line 189 says "`0x4e10` opens a
  request (slot 90 -> state 1) and the client immediately builds and sends `0x4e00` back
  (`li r4,19968` into the builder at `0xD5B0CC`)". That is backwards. `0xD5B0CC` is inside **this
  sender**, `0xD5B05C`, a standalone function; the `0x4E10` parser is `0xD5AD5C`-`0xD5B058` and it
  touches no request slot whatsoever. The direction is `0x4E00` (request, arms slot 90) ->
  `0x4E10`/`0x4E11`/`0x4E12` (reply, closes slot 90). Nothing obliges the *server* to answer
  `0x4E00` with `0x4E00`; the obligation runs the other way.

  Never observed live; not answered by this server. As a bare argument-less request its
  reply is scoped entirely by session state — the client already knows which lobby it is in, and
  `0x4E10` echoes an `event_id` that `0x4E12` and `0x4E20` are then required to match. A bare ack
  will not satisfy it: the screen advances only when slot 90's *result* is 0 (`0xD5A948` ->
  `0xD330C4(session, 90)` at `0x930CA0`), which only `0x4E12` sets.
seq: []
