meta:
  id: mgo2_cmd_4682_s2c
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

  ## The record struct — 28 bytes, and the wire byte lands at +25, not +24

  [ELF 2026-07-31, batch 3c] The parser builds each record in a 28-byte stack scratch at `r1+112`,
  zeroed up front (`stvx` 0..15, `std` 16..23, `stw` 24..27 at `0xd3b674`-`0xd3b680`), then copies
  it whole into the list with `lswi`/`stswi` r5,28 at `0xd3b72c`. The four reads are
  `0xd5ccd8 -> +0`, `0xd5ccd8 -> +4`, `0xd5d018 r5=16 -> +8`, `0xd5cb8c -> +25`.

  So the struct is `{u32 timestamp; u32 chara_id; char name[16]; u8 ZERO; u8 lobby_type; u8[2]}` —
  **struct byte +24 is a hole the parser never writes**, and the fifth wire byte goes to +25. The
  wire is still strictly sequential 4+4+16+1 = 25 bytes; only the struct has the gap.

  List head is `*(session+6404) + 0x20000 + 27924` (= `T+0x26d14`, as OBSERVED.md records):
  `{u32 result_slot; u32 count; record[64] at +8}`. Accessors `0xd3f5a0` `GetRow(session, i)`
  (bounds-checked against `count`, `mulli 28`) and `0xd3f5f8` `GetCount(session)`. The count cap of
  64 is the parser's own `cmpwi cr7,r4,63; bgt` at `0xd3b710`.

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
          [ELF 2026-07-31] **`0xFFFFFFFF` is a sentinel, not a date**: each painter tests
          `lwz r3,0(rec); cmpwi -1` (`0x91e4bc`/`0x91e4c0`) and on a match skips the formatter
          entirely, printing the single-space string into both the date and the time elements.
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
      - id: lobby_type
        type: u1
        doc: |
          [ELF 2026-07-31, batch 3c] **The lobby/game type of the match in which this player was
          met**, rendered as the row's type column. Was `unknown_flag`.

          Struct offset **+25** (see the header). Read by all four met-players row painters —
          `0x91e598`, `0x91ec84`, `0x91f55c`, `0x9202c8`, each `lbz r9,25(r9)` with the record
          pointer live in `r27` from `0xd3f5a0`. These are the only four `lbz ...,25(...)` sites in
          the history screen and the field's only readers anywhere.

          Each painter does `v-1`, rejects `(v-1) & 0xFF > 8`, and dispatches an **8-entry-wide,
          9-arm jump table** (`0x91e5c4`, offsets read `lwax` and added to the table base). Six arms
          load a UI object name from the module TOC, hash it (`0xd25d0`) and resolve it as
          `GetString(0x23326A, hash)`; three call `GetString` with a literal group and name hash:

          | value | arm | label |
          | --- | --- | --- |
          | 1 | `0x91e60c` | `TYPE_FREEBATTLE` |
          | 2 | `0x91e650` | `GetString(0x00F914BF, 0x00A6FC6D)` — the Lobby Select message resource |
          | 3 | `0x91e61c` | `TYPE_TOURNAMENT` |
          | 4 | `0x91e624` | `TYPE_SURVIVAL` |
          | 5 | `0x91e62c` | `TYPE_TOURNAMENT_OFFICIAL` |
          | 6 | `0x91e634` | `TYPE_SURVIVAL_OFFICIAL` |
          | 7 | `0x91e664` | `GetString(0x00654515, 0x0083889F)` |
          | 8 | `0x91e678` | `GetString(0x00654515, 0x0077B743)` |
          | 9 | `0x91e614` | `TYPE_COOP` |
          | 0, or >9 | `0x91e5e8` | the single-space string at `-32760(r30)` — column blank |

          The six `TYPE_*` pointers are the contiguous array at **`0xFE85F0`** (module TOC
          `r30 = 0xFF05E0`, offsets `-32752`..`-32732`), the one `LOBBIES.md` describes as
          "reached through a base register loaded from the TOC, so nothing in the image points at
          it directly". This is the code that reaches it, and **it settles that file's open
          question in the negative: the mapping is NOT `index = subtype - 1`.** Array order is
          FREEBATTLE, COOP, TOURNAMENT, SURVIVAL, TOURNAMENT_OFFICIAL, SURVIVAL_OFFICIAL but the
          values are 1, **9**, 3, 4, 5, 6 — `TYPE_COOP` sits on 9, not 2.

          Correspondence with `LOBBIES.md`'s lobby **subtypes** is close but not identity, and is
          deliberately not asserted as one: 1 / 3 / 4 / 5 line up, 7 and 8 share a string group
          exactly as Basic and Combat Training share a menu scan, and 2 resolves out of the same
          `0x00F914BF` resource that holds the Lobby Select labels. But that file has 6 routed to a
          fallback and 9 out of range entirely, while both have labels here. Treat this as the
          history screen's own game-type enum until something ties the two axes together.

          **Why the earlier fingerprint saw nothing.** The 2026-07-23 test sent `40 + row`, i.e.
          41..45 — every one of them above 9, so every row took the default arm and printed a
          space. Nomad's 0 does the same. The negative was real; the range was simply outside the
          table. Release-day note: values 3-6 name post-launch lobby families, so only 1, 2, 7, 8
          and 9 are candidates for anything we send now.
