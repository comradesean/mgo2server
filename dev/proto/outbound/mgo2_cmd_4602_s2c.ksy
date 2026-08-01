meta:
  id: mgo2_cmd_4602_s2c
  title: "MGO2 0x4602 — player-search result records (server -> client)"
  endian: be
doc: |
  Item packets of the 0x4600 player-search triple (0x4601 start / N x 0x4602 / 0x4603 end).
  Parser 0xD45F38 (ends 0xD46124), dispatcher stub 0xD39380. PROTOCOL.md documents 59-byte
  records, client table capped at 100; the ELF confirms both.

  **THE TAIL IS A LOCATION BLOCK — NAMED 2026-07-31 (batch 3b).** The last five fields are
  `{lobby_id, lobby_name, game_id, game_name, lobby_type}`. **This CONFIRMS the reading
  `SocialGameController` recorded as an unproven tier-4 candidate** — "current lobby name /
  current game name / lobby id" — with two corrections: the u16 is the lobby **id** (not
  level/rank, refuting Nomad's `36`), and the trailing u8 is a lobby **category enum**, not a
  lobby id. The three fields the server deliberately sends as zero can now be filled with real
  data; see each field for what a non-zero value costs.

  Evidence is in mgo2_cmd_4582_s2c.ksy — it is the same record and the two flows were worked
  together. In brief: the renderers name the fields, `0x9351AC` takes six of them as one
  argument list, and the whole quintuple is a struct-shape *and* consumer-code bijection with
  `0x4b54`'s `lobby_id` / `lobby_name` / `game_id` / `game_name` / `location_kind`.

  LOOP STRUCTURE. No per-packet count: 68-byte scratch zeroed (memset r5=68 at 0xD45FC4), loop
  test 0xD5CEB0 at 0xD45FD0 (cursor < payload length), seven field reads, memcpy into the array
  at stride 68 (mulli at 0xD460C0), count++ , back-edge at 0xD460E4. Cap check `cmpwi r3,99`
  at 0xD460B8 → 100 entries, then bail.

  WIRE 59 BYTES, CLIENT STRUCT 68 — the three 16-byte strings NUL-terminate at dest[16] and the
  following scalars re-align, so struct offsets run ahead of wire offsets: struct
  0/4/22/24/44/48/65 for wire 0/4/20/22/38/42/58.

  **THE SCREEN.** One array only: `*(session+0x10000+6404) + 0x20000 - 29952`, rows at `+8`,
  count at `+4`, "loading" word at `+0`. Accessors `0xD473B8` (count) and `0xD473F4` (row i,
  `mulli r9,r4,68` at 0xD4742C). **`0xD473F4` has exactly ONE `bl` site in the whole text
  section — 0x90EA04** — so the provenance of every read of a search row is closed by
  construction, no band sweep required. That call is inside the results builder at
  0x90E9F4-0x90EBDC, a state of the machine at 0x90DE0C (state 11, jump table 0x90DE9C). The
  screen is the player search: 0x90EC60 plays the layout animation `search_on` (hash 0x00DBCB78,
  in `dev/tools/gcx/dictionary.txt`), and its list-preference nibbles come from `0x906C90` /
  `0x906C9C`, the accessors ADDRESSES.md §8 already ties to the PLAYER SEARCH screen.

  Rows are drawn as **three columns** (`0x94AD8C` appends at 0x90EA70, 0x90EAC0, 0x90EB44, into
  widgets at `ctx+136`, `ctx+0xC0000+6772`, `ctx+0x180000+13408` — uniform stride
  `0xC0000+6636`): `name`, then `lobby_name`, then `game_name`. Both gated columns fall back to
  `GetString(hash("lobby"), 18)` = `"----"`. The screen's constructor 0x90D1C0 sets four static
  captions by element hash — 0x00A9E396 = **NAME** (string 42), 0x008E5E53 = **LOBBY** (29),
  0x00375B97 = **GAME TYPE** (12), 0x00B17B95 = **HOST NAME** (16) — one more caption than there
  are columns, and the four element names resolve nowhere in the ELF or in the lobby `.dar`, so
  the caption-to-column binding is NOT established here. The field identities do not rest on it.

  Every parsed row is also cached into six parallel per-row arrays (0x90EB4C-0x90EBD0, memsets at
  0x90E920-0x90E9A8), base `ctx + 36<<16`: `+20044` chara_id u32, `+24044` name ptr,
  `+28044` lobby_id u16, `+30044` game_id u32, `+34044` game_name ptr, `+38044` lobby_type u8.
  0x90D6F8-0x90D710 reads all six back and calls `0x9351AC(kind=31, chara_id, name, game_id,
  game_name, lobby_id, lobby_type)` — the same per-player action popup the friend list opens with
  `kind=23`. That shared call is the strongest single piece of evidence that these five bytes are
  one location block.

  **DIVERGENCES FROM 0x4582 — the two are NOT interchangeable.** Tracked, not assumed:

    1. Table cap **100** here (`cmpwi r3,99`, 0xD460B8) vs **32** there (`cmpwi 31`, 0xD46950).
    2. **One array here; four there.** 0x4582 writes `session+0x10000 + listId*2184 + (which ?
       -23596 : -27964)` with `listId` ∈ {0, 1} (Friend List / Black List) and two buffers each.
       That is *why* `0x4583` has a compaction pass and `0x4603` (0xD45D30) does not — there is no
       second buffer here to compact into. New in batch 3b: the 0x4582 compaction's destination
       has **no reader anywhere in the image**, so the asymmetry is real in code and inert in
       behaviour. Full proof in mgo2_cmd_4582_s2c.ksy.
    3. `game_name` is a **list column** here; on the 0x4582 screens it appears only in the
       selected-row status line, and the Black List never reads it at all.
    4. `0x4603` requires the "loading" word non-zero and stores its own u32 result into it
       (0xD45DC8), completing wait slot 0x53. `0x4583` clears the word on two arrays and runs the
       compaction.

  Same layout, four different behaviours. Keep testing for more before ever calling them mirrors.
