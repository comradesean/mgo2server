meta:
  id: mgo2_cmd_4682
  title: "MGO2 0x4682 — match-history list record(s) (item packet of the 0x4680 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Item packet of the 0x4680 match-history triple (0x4681 start {u32 count} / 0x4682 items /
  0x4683 end {u32 count}). Records are packed back to back with no per-packet count — the
  parser (0xd3b5fc) reads until the payload ends; client table caps at 64 entries, 25 bytes
  each on the wire (struct stride 0x1c).

  Field POSITIONS are READ from the ELF parser. LABELS are candidates only: the SaveMGO
  Nomad dev-era test payload (tier 4, decoded 2026-07-23) and the ELF's history-UI
  %Y/%m/%d %H:%M:%S date resource support {timestamp, id, name, u8} — awaiting live
  fingerprint confirmation. One field must be the entry id the 0x4684 detail request echoes.
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
          [CANDIDATE] Unix seconds — Nomad's test payload puts a timestamp here and the
          history UI renders a %Y/%m/%d %H:%M:%S date. Unconfirmed against the live client.
      - id: entry_id
        type: u4
        doc: |
          [CANDIDATE] id — plausibly the selectable entry id echoed by the 0x4684 detail
          request (u32). Nomad's test payload put a character id here. Unconfirmed.
      - id: name
        type: str
        size: 16
        doc: "[CANDIDATE] NUL-padded name (host? game?). A 16-byte string field per the parser; content label unconfirmed."
      - id: unknown_flag
        type: u1
        doc: "[UNKNOWN] Nomad's test payload sent 0."
