meta:
  id: mgo2_cmd_4582_s2c
  title: "MGO2 0x4582 — bulk roster entries (server -> client)"
  endian: be
doc: |
  Item packets of the 0x4580 roster triple (0x4581 start / N x 0x4582 / 0x4583 end). Parser
  0xD467C0 (ends 0xD469BC), dispatcher stub 0xD39350. PROTOCOL.md records 59-byte records with
  "only id and name of known meaning"; the ELF confirms the widths and the order.

  **THE TAIL IS A LOCATION BLOCK — NAMED 2026-07-31 (batch 3b).** The last five fields are
  `{lobby_id, lobby_name, game_id, game_name, lobby_type}` — where the player currently is. Every
  one has a renderer; see each field. The evidence stack, weakest to strongest:

    1. **The renderers.** The friend list paints `lobby_name` into a column the layout literally
       names `STRING_F_LIST_LOBBY` (0xE128A8), and the selected-row detail panel paints
       `game_name` and the decoded `lobby_type`.
    2. **The action call.** `0x8F6D78`-`0x8F6D88` loads SIX row fields in one breath and hands them
       to `0x9351AC(kind=23, chara_id, name, game_id, game_name, lobby_id, lobby_type)` — the
       per-player action popup. `0x90D6F8`-`0x90D710` makes the *same* call from the 0x4602 search
       screen with `kind=31`. The argument slots are the proof that these five bytes are one block.
    3. **Struct-shape bijection with 0x4b54.** The clan roster's tail is the same quintuple in the
       same order and the same widths — `lobby_id` u2, `lobby_name` 16B, `game_id` u4, `game_name`
       16B, `location_kind` u1 (see mgo2_cmd_4b54_s2c.ksy, named 2026-07-30). Not just the shape:
       the *consumer code* matches instruction for instruction. `0x4b54`'s `0xAC8864` tests
       `location_kind == 1 || == 8`, then requires `game_id != 0`, then `0xD4908C(session) == 0`,
       then offers `GetString(hash("lobby"), 996)` = **"Move to Game"**. `0x9355D4`-`0x935600`,
       reached from *this* record, is the identical sequence on `+0xA0` / `+0x88` of the popup
       object. And `0x4b54`'s `lobby_id` proof (`0xAC7CD4` -> `0xD47CE0` -> `0x27EF90(25)` /
       RecordSet key 254) reappears verbatim at `0x936384`-`0x9363AC`.

  This CONFIRMS the reading `SocialGameController` flagged as unproven, and REFUTES the older
  "likely clan name" reading and Nomad's "u16 36 = level/rank" guess. Nothing here is a rank.

  LOOP STRUCTURE. Records back to back with NO per-packet count: a 68-byte stack scratch is
  zeroed (memset r5=68, 0xD4685C), then the loop test 0xD5CEB0 (0xD46868) compares the read
  cursor against the payload length, the seven fields are read, the scratch is memcpy'd into the
  array (stride 68, mulli at 0xD46958) and the count incremented; back-edge at 0xD4697C. The
  client's table caps at 32 entries (cmpwi 31 / bail at 0xD46950) — note this is NOT the 100 of
  the otherwise byte-identical 0x4602 search record.

  WIRE 59 BYTES, CLIENT STRUCT 68. The three 16-byte strings are read with 0xD5D018, which
  NUL-terminates at dest[16], and the u16/u32 after each are re-aligned, so struct offsets drift
  ahead of wire offsets: struct 0/4/22/24/44/48/65 for wire 0/4/20/22/38/42/58.

  **TWO ROSTERS SHARE THIS RECORD — the Friend List and the Black List.** `0xD33508(session,
  listId, which)` is the only address computation for these arrays: `session + 0x10000 +
  listId*2184 + (which ? -23596 : -27964)`, `listId` restricted to {0, 1}. `listId` comes from the
  byte at `session+0x10000-27968`, which the 0x4580 *sender* `0xD4628C` writes (thunks 0xD463A8
  list 0, 0xD463A0 list 1). Naming from the UI layouts: list 0 is `l_shib_y02_03_bg_friend_list`
  (columns `STRING_F_LIST_NAME` / `STRING_F_LIST_LOBBY`), list 1 is
  `l_shib_y02_04_bg_black_list` (columns `STRING_B_LIST_NAME` / `STRING_B_LIST_HOST`).

  **The Black List reads only `chara_id`, `name`, `lobby_id`, `lobby_type` and `lobby_name`.** Its
  action call `0x8F8AA0` is `0x9351AC(kind=9, chara_id, name, 0, 0, 0, 0)` — `game_id`,
  `game_name`, `lobby_id` and `lobby_type` are hardcoded zero at the call site, and there is **no
  load at displacement 44 or 48 anywhere in the Black List module** (0x8F7660-0x8F8F00, TOC
  0xFEFEE8, `l_shib_y02_04_bg_black_list`). Column caption note: the Black List's layout calls the
  `lobby_name` column `STRING_B_LIST_HOST`, the Friend List calls the same bytes
  `STRING_F_LIST_LOBBY`. Same field, two captions — the value is the lobby (the 0x4b54 bijection
  and the lobby-type enum both say so), so the `..._HOST` name is a layout misnomer, not a second
  meaning.

  **THE 0x4583 FILTER IS REAL AND INERT — correction 2026-07-31.** The end handler
  (0xD465D4-0xD46788) does compact: it walks list(x, **0**) and copies only rows whose u16 at
  struct+0x16 is non-zero into list(x, **-1**) (test `lhz r0,30(r9)` at 0xD466D4 — r9 is
  `listBase + i*68`, rows start at `listBase+8`, so the displacement is row+22). **But nothing in
  the image ever reads list(x, -1).** All access to these arrays goes through `0xD463B0`
  (get list), `0xD4643C` (get row) and `0xD46518` (get count), each reachable only via four fixed
  `{listId, which}` thunks; the six `which = -1` thunks — 0xD46418, 0xD46430, 0xD464E8, 0xD46508,
  0xD465B0, 0xD465C8 — have **zero `bl` sites in the whole text section**, and their OPD
  descriptors (0x10297A8, 0x10297B8, 0x10297D0, 0x10297E0, 0x10297F8, 0x1029808) occur exactly
  once each in the file, as the descriptor itself, with no reference anywhere. `ET_EXEC`
  (`e_type == 2`), so there are no relocations to hide one. The UI reads list(x, 0), whose count
  and rows the compaction does not touch — 0x4583 only clears the "loading" word at +0 on both.

  So PROTOCOL.md's *"Serving zeros there yields an empty roster"* is **wrong**: the drop happens
  into a buffer with no reader. (PROTOCOL.md's own caveat applies — that line is tagged "Traced
  from the ELF 2026-07-26, single-source, none confirmed by a capture".) The `0x4583` / `0x4603`
  asymmetry is still a real code difference; it is just not a behavioural one.
doc-ref: dev/docs/PROTOCOL.md "0x4580 — bulk roster fetch (answered empty)"
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: |
      [ELF 0xD46868] Records until the payload ends. Split across packets freely — the parser resumes from the
      cursor and the client keeps the running count itself.
types:
  entry:
    doc: "59 bytes on the wire, 68 in the client struct."
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED by PROTOCOL.md] character id -> struct+0x00. [ELF 0xD46880]"
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED by PROTOCOL.md] character name, NUL-padded -> struct+0x04. [ELF 0xD468A0]"
      - id: lobby_id
        type: u2
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x16, read at 0xD468BC. **The id of the lobby this player
          is currently in.** Same field, same width, same position-in-block as `0x4b54`'s
          `lobby_id`; see the top-level doc for the bijection.

          Two roles, both tier 1:

          * **Gate on `lobby_name`.** Friend-list row painter 0x8F611C: `lhz r0,22(r11)` at
            0x8F6164, zero branches to 0x8F6190 which substitutes `GetString(hash("lobby"), 18)` =
            **`"----"`**. Black-list row painter 0x8F8534 does the same at 0x8F85A8. (`"----"` is
            disc set `[2f0293]`, group 0xF914BF = `"lobby"`, string id 18 — validated against the
            known-good id 996 = "Move to Game" and id 3 = a single space.)
          * **Dialled as a real lobby id.** 0x8F6D84 `lhz r8,22(r11)` is argument 6 of
            `0x9351AC`, which parks it at popupObj+0x9E. From there 0x935B04 passes it to
            `0x884300` (lobby-table lookup) and 0x936384 passes it to `0xD47CE0(session, id)`,
            whose result goes into the client's own property store via `0x27EF90(25)` +
            RecordSet(key 254, len 2) at 0x93639C-0x9363AC. That is instruction-for-instruction
            what `0x4b54`'s `lobby_id` does at 0xAC7CD4-0xAC7D04.

          **A fabricated non-zero value is therefore not neutral** — it will be looked up. The
          server has sent a hardcoded `1` here since 2026-07-26 on the theory that zero would
          empty the roster; that theory is refuted above (the 0x4583 drop targets a dead buffer),
          so zero is safe and `1` is a live lobby id being handed to the jump path. Not changed
          here — this is a schema, not the server.

          NOT level/rank. Nomad's tier-4 test payload put 36 here and PROTOCOL.md recorded the
          guess; nothing reads this value as a number anywhere.
      - id: lobby_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x18, read at 0xD468DC. **The display name of the lobby
          `lobby_id` points at.**

          Rendered as a list column on both roster screens, gated by `lobby_id != 0` **and**
          `lobby_type != 0`:

          * Friend list, 0x8F6174: `addi r4,r29,24` — the address of this field — then
            `0x87C738` (the display-text converter, which stages into a 3073-byte rotating bank)
            and `0x94AD8C` appends it to the column widget at `screen+0xC0000+6952`. That widget
            is configured eight times over at 0x8F5AE8ff with the element-name pair
            `STRING_F_LIST_LOBBY` / `STRING_F_LIST_LOBBY-1` (module TOC 0xFEFE38, slots -32700 /
            -32696). **The column is named LOBBY in the layout.** Its sibling column
            `STRING_F_LIST_NAME` takes `name`.
          * Black list, 0x8F85C0: identical four instructions into the widget at
            `screen+0xC0000+6872`, configured at 0x8F7E48 with `STRING_B_LIST_HOST` (TOC 0xFEFEE8
            slot -32712). See the top-level doc on that caption.

          Either gate zero substitutes `"----"`. Serve a NUL-terminated name whenever `lobby_id` is
          non-zero; the client fills the slot itself otherwise and never looks at these bytes.
      - id: game_id
        type: u4
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x2C, read at 0xD468F8. **The id of the game this player
          is currently in**, second of the record's two `{id, name}` location pairs.

          * **Gate on `game_name`.** Friend-list detail panel 0x8F62B4: `lwz r0,44(r9)`, zero
            branches to 0x8F62F8 and writes `"----"` (`GetString(hash("lobby"), 18)`) instead of
            the name. Second site 0x8F6F04, same shape.
          * **It is the "Move to Game" switch.** 0x8F6D80 `lwz r6,44(r11)` is argument 4 of
            `0x9351AC` and lands at popupObj+0x88. At 0x9355E8 the popup's menu builder requires
            `lobby_type` ∈ {1, 8} *and* `game_id != 0` *and* `0xD4908C(session) == 0` before the
            entry appears. `0x4b54`'s `game_id` is gated by the byte-identical test at 0xAC8864 /
            0xAC89B0, and there the menu label is resolved as `GetString(hash("lobby"), 996)` =
            **"Move to Game"**. That is the anchor for the name.

          **A non-zero value here is not neutral** — it offers the player a jump that the server
          must be able to honour. Not "in-game flag": it is an id, tested against zero.
      - id: game_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x30, read at 0xD46918. **The display name of the game
          `game_id` points at.**

          Read at 0x8F62DC (`addi r4,r26,48`, `li r5,32`, `0xAF70F0` bounded copy into the 33-byte
          buffer at `screen+0x180000+13717`) and again at 0x8F6F2C. The buffer becomes the text of
          the element named `STRING_ST1_ON` / `STRING_ST1_ON_SD` (module TOC 0xFEFE38, slots
          -32632 / -32628) at `screen+0x180000+13672` — the **selected-row status line**, not a
          list column. `game_id == 0` puts `"----"` there instead.

          Also carried out of the row at 0x8F6D68 (`addi r7,r5,0x30`) as argument 5 of `0x9351AC`,
          strcpy'd to popupObj+0x8C at 0x9352D4 — but only when the pointer is non-null.

          The 32 at 0x8F62E8 is `0xAF70F0`'s copy bound, not a field width. **Do not widen the
          field on the strength of it** — same trap as `0x4b54`'s 34.

          Unlike 0x4602, no roster screen puts this in a list column, and the Black List never
          reads it at all.
      - id: lobby_type
        type: u1
        doc: |
          [ELF — NAMED 2026-07-31] struct+0x41, last byte of the record, read at 0xD46934.
          **A small enum naming the CATEGORY of the lobby the player is in**, and the second gate
          on `lobby_name`.

          `0x8E1110(code)` decodes it. It is `code - 1` into an 8-arm jump table (bound
          `cmplwi 7` at 0x8E1128, table 0x8E114C off module TOC 0xFEFA40), each arm doing
          `GetString(hash("lobby"), N)`:

          | value | string id | text |
          | --- | --- | --- |
          | 1 | 245 | `Free Battle` |
          | 2 | 251 | `Automatching` |
          | 3 | 246 | `Tournament` |
          | 4 | 248 | `Survival` |
          | 5, 6 | 247 | `Official Tournament` |
          | 7, 8 | 249 | `Training` |
          | 0 or > 8 | 18 | `----` (the default arm, 0x8E11B4) |

          Readers of THIS record: 0x8F6170 (friend-list row painter — non-zero required or the
          `lobby_name` column shows `"----"`), 0x8F85B4 (black-list row painter, same gate),
          0x8F646C and 0x8F70BC (friend-list detail panels — the value goes through `0x8E1110` and
          becomes the text of the element at `screen+0x180000+13676`), and 0x8F6D78 as argument 7
          of `0x9351AC` -> popupObj+0xA0. Downstream of the popup: 0x936294/0x9362A8 compare it
          against the type of the lobby the viewer is already in (`0x883F20()->[0x294]`), and
          0x9355D8/0x9355E0 admit **only 1 and 8** to the "Move to Game" arm — Free Battle and
          Training, the two categories that host joinable games. `0x4b54` calls the same byte
          `location_kind` and has the same `cmpwi 1` / `cmpwi 8` pair at 0xAC8864; **this table
          decodes that field too.**

          Not a lobby id. PROTOCOL.md's tier-4 note ("u8 4 = lobby id?") had the right
          neighbourhood and the wrong quantity; value 4 is Survival, which is post-launch content
          (see POST_LAUNCH.md) and should never be served by a release-day server.
