meta:
  id: mgo2_cmd_4221_s2c
  title: "MGO2 0x4221 — player-details card (single reply to 0x4220 {u32 character id})"
  endian: be
  encoding: ISO-8859-1
doc: |
  Single reply (no triple) to the 0x4220 player-details request — the history row's
  "Player Details" context-menu item (observed live 2026-07-23). Sender 0xd3b950, parser
  0xd3d874, subsystem index 0x1c. 201 bytes total: u32 result code, then 197 bytes of
  fields. A nonzero result skips every field read and surfaces via the open screen's error
  dialog (no fixed screen constant in this path). Field POSITIONS and client struct
  destinations are READ from the parser (ELF trace 2026-07-23); labels came from the live
  fingerprint pass the same day (u32s 95xx, u8s 6x, FP-DTL-* strings served), and the card
  has since been filled in with real data (live 2026-07-27).

  The card renders NAME, CLAN, LEVEL, PLAY TIME, COMMENTS, and a square-button "more
  details" that requests the 0x4102 personal-stats burst for this card's character id.
  NAME, CLAN, PLAY TIME and COMMENTS are all confirmed rendering correctly with real data.
  LEVEL is the one open question — see `unknown_18`..`unknown_1e` below.

  RESOLVED 2026-07-27 — the CLAN "---" reading. The 2026-07-23 pass sent FP-DTL-CLAN into
  the 16-byte string at wire 0xab and the card's CLAN slot rendered "---", which was
  recorded here as [CANDIDATE, WEAKENED] with two live alternatives: "either the label is
  wrong or display is gated". The second alternative is correct and the first is falsified.
  Wire 0xa7/0xab/0xbb are a `{u32 id, char name[16], u8 state}` triple — the same shape a
  clan takes everywhere else in this protocol (session record at +0x1AA0, 0x4122's block,
  0x4b47, 0x4b21's head, 0x4103's tail) — and every reader traced so far checks the ID
  first, treating a zero id as "no clan" whatever the name says. Sending only the name was
  never going to render. With the id and state sent alongside it, the clan renders.
