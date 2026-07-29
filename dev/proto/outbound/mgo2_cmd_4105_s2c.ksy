meta:
  id: mgo2_cmd_4105_s2c
  title: "MGO2 0x4105 — per-mode stat grid (replies 2/4 and 3/4 of the 0x4102 burst)"
  endian: be
doc: |
  The per-mode statistics matrix. Sent TWICE per 0x4102 burst: once with page 0
  (cumulative) and once with page 1 (weekly) — the stats screen's cumulative/weekly toggle
  switches between them [CONFIRMED, fingerprint v9]. Parser 0xd3e53c stores into
  T+0x138 + mode*0x48 + page*0x360 + column*4; the grid reader is the cluster at 0x9193BC+.

  Client-side derivations (never on the wire): the OTHER row = the category's minuend
  column − headshot − lockon, clamped at 0 [CONFIRMED v6]; the ALL row = sum of the displayed rows [CONFIRMED
  v8]; the whole Total page and header play time = per-column sums over mode rows 0..6
  [CONFIRMED v5/v6]; title and medal unlocks derive from these values plus 0x4107.

  Since 2026-07-23 every operand of the OTHER derivation has a known accumulation source in
  the 0x4390 round reports (round_report table): headshots at report 0x11, lock-on kills at
  0x09 (single-variable-round confirmed), so a served minuend composes as
  other + headshots + lockon per mode/period. See PROTOCOL.md "0x4390 — update stats".
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

      NOTE: the extra per-mode lines on the stats screen (Consecutive Survivals on TDM,
      Bases Conquered / SOP Destabilizer Uses on Base, the GA-KO trio on Rescue, the
      Snake trio on Sneaking) are NOT grid columns — they are 0x4107 personal-score
      slots the UI overlays onto the mode pages. See mgo2_cmd_4107.ksy.
enums:
  period:
    0: cumulative
    1: weekly
types:
  mode_stats:
    doc: "18 u32 columns. 16 of 18 mapped [CONFIRMED v5/v6/v8]; 13 and 15 open."
    seq:
      - id: other_kills_minuend
        type: u4
        doc: |
          col 0. PROVEN role only: the client renders OTHER KILLS = this − hs_kills −
          lockon_kills, clamped ≥0 [CONFIRMED v6], and this value itself never renders
          [CONFIRMED v8]. Therefore a server wanting OTHER to show x must send
          x + hs + lockon. Whether the original server semantically treated it as
          "total kills" is [UNKNOWN] — the name states the derivation, not a meaning.
      - id: other_deaths_minuend
        type: u4
        doc: "col 1. As other_kills_minuend, for deaths (OTHER DEATHS = this − hs − lockon). [CONFIRMED v6]"
      - id: lockon_kills
        type: u4
        doc: "col 2. [CONFIRMED]"
      - id: score
        type: s4
        doc: "col 3. Signed — round score can be negative. [CONFIRMED position; sign by analogy to 0x4390]"
      - id: other_stuns_minuend
        type: u4
        doc: "col 4. As other_kills_minuend, for stuns. [CONFIRMED v6]"
      - id: other_stuns_received_minuend
        type: u4
        doc: "col 5. As other_kills_minuend, for stuns received. [CONFIRMED v6]"
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
