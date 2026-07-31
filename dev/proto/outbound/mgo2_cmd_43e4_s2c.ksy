meta:
  id: mgo2_cmd_43e4_s2c
  title: "MGO2 0x43e4 — automatch search panel push (server -> client)"
  endian: be
doc: |
  **The search panel, pushed unsolicited on channel 60.** 36 bytes. The client repaints only when
  this arrives and never requests one, so a tick that pushes nothing leaves the player watching a
  stopwatch.

  **It can never cause a stall.** It uses the fire-and-forget event path `0xD33CD8`, not the
  request-status completion path that `0x43e1` (slot 50) and `0x43e3` (slot 51) use. Nothing waits
  on it, an all-zero push renders a flat graph, and no value it can carry changes control flow.

  Each recipient needs its **own** buffer: `players_needed` is relative to the recipient, so this is
  not broadcastable.

  ## Evidence

  Destination base `A = ctx+0x10000`, the same block `0x43E1` partially fills: `band` -> `A+0x14A1`,
  `players_needed` -> `A+0x14A2`, `event_arg` -> `A+0x14A3`, `unused` -> `A+0x14A4`, and the two
  16-byte arrays at `A+0x14A5` and `A+0x14B5`.

  The 23-column axis is confirmed four ways: the loop bound at `0x93C790` and four 23-entry sprite
  hash tables at `0xE14BA0 + 128/220/312/404`. The centre column is the recipient's own level, which
  the client computes for itself via `0x6F9260` and clamps 0-22 at `0x93C348`.

seq:
  - id: array_a
    size: 16
    doc: |
      [PARTIAL] 23 packed nibbles — byte *j* holds column `2j` in the low nibble and `2j+1` in the
      high, columns 0-22. **12 bytes carry data, 4 are ignored.**

      **What A and B count is UNKNOWN**, and an earlier reading was withdrawn 2026-07-28. This file
      once said one series is players queued and the other players in a game, from the disc strings
      "Entry Status" (915) / "Matching" (924) / "In Game" (923). That was an inference from three
      nearby strings, and reference footage of a real Konami-era session refutes it: filling this
      array with a per-level count of searchers draws a visible bar above the player's own column,
      and no such bar appears in the footage.

      What the ELF establishes is only that the client draws `A[i] + B[i]` per column, clamped to 15
      (960 px / 64 px per unit, `0x93C754`-`0x93C784`). **The server sends zeros in both**, which
      renders the flat graph the footage shows.
  - id: band
    type: u1
    doc: "[PARTIAL] Same as `0x43e1`'s — re-sent widened on every push."
  - id: players_needed
    type: u1
    doc: "[CONFIRMED LIVE] Same as `0x43e1`'s, and per-recipient. See that schema."
  - id: event_arg
    type: u1
    doc: "[CONFIRMED] Passed to event 42 and **discarded by the only handler**."
  - id: array_b
    size: 16
    doc: "[PARTIAL] Same packing and the same unknown as `array_a`."
  - id: unused
    type: u1
    doc: "[CONFIRMED] Stored at block+4 and **never read anywhere**."
