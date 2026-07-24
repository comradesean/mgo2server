meta:
  id: mgo2_cmd_43a2
  title: "MGO2 0x43a2 — round-end per-weapon tally list (client -> server)"
  endian: be
doc: |
  The ROUND-MVP CARD: sent by the host once per round end, between the per-player
  0x4390 reports; acked 0x43a3 (result 0). Identifies the round's OVERALL TOP PERFORMER —
  team outcome irrelevant — and carries THAT PLAYER'S per-weapon breakdown, not the whole
  round's. Proven 2026-07-24 in two steps: a 2v1 where the winning team's second scorer
  was absent from the list, then a 2v2-style round where the LOSING team's 4-kill player
  (id 2) took the header over the winning team's 3-kill player and the round-ending
  killer. Kills-based vs score-based ranking is still confounded (the MVP led both). First observed
  2026-07-23; ELF-decoded (builder 0xD41AC0, caller 0x27CC78); every field live-confirmed
  across thirteen designed rounds. Sent in every mode including DM (the "never sent"
  verdict was a pre-tracing capture gap); skipped only when the winner has no tally
  entries (count 0 -> early return).

  One entry per weapon with which THE WINNER caused a TERMINAL EVENT (kill or faint) —
  damage alone never creates an entry (two wounding headshots produced no row), and
  melee/CQC events never appear even though the weapon table has ids for them (PUNCH/CQC
  stayed silent through knockout rounds; melee lives in the 0x4390 stun pair).
  Weapon ids index the ELF's 141-entry master table, dev/docs/WEAPONS.md (0-based; anchors
  ST KNIFE 1, RUGER 2, GSR 7, SKORPION/Vz.83 23, AK102 25, MOSIN N 43). The builder caps
  entries at 0x7f; the caller further caps at 50 and walks a 127-slot per-round table,
  emitting non-zero slots in id order.

  The server acks and currently stores nothing (BACKLOG, "Store 0x43a2 per-weapon round
  tallies").
doc-ref: dev/docs/PROTOCOL.md "0x43a2 — round-end slot-tally list"
seq:
  - id: winner_chara_id
    type: u4
    doc: |
      [CONFIRMED-LIVE] The round's top performer's character id, INDEPENDENT of team
      outcome (a losing-team 4-kill player took it over the winning team's 3-kill player
      and the round-ending killer). Confirmed across three distinct ids (1/2/3).
      Eliminated on the way: reporter/host id, host-transfer artifact, constant, round
      winner, winning-team-top-scorer. Kills-vs-score ranking unconfounded only when
      those diverge. Mechanically the cached 0x4101-shaped character record the client
      snapshots per round (ELF) — the MVP's record.
  - id: count
    type: u4
    doc: "[CONFIRMED] Number of entries that follow (builder caps 0x7f, caller caps 50)."
  - id: entries
    type: weapon_tally
    repeat: expr
    repeat-expr: count
types:
  weapon_tally:
    seq:
      - id: weapon_id
        type: u1
        doc: |
          [CONFIRMED] Weapon id, 0-based index into the ELF weapon master table
          (dev/docs/WEAPONS.md). Six ids live-anchored via single-variable rounds.
      - id: kills
        type: u2
        doc: "[CONFIRMED] Kills by this weapon this round (AK102 round: 2 kills -> 2)."
      - id: headshots
        type: u2
        doc: |
          [CONFIRMED] Headshot TERMINAL BLOWS by this weapon — a qualifier of the kill or
          faint, never a hit counter: wounding headshots tally nothing (helmet + GSR
          experiment), while a dart headshot that causes the faint counts here even though
          the 0x4390 scoreboard headshot slot (lethal bullets only) refuses it.
      - id: faints
        type: u2
        doc: |
          [CONFIRMED] Faints CAUSED by this weapon (tranq dart on an awake target -> 1;
          30 darts into an already-fainted body -> 0). Melee-caused faints are excluded
          from this list entirely.
