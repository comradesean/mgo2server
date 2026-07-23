meta:
  id: mgo2_cmd_4221
  title: "MGO2 0x4221 — player-details card (single reply to 0x4220 {u32 character id})"
  endian: be
  encoding: ISO-8859-1
doc: |
  Single reply (no triple) to the 0x4220 player-details request — the history row's
  "Player Details" context-menu item (observed live 2026-07-23). Sender 0xd3b950, parser
  0xd3d874, subsystem index 0x1c. 201 bytes total: u32 result code, then 197 bytes of
  fields. A nonzero result skips every field read and surfaces via the open screen's error
  dialog (no fixed screen constant in this path). Field POSITIONS and client struct
  destinations are READ from the parser (ELF trace 2026-07-23); labels from the live
  fingerprint pass the same day (u32s 95xx, u8s 6x, FP-DTL-* strings served). The card
  renders NAME, CLAN ("---" despite a string being sent — gated or mislabelled), LEVEL
  (22 displayed, matching no sent value — likely derived from an exp-like u32 via a level
  table), PLAY TIME, COMMENTS, and a square-button "more details" that requests the 0x4102
  personal-stats burst for this card's character id.
doc-ref: dev/docs/PROTOCOL.md "0x4220 — player details"
seq:
  - id: result
    type: u4
    doc: "[CONFIRMED] Result code: 0 = success; nonzero skips all fields and raises the error dialog (parser 0xd3d8e8 branch)."
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED-BY-USE] character id — dest T+0x000; we echo the requested id. The card's
      square-button "more details" sends 0x4102 with this character (fake 9101 produced our
      not-found status 1, rendered 1036:00000001 — screen 0x1036 = character information).
  - id: name
    type: str
    size: 16
    doc: "[CONFIRMED] player name — dest T+0x004. FP-DTL-NAME rendered as NAME on the card."
  - id: unknown_u32_a
    type: u4
    doc: "[UNKNOWN] dest T+0x120. Fingerprint 9501 — not visibly rendered; LEVEL-source candidate (22 displayed, table-derived?)."
  - id: unknown_u8_a
    type: u1
    doc: "[UNKNOWN] dest T+0x3328. Fingerprint 61."
  - id: unknown_u8_b
    type: u1
    doc: "[UNKNOWN] dest T+0x3329. Fingerprint 62."
  - id: unknown_u32_b
    type: u4
    doc: "[UNKNOWN] dest T+0x484. Fingerprint 9502 — not visibly rendered; LEVEL-source candidate (adjacent to play time)."
  - id: play_time_seconds
    type: u4
    doc: "[CONFIRMED] total play time in seconds — dest T+0x494. Fingerprint 9503 rendered as PLAY TIME 02:38:23 (= 9503 s)."
  - id: unknown_u8_c
    type: u1
    doc: "[UNKNOWN] dest T+0x1ea5. Fingerprint 63."
  - id: comment
    type: str
    size: 128
    doc: "[CONFIRMED] player comment — dest T+0x1e24. FP-DTL-COMMENT-128 rendered as COMMENTS on the card."
  - id: unknown_u32_d
    type: u4
    doc: "[UNKNOWN] dest T+0x1aa0. Fingerprint 9504."
  - id: clan_name
    type: str
    size: 16
    doc: |
      [CANDIDATE, WEAKENED] second name-width string — clan? dest T+0x1aa4. FP-DTL-CLAN was
      sent but the card's CLAN slot rendered "---": either the label is wrong or display is
      gated (e.g. on the u32 before it being a valid clan id; fingerprint 9504 sent there).
  - id: unknown_u8_d
    type: u1
    doc: "[UNKNOWN] dest T+0x1ab5. Fingerprint 64."
  - id: unknown_u32_e
    type: u4
    doc: "[UNKNOWN] dest T+0x32d8. Fingerprint 9505."
  - id: unknown_u32_f
    type: u4
    doc: "[UNKNOWN] dest T+0x32dc. Fingerprint 9506."
  - id: unknown_u8_e
    type: u1
    doc: "[UNKNOWN] dest T+0x1ad8. Fingerprint 65."
  - id: unknown_u32_g
    type: u4
    doc: "[UNKNOWN] dest T+0x124. Fingerprint 9507."
