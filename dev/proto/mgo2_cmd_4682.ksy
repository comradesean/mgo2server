meta:
  id: mgo2_cmd_4682
  title: "MGO2 0x4682 — match-history list record(s) (item packet of the 0x4680 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Item packet of the 0x4680 match-history triple (0x4681 start {u32 result} / 0x4682 items /
  0x4683 end {u32 result}). The start/end u32 is a RESULT CODE, not a count — 0 required in
  both (a nonzero start aborts the screen with dialog 1032:%08X, and the end value overwrites
  the client's result slot unconditionally; handlers 0xd3adf4/0xd3acf8, live-confirmed
  2026-07-23 when sending a count of 5 produced 1032:00000005). Records are packed back to
  back with no per-packet count — the parser (0xd3b5fc) reads until the payload ends and the
  client counts them itself; table caps at 64 entries, 25 bytes each on the wire (struct
  stride 0x1c).

  Field POSITIONS are READ from the ELF parser. Live fingerprint 2026-07-23: the screen is a
  MET-PLAYERS history, one row per player encountered — each row shows the timestamp and the
  name, and selecting a row opens a player context menu (Player Details / Create Mail /
  Add to Friend List / Add to Block List). "Player Details" sends 0x4220 (the player-card
  family), NOT 0x4684 — what triggers 0x4684 is now unknown again.
doc-ref: dev/docs/PROTOCOL.md "0x4600 / 0x4680 / 0x4684 — player search and match history"
seq:
  - id: records
    type: history_record
    repeat: eos
types:
  history_record:
    seq:
      - id: timestamp
        type: u4
        doc: |
          [CONFIRMED] Unix seconds, rendered as the row's date. Live fingerprint 2026-07-23:
          sent 978397261 (2001-01-02 01:01:01 UTC), screen showed "01-02-2001 04:01:01" —
          date exact, time +3h (emulated-clock timezone handling unresolved; note the
          rendered format was MM-DD-YYYY, not the %Y/%m/%d ELF resource).
      - id: chara_id
        type: u4
        doc: |
          [CONFIRMED] character id. Live 2026-07-23: row 1 carried fingerprint 9101 and
          selecting "Player Details" sent 0x4220 with payload 9101 (server log) — the
          client echoes this field as the id for the row's player-scoped actions.
      - id: name
        type: str
        size: 16
        doc: |
          [CONFIRMED] NUL-padded player name — rendered verbatim as the row label
          (FP-ROW-1..5 displayed) on the met-players history screen.
      - id: unknown_flag
        type: u1
        doc: "[UNKNOWN] Fingerprint 40+row sent; nothing visibly rendered. Nomad's test payload sent 0."