doc-ref: dev/docs/PROTOCOL.md "0x4600 — player search"
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF 0xD45FD0] Records until the payload ends; may be split across 0x4602 packets freely."
types:
  entry:
    doc: "59 bytes on the wire, 68 in the client struct."
    seq:
      - id: chara_id
        type: u4
        doc: |
          [CONFIRMED by PROTOCOL.md] character id → struct+0x00. [ELF 0xD45FE8]

          Also the **row-occupied test**: 0x90EA1C `lwz r0,0(r3); cmpwi 0; beq` skips the row
          entirely, and 0x93524C-0x93527C refuses to open the action popup (error dialog 0x1036)
          when it or `name` is zero.
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED by PROTOCOL.md] character name, NUL-padded → struct+0x04. [ELF 0xD46008] Column 1, copied at 0x90EA58."
      - id: lobby_id
        type: u2
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x16, read at 0xD46024. **The id of the lobby this
          player is currently in.**

          * **Gate on `lobby_name`.** 0x90EA78 `lhz r0,22(r31); cmpwi 0; beq 0x90EAA0` → the
            column gets `GetString(hash("lobby"), 18)` = `"----"` instead. (Disc set `[2f0293]`,
            group 0xF914BF = `"lobby"`, id 18; anchored against the known-good id 996 =
            "Move to Game".)
          * **Dialled as a real lobby id.** Cached at 0x90EBA4 into the `+28044` u16 array, read
            back at 0x90D70C as argument 6 of `0x9351AC`, parked at popupObj+0x9E, and from there
            handed to `0x884300` (0x935B04) and to `0xD47CE0(session, id)` (0x936384) whose result
            is written to the client's property store — `0x27EF90(25)` + RecordSet key 254, len 2
            at 0x93639C-0x9363AC. `0x4b54`'s `lobby_id` does exactly this at 0xAC7CD4-0xAC7D04.

          **Not level/rank.** PROTOCOL.md's tier-4 candidate came from Nomad's `search-player.bin`
          putting 36 here; no site in the image renders this value as a number. Correspondingly, a
          fabricated non-zero id is not neutral — it is looked up in the lobby table.
      - id: lobby_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x18, read at 0xD46044. **The display name of the lobby
          `lobby_id` points at** — column 2 of the results list.

          0x90EA88 `addi r4,r31,24` is the address of this field; it becomes the appended text
          only when `lobby_id != 0` (0x90EA78) **and** `lobby_type != 0` (0x90EA84). Either gate
          zero takes 0x90EAA0 and the row shows `"----"`.

          The name is fixed by the twin flow rather than by this screen's captions: 0x4582 paints
          the same bytes into a friend-list column the layout names `STRING_F_LIST_LOBBY`
          (0xE128A8), and the byte after it decodes to lobby-category names. Serve a
          NUL-terminated name whenever `lobby_id` is non-zero.
      - id: game_id
        type: u4
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x2C, read at 0xD46060. **The id of the game this player
          is currently in.**

          * **Gate on `game_name`.** 0x90EAC8 `lwz r0,44(r31); cmpwi 0; beq 0x90EB0C` → column 3
            gets `"----"`. The detail painter repeats it at 0x90DC34 / 0x90DD70 off the `+30044`
            cache.
          * **The "Move to Game" switch.** Cached at 0x90EBB4, read at 0x90D6F8 as argument 4 of
            `0x9351AC` → popupObj+0x88, where 0x9355E8 requires it non-zero (after `lobby_type` ∈
            {1, 8}) before the menu entry is built. `0x4b54` gates the same entry the same way at
            0xAC89B0 and resolves its label as `GetString(hash("lobby"), 996)` = **"Move to
            Game"**.

          **Not an "in-game flag"** — PROTOCOL.md's tier-4 candidate. It is an id that is only ever
          compared against zero *on this screen*; the popup hands it on.
      - id: game_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x30, read at 0xD46080. **The display name of the game
          `game_id` points at** — column 3 of the results list.

          0x90EAF0 `addi r5,r28,48` into a 33-byte scratch via `0x23E3F0(dst, 32, src)`, appended
          at 0x90EB44; `game_id == 0` instead strcpy's `"----"` (0x90EB0C-0x90EB24). The pointer is
          cached at 0x90EBB8 into the `+34044` array and re-read at 0x90D700 as argument 5 of
          `0x9351AC` (strcpy'd to popupObj+0x8C at 0x9352D4). The detail painter sets the element
          named by hash 0x00078D1F from a per-row 792-byte buffer at `ctx+0x180000+0x3460`, again
          `"----"` when `game_id` is zero (0x90DC4C, 0x90DD88).

          The `li r4,32` at 0x90EAFC is the copy bound, **not** a field width — do not widen the
          field on the strength of it.
      - id: lobby_type
        type: u1
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x41, last byte, read at 0xD4609C. **A small enum naming
          the CATEGORY of the lobby the player is in**, and the second gate on `lobby_name`.

          `0x8E1110(code)` decodes it — `code - 1` into an 8-arm jump table (bound `cmplwi 7` at
          0x8E1128, table 0x8E114C off module TOC 0xFEFA40), each arm calling
          `GetString(hash("lobby"), N)`:

          | value | string id | text |
          | --- | --- | --- |
          | 1 | 245 | `Free Battle` |
          | 2 | 251 | `Automatching` |
          | 3 | 246 | `Tournament` |
          | 4 | 248 | `Survival` |
          | 5, 6 | 247 | `Official Tournament` |
          | 7, 8 | 249 | `Training` |
          | 0 or > 8 | 18 | `----` (default arm 0x8E11B4) |

          Readers: 0x90EA84 (gates the `lobby_name` column), 0x90EBBC (cached into the `+38044`
          array), 0x90DBD4 and 0x90DD10 (`lbz r3,0xc(r9)` off that array → `0x8E1110` → text of
          the element with hash 0x0007BDDB in the two detail painters), and 0x90D704 as argument 7
          of `0x9351AC` → popupObj+0xA0. In the popup, 0x936294/0x9362A8 compare it against the
          viewer's own lobby type (`0x883F20()->[0x294]`) and 0x9355D8/0x9355E0 admit **only 1 and
          8** — Free Battle and Training — to the "Move to Game" arm. `0x4b54`'s `location_kind`
          is the same byte with the same `cmpwi 1` / `cmpwi 8` test at 0xAC8864; **this table
          decodes that field too.**

          Not a lobby id — PROTOCOL.md's tier-4 note ("u8 4 = lobby id?") had the block right and
          the quantity wrong. Release-day note: values 3, 4 and 5/6 name Tournament, Survival and
          Official Tournament, all post-launch content (POST_LAUNCH.md); a release-day server
          should only ever emit 1, 2 or 7/8.
