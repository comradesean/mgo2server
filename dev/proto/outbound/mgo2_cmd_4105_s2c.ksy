meta:
  id: mgo2_cmd_4105_s2c
  title: "MGO2 0x4105 — per-mode stat grid (replies 2/4 and 3/4 of the 0x4102 burst)"
  endian: be
doc: |
  The per-mode statistics matrix. Sent TWICE per 0x4102 burst: once with page 0
  (cumulative) and once with page 1 (weekly) — the stats screen's cumulative/weekly toggle
  switches between them [CONFIRMED, fingerprint v9]. Parser 0xd3e53c stores into
  T+0x138 + memRow*0x48 + page*0x360 + column*4, where memRow is the *client mode id*, not
  the wire index — see the `modes` field. The grid reader is the cluster at 0x9193BC+.

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
      Wire order = client mode-loop order [CONFIRMED v5; mechanism read 2026-07-30 at
      0xd3e60c-0xd3e650: `r27` counts client mode ids 0..11, the four `beq` at
      0xd3e614/0xd3e61c/0xd3e624/0xd3e62c skip ids 6, 8, 9 and 10, and the row is stored at
      `T + 312 + r27*72 + page*864`]. So **wire index ≠ memory row**: the eight wire records
      land on memory rows 0,1,2,3,4,5,7,11, and the memset at 0xd3e5f4 clears 3456 bytes =
      12 rows × 4 pages.

      Identities, now tier-1 rather than inferred — the DETAIL page's seven "Total Time
      Playing X" rows each read `memRow*72 + 68` (column 17) and carry a disc label:

        wire 0 → row 0  Deathmatch       (hash 0x39b481, read 0x918304)
        wire 1 → row 1  Team Deathmatch  (0x39b482, 0x918314)
        wire 2 → row 2  Rescue           (0x39b485, 0x918344)
        wire 3 → row 3  Capture          (0x39b484, 0x918334)
        wire 4 → row 4  Sneaking         (0x39b49d, 0x918364)
        wire 5 → row 5  Base             (0x39b483, 0x918324)
        wire 6 → row 7  **TEAM SNEAKING** (0x39b49c, 0x918354)
        wire 7 → row 11 no label, no row, no reader

      **Wire index 6 is Team Sneaking**, not an unidentified reserved slot: disc string
      group [1ab3b6] name hash 0x39b49c = "Total Time Playing TEAM SNEAKING", and the
      seventh mode page (dispatcher arm `byte[16]` at 0x917618) is the one that overlays
      `SP_SCORE_TSNE01/02` — see mgo2_cmd_4107.ksy slots 33/34. It has no *visible* page on a
      release-day server only because rule 7 was switched on 2008-07-04. SERVE ZEROS.

      The Total-page sum loops (0x9193ac, 0x919478, 0x91955c, … all identical) iterate memory
      rows 0..7 gated by the bitmask `li r0,191` → `sraw r0,r0,r7` → `clrldi. r9,r0,63`:
      0xBF has bit 6 clear, so memory row 6 (never written by the parser) is skipped and
      memory row 7 — wire index 6 — **is** summed. That is exactly what fingerprint v5
      measured (the 3115 residual), and it means the earlier reading "wire 6 hidden but
      summed / wire 7 unused" was right about the arithmetic and wrong about which of them
      had a page. Memory row 11 (wire 7) is outside the loop bound entirely.

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
        doc: |
          col 13 (cell offset `312 + row*72 + 52`). [UNKNOWN] — fp marker 52300 (v6,
          Deathmatch) surfaced nowhere on the stats screen, and the ELF now agrees:
          **no reader anywhere in the image**.

          How that was established (2026-07-30): every grid access in the binary has the
          shape `addi rX,rY,K` (K = 304/320/336/352/368) → `add` with the T pointer →
          `lwz rZ,D(rX)` with D ≤ 32, inside a window containing `mulli …,72` or
          `mulli …,864`. Enumerating all such sites image-wide yields hits for columns
          0,1,2,3,4,5,6,7,8,9,10,11,12,14,16,17 — and **zero** for column 13 (which would be
          K=352,D=12) and column 15 (K=352,D=20). Columns 12 and 14 are read at 0x919688 /
          0x91a074 with the same K=352 base, so the addressing form is not the reason 13 is
          missing.

          What would settle it: a reader appearing in a later client build, or the original
          server's own accounting. Do not guess it from column 12's or 14's meaning.
      - id: rounds
        type: u4
        doc: "col 14. [CONFIRMED]"
      - id: unknown_15
        type: u4
        doc: |
          col 15 (cell offset `312 + row*72 + 60`). [UNKNOWN] — fp marker 52500 (v6)
          surfaced nowhere, and the same image-wide scan described on `unknown_13` finds
          **no reader** for K=352,D=20 either. The old note "candidates: post-game/ranking
          views" is retracted as unsupported: those screens do not address this grid at all
          (every 72/864-strided access in the binary lives in 0x9193bc-0x91a130, the stats
          screen, plus the DETAIL play-time rows at 0x918304-0x918378).
      - id: wins
        type: u4
        doc: "col 16. Not rendered on the Deathmatch page (no Wins there) but present in every row. [CONFIRMED]"
      - id: play_seconds
        type: u4
        doc: "col 17. Play time in seconds; rendered hh:mm:ss (\"Total Time Playing X\") and summed into the header time. [CONFIRMED]"
