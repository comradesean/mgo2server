meta:
  id: mgo2_cmd_43a2
  title: "MGO2 0x43a2 — per-player round weapon tallies (client -> server, one per scorer)"
  endian: be
doc: |
  PER-PLAYER weapon-breakdown appendix to the 0x4390 stat report: at round end the host
  sends, for EACH player with at least one tally entry, that player's 0x43a2 immediately
  after their 0x4390 (players with empty lists are skipped — the count==0 early return in
  the ELF caller). Header = THAT player's character id; entries = their personal per-weapon
  terminal-event tallies. Settled 2026-07-24 after a night of false theories (winner / MVP /
  top-scorer / finishing-blow), every one an artifact of sampling only the LAST packet per
  round; a three-scorer round emits three packets, one per scorer, ids and tallies matching
  each player's own stats exactly. Sent in every mode including DM.

  One entry per weapon with which THIS PLAYER caused a TERMINAL EVENT (kill or faint) —
  damage alone never creates an entry (two wounding headshots produced no row), and
  melee/CQC events never appear even though the weapon table has ids for them (melee lives
  in the 0x4390 stun pair). Weapon ids index the ELF's 141-entry master table,
  dev/docs/WEAPONS.md (anchors: ST KNIFE 1, RUGER 2, GSR 7, Vz.83/SKORPION 23, AK102 25,
  MOSIN N 43). Builder caps entries at 0x7f, caller at 50.

  The server acks and STORES these since 2026-07-28 (round_weapon_tally); they feed 0x4107
  slot 64 Knife Kills, which struct B cannot carry. Was: "acks and currently stores nothing"
  (BACKLOG, "Store 0x43a2 per-weapon round
  tallies" — now attributable per player, which that entry wondered about).
doc-ref: dev/docs/PROTOCOL.md "0x43a2 — per-player weapon tallies"
seq:
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED-LIVE] THIS packet's player — the character whose weapon tallies follow.
      Verified across three simultaneous per-player packets whose ids and tallies each
      matched that player's own 0x4390 stats. (Mechanically: the head of the per-player
      round record, as the ELF trace said before a night of sampling-artifact theories.)
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
