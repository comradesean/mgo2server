meta:
  id: mgo2_cmd_43a2
  title: "MGO2 0x43a2 — round-end per-weapon tally list (client -> server)"
  endian: be
doc: |
  Sent by the host once per round end, between the per-player 0x4390 reports; acked 0x43a3
  (result 0). First observed 2026-07-23 (TDM; the earlier "never sent" verdict was DM-era
  and wrong), ELF-decoded the same day (builder 0xD41AC0, caller 0x27CC78), and fully
  live-confirmed over eight designed rounds 2026-07-23/24.

  One entry per weapon that caused a TERMINAL EVENT (kill or faint) this round — damage
  alone never creates an entry (a round of two wounding headshots produced no row for that
  weapon), and melee/CQC events never appear even though the weapon table has ids for them
  (PUNCH/CQC stayed silent through knockout rounds; melee lives in the 0x4390 stun pair).
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
      [CONFIRMED-LIVE] The round WINNER's character id. Proven 2026-07-24 by a controlled
      flip: same fresh game, same host (chara 3), only the winner varied — chara 1 wins ->
      header 1 (eleven captures), chara 3 wins -> header 3. Eliminated on the way: the
      reporter/host's id (chara-3-hosted rounds sent 1), a host-transfer artifact (fresh
      game), a constant (it moved). Mechanically it is the cached 0x4101-shaped character
      record the client snapshots per round (ELF trace) — evidently the winner's record.
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
