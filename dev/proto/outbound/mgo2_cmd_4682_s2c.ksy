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
          | 2 | `0x91e650` | `GetString(0x00F914BF, 0x00A6FC6D)` = **"Automatching"** |
          | 3 | `0x91e61c` | `TYPE_TOURNAMENT` |
          | 4 | `0x91e624` | `TYPE_SURVIVAL` |
          | 5 | `0x91e62c` | `TYPE_TOURNAMENT_OFFICIAL` |
          | 6 | `0x91e634` | `TYPE_SURVIVAL_OFFICIAL` |
          | 7 | `0x91e664` | `GetString(0x00654515, 0x0083889F)` = **"Training"** |
          | 8 | `0x91e678` | `GetString(0x00654515, 0x0077B743)` = **"Combat Training"** |
          | 9 | `0x91e614` | `TYPE_COOP` |
          | 0, or >9 | `0x91e5e8` | the single-space string at `-32760(r30)` — column blank |

          **The three literal-hash arms, decoded off the disc [2026-07-31].** Method is
          `AUTOMATCH.md` §10 (`lobby/scenerio.gcx`, `gcx.exe -res`); the group hash in each
          `GetString` call is the header's `groupHash` field verbatim, so the record is found by
          scanning headers rather than guessing.

          - **Value 2** — group `0x00F914BF` = `hash("lobby")`, set `[2f0293]` headers
            `$strres:9789`-`11033`, string base **11034**. Name hash `0xA6FC6D` is header
            **10695**, i.e. **string id 906**, EN ordinal `0x477` → file `12176` = `"Automatching"`
            (JP `オートマッチング`). Base validated three ways before trusting it: id 996 → EN
            `"Move to Game"`, id 3 → a single space, id 18 → `"----"`, all byte-identical to what
            batch 3b recorded. And **id 906 is independently already in `AUTOMATCH.md` §9** as
            "Automatching", written down before this arm was known — the two agree without either
            being derived from the other.
          - **Values 7 and 8** — group `0x00654515` is a *different* group: set `[40eff4]`, headers
            `$strres:0`-`341`, string base **342**. Name hash `0x83889F` is header **18**
            (string id 18) → EN file `408` = `"Training"`; `0x77B743` is header **20** (string id
            20) → EN file `415` = `"Combat Training"`.
          - **Base 342 is locked by the language column, not by eyeballing.** Each header carries
            six ordinals in order JP, EN, FR, DE, IT, ES. Reading the *second* ordinal at bases
            341 / 342 / 343 yields Japanese / English / French respectively — only 342 puts the EN
            slot on English. Contents then self-validate: headers 0-17 are nine *identical adjacent
            pairs* naming the ten rules in order (Deathmatch, Team Deathmatch, Rescue, Capture,
            Sneaking, Base, BOMB, Team Sneaking, Coop) with Training/Combat Training at 18-21, and
            headers 22-43 repeat that same order as `DM TDM RES CAP SNE BASE BOMB TSNE COOP TRA CT`
            then `DM TD RE CA SN BA BM TS CO TR CT`. An off-by-N breaks the pairing and the two
            abbreviation runs stop lining up with the name run. (The trap this guards against is
            real: in set `[e60831]` the strings start at 17943 while twelve later headers belong to
            other sub-groups.)

          The six `TYPE_*` pointers are the contiguous array at **`0xFE85F0`** (module TOC
          `r30 = 0xFF05E0`, offsets `-32752`..`-32732`), the one `LOBBIES.md` describes as
          "reached through a base register loaded from the TOC, so nothing in the image points at
          it directly". This is the code that reaches it, and **it settles that file's open
          question in the negative: the mapping is NOT `index = subtype - 1`.** Array order is
          FREEBATTLE, COOP, TOURNAMENT, SURVIVAL, TOURNAMENT_OFFICIAL, SURVIVAL_OFFICIAL but the
          values are 1, **9**, 3, 4, 5, 6 — `TYPE_COOP` sits on 9, not 2.

          **Correspondence with `LOBBIES.md`'s lobby subtypes: CORROBORATED at every value both
          axes define [2026-07-31].** The three decoded labels were the weak points, and all three
          land on the subtype of the same number:

          | value | this table's label | subtype | that subtype's own menu string |
          | --- | --- | --- | --- |
          | 1 | `TYPE_FREEBATTLE` | 1 | id 245 = `"Free Battle"` |
          | 2 | **"Automatching"** (id 906) | 2 | id 251 = `"Automatching"`, title id 904 `"AUTO MATCHING LOBBY"` |
          | 3 | `TYPE_TOURNAMENT` | 3 | tournament/survival family |
          | 4 | `TYPE_SURVIVAL` | 4 | tournament/survival family |
          | 5 | `TYPE_TOURNAMENT_OFFICIAL` | 5 | title reads "OFFICIAL CUP LOBBY" |
          | 7 | **"Training"** | 7 | id 249 = `"Training"`, title id 842 `"TRAINING LOBBY"` |
          | 8 | **"Combat Training"** | 8 | shares 7's row; separated only inside the lobby |

          Note the ids in the right-hand column come from the *other* resource group
          (`0x00F914BF`, the Lobby Select labels) and were recorded before this table was decoded,
          so the agreement is between two independently-derived readings, not one restated.

          This is still **not** proof of a single enum — nothing in the binary says the two axes
          share a numbering, and they are not co-extensive: this table has 6 (`SURVIVAL_OFFICIAL`)
          and 9 (`TYPE_COOP`) where `LOBBIES.md` has 6 routed to a fallback title and 9 out of
          range entirely. Both of those are post-launch content we never serve, so the disagreement
          is outside the domain we emit. `SocialGameController.gameTypeLabel`'s policy of serving
          `lobby.subtype` here is corroborated over {1, 2, 7, 8} — every value we can actually
          produce — and would be refuted by a label mismatch at one of those four. There is none.

          The one wording correction: subtype 7's name in `LOBBIES.md` was **"Basic Training"**,
          which is nobody's string. The game's own word for the lobby is **"Training"**; the string
          `"Basic Training"` does not occur anywhere in the `lobby` stage's 28693 string resources.
          "Basic" survives only as the informal contrast with Combat Training — the two activities
          the disc actually names inside the lobby are `"Solo Training"` and `"Novice Training"`.

          **Why the earlier fingerprint saw nothing.** The 2026-07-23 test sent `40 + row`, i.e.
          41..45 — every one of them above 9, so every row took the default arm and printed a
          space. Nomad's 0 does the same. The negative was real; the range was simply outside the
          table. Release-day note: values 3-6 name post-launch lobby families, so only 1, 2, 7, 8
          and 9 are candidates for anything we send now.
