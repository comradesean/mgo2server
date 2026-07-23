meta:
  id: mgo2_cmd_4105
  title: "MGO2 0x4105 — per-mode stat grid (replies 2/4 and 3/4 of the 0x4102 burst)"
  endian: be
doc: |
  The per-mode statistics matrix. Sent TWICE per 0x4102 burst: once with page 0
  (cumulative) and once with page 1 (weekly) — the stats screen's cumulative/weekly toggle
  switches between them [CONFIRMED, fingerprint v9]. Parser 0xd3e53c stores into
  T+0x138 + mode*0x48 + page*0x360 + column*4; the grid reader is the cluster at 0x9193BC+.

  Client-side derivations (never on the wire): the OTHER row = category total − headshot −
  lockon, clamped at 0 [CONFIRMED v6]; the ALL row = sum of the displayed rows [CONFIRMED
  v8]; the whole Total page and header play time = per-column sums over mode rows 0..6
  [CONFIRMED v5/v6]; title and medal unlocks derive from these values plus 0x4107.
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats"
seq:
  - id: status
    type: u4
    doc: "Observed 0; unlike 0x4103 no error branch was traced in this parser."
  - id: page
    type: u4
    enum: period
    doc: |
      MUST be 0 or 1 — any larger value makes the parser bail (error -0x47) and silently
      discard the whole matrix [READ 0xd3e5e4; the v1-v4 fingerprint rounds proved the
      failure mode live]. Page 0 receipt zeroes the full grid region (both pages).
  - id: modes
    type: mode_stats
    repeat: expr
    repeat-expr: 8
    doc: |
      Wire order = client mode-loop order (12-slot loop skipping indices 6/8/9/10)
      [CONFIRMED v5]: 0 Deathmatch, 1 Team Deathmatch, 2 Rescue, 3 Capture, 4 Sneaking,
      5 Base, 6 HIDDEN (no page of its own but summed into every Total and the header
      time — plausibly reserved for an unshipped mode; identity parked. SERVE ZEROS),
      7 unused (excluded from all sums; serve zeros).
enums:
  period:
    0: cumulative
    1: weekly
types:
  mode_stats:
    doc: "18 u32 columns. 16 of 18 mapped [CONFIRMED v5/v6/v8]; 13 and 15 open."
    seq:
      - id: all_kills
        type: u4
        doc: |
          col 0. Category total incl. "other". Display: only used to derive OTHER KILLS
          (this − hs − lockon, clamped ≥0); the ALL row is client-summed. Send as
          other + hs + lockon. [CONFIRMED v6+v8]
      - id: all_deaths
        type: u4
        doc: "col 1. As all_kills, for deaths. [CONFIRMED]"
      - id: lockon_kills
        type: u4
        doc: "col 2. [CONFIRMED]"
      - id: score
        type: s4
        doc: "col 3. Signed — round score can be negative. [CONFIRMED position; sign by analogy to 0x4390]"
      - id: all_stuns
        type: u4
        doc: "col 4. As all_kills, for stuns. [CONFIRMED]"
      - id: all_stuns_received
        type: u4
        doc: "col 5. As all_kills, for stuns received. [CONFIRMED]"
      - id: hs_kills
        type: u4
        doc: "col 6. Headshot kills. [CONFIRMED]"
      - id: hs_deaths
        type: u4
        doc: "col 7. [CONFIRMED]"
      - id: hs_stuns
        type: u4
        doc: "col 8. [CONFIRMED]"
      - id: hs_stuns_received
        type: u4
        doc: "col 9. [CONFIRMED]"
      - id: lockon_stuns
        type: u4
        doc: "col 10. [CONFIRMED]"
      - id: lockon_deaths
        type: u4
        doc: "col 11. [CONFIRMED]"
      - id: lockon_stuns_received
        type: u4
        doc: "col 12. [CONFIRMED]"
      - id: unknown_13
        type: u4
        doc: "col 13. [UNKNOWN] — fp marker 52300 (v6, Deathmatch) surfaced nowhere on the stats screen."
      - id: rounds
        type: u4
        doc: "col 14. [CONFIRMED]"
      - id: unknown_15
        type: u4
        doc: "col 15. [UNKNOWN] — fp marker 52500 (v6) surfaced nowhere; candidates: post-game/ranking views."
      - id: wins
        type: u4
        doc: "col 16. Not rendered on the Deathmatch page (no Wins there) but present in every row. [CONFIRMED]"
      - id: play_seconds
        type: u4
        doc: "col 17. Play time in seconds; rendered hh:mm:ss (\"Total Time Playing X\") and summed into the header time. [CONFIRMED]"