doc-ref: dev/docs/PROTOCOL.md "0x4220 — player details"
seq:
  - id: result
    type: u4
    doc: "[CONFIRMED] Wire 0x00. Result code: 0 = success; nonzero skips all fields and raises the error dialog (parser 0xd3d8e8 branch)."
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED-BY-USE] Wire 0x04, character id — dest T+0x000; we echo the requested id. The
      card's square-button "more details" sends 0x4102 with this character (fake 9101 produced
      our not-found status 1, rendered 1036:00000001 — screen 0x1036 = character information).
  - id: name
    type: str
    size: 16
    doc: "[CONFIRMED] Wire 0x08, player name — dest T+0x004. FP-DTL-NAME rendered as NAME; renders the real character name live 2026-07-27."
  - id: unknown_18
    type: u4
    doc: |
      [UNKNOWN] Wire 0x18 -> dest T+0x120. LEVEL-source candidate 1 of 4 — see the note on
      `unknown_1e`. Currently carrying live probe value 1450 (level 10 through the client's
      experience table).
  - id: unknown_1c
    type: u1
    doc: |
      [UNKNOWN] Wire 0x1c -> dest T+0x3328. LEVEL-source candidate 2 of 4. Currently carrying
      live probe value 250 (level 2).
  - id: unknown_1d
    type: u1
    doc: |
      [UNKNOWN] Wire 0x1d -> dest T+0x3329. LEVEL-source candidate 3 of 4. Currently carrying
      live probe value 130 (level 1).
  - id: unknown_1e
    type: u4
    doc: |
      [UNKNOWN] Wire 0x1e -> dest T+0x484. LEVEL-source candidate 4 of 4. Currently carrying
      live probe value 500 (level 4).

      OPEN QUESTION — which of these four fields drives LEVEL. The card renders LEVEL as 0
      with real data, and four fields sit between `name` and `play_time_seconds`: wire 0x18
      (u32), 0x1c (u8), 0x1d (u8), 0x1e (u32). None has been identified.

      PROBE DESIGN, live as of 2026-07-27. Probe round 1 sent 11 / 22 / 33 / 44 and LEVEL
      still read 0 — consistent with the driving field being an EXPERIENCE value rather than a
      level, because the client derives the level from a threshold table (125, 250, 375, 500,
      650, ...) and all four of those values fall below the first threshold, so every one of
      them would render as level 0. Round 1 therefore eliminated nothing (per CLAUDE.md, an
      elimination only counts if the experiment could have produced the confirming
      observation, and this one could not).

      Round 2, currently on the wire, sends 1450 / 250 / 130 / 500 — chosen so that each maps
      to a DISTINCT level through that table: 10 / 2 / 1 / 4 respectively. Whichever level the
      card renders names the field. Until that observation is made, all four stay [UNKNOWN]
      and no guess is recorded here.
  - id: play_time_seconds
    type: u4
    doc: |
      [CONFIRMED] Wire 0x22, dest T+0x494. Total play time in seconds. Fingerprint 9503
      rendered as PLAY TIME 02:38:23 (= 9503 s).

      DEFINITION (live 2026-07-27): this is the SUM ACROSS GAME MODES, not the raw stored
      aggregate. The client totals the per-mode column itself, so the figure this card shows
      must equal the figure the personal-stats screen shows — the aggregate times the number
      of populated mode rows. Sending the raw stored aggregate here read SIX TIMES SHORT
      against the stats screen, because six mode rows were populated.

      Separate known problem, recorded so the definition is not mistaken for correctness: the
      total is INFLATED. The server stores one play-time number and writes it into every mode
      row because there is no per-mode accounting. Both screens agree with each other; neither
      agrees with reality.
  - id: unknown_26
    type: u1
    doc: "[UNKNOWN] Wire 0x26 -> dest T+0x1ea5. Fingerprint 63; we send 0."
  - id: comment
    type: str
    size: 128
    doc: "[CONFIRMED] Wire 0x27, player comment — dest T+0x1e24. FP-DTL-COMMENT-128 rendered as COMMENTS; renders the real database comment live 2026-07-27."
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0xa7 -> dest T+0x1aa0. Clan id, and the FIRST member of
      the `{u32 id, char name[16], u8 state}` clan triple. This is the gate: every reader
      traced so far checks the id before the name, and treats 0 as "no clan" regardless of what
      the name carries. Zero here is why the fingerprint pass rendered CLAN as "---" while
      sending FP-DTL-CLAN in the string below.
  - id: clan_name
    type: str
    size: 16
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0xab -> dest T+0x1aa4. The clan name, second member of
      the clan triple. Renders in the card's CLAN slot when `clan_id` is nonzero.

      Falsified reading kept on the record: this field was tagged [CANDIDATE, WEAKENED] with
      the "---" symptom and two alternatives, "either the label is wrong or display is gated".
      The label was right; display is gated on `clan_id`. Resolved, not deleted — the symptom
      is what a name-only clan write looks like, and it will look identical anywhere else in
      this protocol that carries the same triple.
  - id: clan_state
    type: u1
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0xbb -> dest T+0x1ab5. Clan membership state, third
      member of the clan triple. Same constants the client writes for itself: 0 affiliation
      pending (0xD58740), 1 member (0xD56B68), 2 leader (0xD56B84), 99 not in a clan
      (0xD56B44 / 0xD56C7C / 0xD56D68, each `li r0,99` alongside a zeroed clan id). Readers
      test membership as `state - 1 <= 1`.
  - id: unknown_bc
    type: u4
    doc: "[UNKNOWN] Wire 0xbc -> dest T+0x32d8. Fingerprint 9505; we send 0."
  - id: unknown_c0
    type: u4
    doc: "[UNKNOWN] Wire 0xc0 -> dest T+0x32dc. Fingerprint 9506; we send 0."
  - id: unknown_c4
    type: u1
    doc: "[UNKNOWN] Wire 0xc4 -> dest T+0x1ad8. Fingerprint 65; we send 0."
  - id: unknown_c5
    type: u4
    doc: "[UNKNOWN] Wire 0xc5 -> dest T+0x124. Fingerprint 9507; we send 0."
