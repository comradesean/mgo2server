meta:
  id: mgo2_cmd_43f0_s2c
  title: "MGO2 0x43f0 — server -> client: server-assigned team rosters for the tournament/survival lobby family"
  endian: be
doc: |
  **What it is (settled 2026-08-02).** `0x43F0` carries the **same lobby-identity header as
  `0x43F1`** — byte for byte, onto the same five destination slots — plus a two-value series
  counter and **two eight-entry lists of character ids**. The client uses those lists to set each
  player's **team** as they are added to the in-game roster. It is the server's way of saying
  *"these eight players are team 0, those eight are team 1"*, instead of letting the client's own
  auto-balancer decide.

  It is a **tournament/survival-family packet** (lobby subtypes 3-6). The consuming code is gated
  behind a game-object flag bit that is only ever set for those subtypes; see "Why we do not send
  it" below.

  ## The destination record, and why the header names transfer

  The parser stores into `R = 0xD3F7B0(ctx)` = **`session + 0x11558`**, the shared
  last-notification record. `0x43F1`'s parser (`0xD5B664`) uses **the same accessor** and writes
  **the same five offsets with the same widths**:

  | wire (this packet) | -> R | `0x43F1` wire | `0x43F1` field |
  | --- | --- | --- | --- |
  | `0x00` u4 | `R+4`  | `0x04` u4 | `lobby_id` |
  | `0x04` u1 | `R+8`  | `0x08` u1 | `lobby_subtype` |
  | `0x05` u1 | `R+9`  | `0x09` u1 | `lobby_subtype_sibling` |
  | `0x06` u4 | `R+12` | `0x0a` u4 | `zero_0a` |
  | `0x0a` u4 | `R+16` | `0x0e` u4 | `zero_0e` |

  That is a **struct-offset bijection**, not an analogy: same base accessor, same offsets, same
  widths, in the same order. The names are `0x43F1`'s and they transfer. (`0x49a2`, `0x4950`,
  `0x4960`, `0x4918`/`0x4919`/`0x491c`, `0x4a00`/`0x4a01`, `0x4a12`, `0x4a20`, `0x4a28`/`0x4a29`
  and `0x4e10` write the same five slots from their own sources — this is the protocol's shared
  "which lobby/session is this about" header, not a coincidence of layout.)

  ## The two arrays are team rosters. Proof.

  The single live reader is **`0x270CA4`-`0x270DA4`**, inside the routine that installs a player
  into an in-game roster slot (`0x2705A8`, 24 slots at `game+212`, stride 116):

  ```
  270ca4  bl 0x2810e0                 ; session base
  270cb4  bl 0xd3f7b0                 ; r26 = R
  270cd8  lwz r3,22488(r20)           ; session+0x57D8 +0 = MY CHARACTER ID (0x4101 wire 0x00)
  270cdc  lwz r0,44(r26)   == r3 ? -> 0x270f4c   ; li r0,0 ; stb r0,1(r28)
  270ce8  lwz r0,100(r26)  == r3 ? -> 0x270d9c   ; li r0,1 ; stb r0,1(r28)
  ...     the same pair for +48/+104, +52/+108 ... +72/+128   (all 8 of each)
  ```

  `entry+1` is the roster entry's **team byte**, already mapped independently: it is
  character-record **field 1**, 0-based, `0xFE` = no team, published by `0x275FE0` and read by
  `0x4344` (raw) and `0x4440` (as `(v == 1) ? 2 : 1`). See `mgo2_cmd_4440_c2s.ksy`, which derives
  that field from its writers — the auto-balance picker `0x6EB4F0` and the `254` sentinel.

  So a hit in the **first** array assigns team **0**, a hit in the **second** assigns team **1**,
  and a player in neither keeps the default `stb r18,1(r28)` with `r18 = -1`, i.e. **255**. Eight
  entries each, matching the game's 16-player maximum split two ways.

  **~~Exactly one writer, exactly one reader~~ — CORRECTED 2026-08-03: `0x4A13`'s parser also
  writes both arrays** (`0xD450A4`-`0xD450D4`, `0xD45118`-`0xD45148`), so the arrays have two
  wire writers, and the original claim below overstated. Original text, kept for the reader
  census it carries: `R+44..R+75` and `R+100..R+131` are written only by
  this parser (every other `0xD3F7B0` caller in the image was enumerated) and read only at
  `0x270CDC`-`0x270D94`.

  ## Why we do not send it, and why that is correct

  The lookup runs only when the game object's flag word satisfies
  `(*(u32*)(game+3020) & 0x201) == 0x201` (`0x270698`-`0x2706A8`). **Bit 9 (`0x200`) is set at
  exactly one place**, `0x27272C`:

  ```
  272704  lbz r9,8(r31)               ; R+8 = lobby_subtype
  272708  addi r0,r9,-2 ; cmplwi 4 ; bgt -> skip     ; require subtype in 2..6
  272718  cmpwi r9,2 ; beq -> skip                   ; and NOT 2
  272728  ori r0,r0,1792 ; stw r0,3020(r9)           ; sets bits 8, 9, 10
  ```

  So the team lists are consulted **only for lobby subtypes 3, 4, 5 and 6** — the
  tournament/survival family (`LOBBIES.md`: 3/4/5 are the unnamed tournament/survival trio, 6 has
  no scan). **Automatching is subtype 2**, which is explicitly excluded, so on the lobby we deploy
  the client can never reach the code that reads these arrays. Not sending `0x43F0` is correct for
  what the server serves today; it is not a gap.

  Nor can its absence stall anything:

  - **No result field and no request slot.** The parser ends at `0xD33CD8(ctx, 43, 0)`, the
    fire-and-forget event helper, with a literal zero value. Nothing times out waiting for it.
  - **Event 43 is an explicit no-op.** The only handler for events 42-47 is the automatch screen's
    `0x93D6E0`; its jump table at `0x93D748` has six entries, and **entry 1 (event 43) is
    `0x93DE5C`, the function's own return** — the same target as the out-of-range `bgt`. It is a
    deliberate empty arm, not a missing one.
  - **Not polled either.** The pending-counter poller `0x33F8C`-family reads only ids `3`, `0x1C`,
    `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37`. `43` (`0x2B`) is not among
    them, so the callback table is the only route and that route returns immediately.

  **Not served in v1** (tournament/survival is post-launch content), and **tier 1 only** — no
  available client build exercises it, so nothing here can be confirmed against a capture.

  ## Parser evidence

  GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43F0` at `0xD38A28` ->
  stub `0xD39D5C` -> parser **`0xD5B868`**.

  Sequence: verify `hdr.command == 0x43F0` (else `-70`); `0xD3F7B0(ctx)` obtains `R`; `0xD5C844`
  open; read the five scalars into stack slots; `0xD418C0(ctx)`; commit them to `R+4`, `R+8`,
  `R+9`, `R+12`, `R+16`; then two `i < 8` u32 loops read directly into `R+44+4i` and `R+100+4i`;
  `0xD5C858` close; `0xD33CD8(ctx, 43, 0)`.

  **78 bytes (`0x4E`).** Note the id parity: `0x43F0` is *even*, and the even ids in this range are
  client->server elsewhere in the protocol; here the even number is on the server->client side,
  which is itself a signal that the `0x43Fx` block is a push channel rather than a request/reply
  family.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Enumerating every `bl 0xD33CD8` gives
  49 sites with 49 distinct ids, one per command parser, so the id says which command arrived and
  nothing about what is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md`
  "UI events: how 0xD33CD8 dispatches".

doc-ref: dev/docs/AUTOMATCH.md "§3 The packets"; dev/docs/LOBBIES.md "Lobby subtypes"
seq:
  - id: lobby_id
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_00`] wire `0x00` -> `R+4`.

      **Struct-offset bijection with `0x43F1` wire `0x04`** (`mgo2_cmd_43f1_s2c.ksy`,
      `lobby_id`): both parsers obtain the same base from `0xD3F7B0`, store a u32 at `+4`, and
      `0x49a2`'s parser fills the same slot from its record's `+604` alongside `+608`/`+609` as one
      straight-line block. Onward: `0x8F9BF8` copies `R+4` to the game object's `+656`, and
      `0x8BE084` copies it to another object's `+708`.

      Confidence: **name inherited by bijection, high**; no reader disambiguates it from any other
      per-session id on its own.
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_04`] wire `0x04` -> `R+8`. Same slot as `0x43F1` wire
      `0x08`.

      **This is the byte that gates the whole packet.** `0x272704` reads `R+8`, requires it in
      `2..6`, excludes `2`, and then sets bits 8/9/10 of `game+3020` — and bit 9 is the bit the
      team-roster lookup below tests. It is also stashed into record 0 key 141 at `0x272754`
      (`RecordSet(rec0, 141, 1)`), whose reader is `0x9BE5F0`.

      Corroborating onward path: `0x8F9BF0` copies `R+8` to game object `+660`; `0x8CA164` copies
      `+660` into the create-game argument block at `args+168`, which the `0x4310` builder emits —
      the same field `0x43F1`'s doc identifies as `0x4310` wire `0xA2`. Three-point chain, so the
      name is [CONFIRMED via bijection + onward path], not inherited on shape alone.
  - id: lobby_subtype_sibling
    type: u1
    doc: |
      [ELF 2026-08-02, renamed from `unknown_05`] wire `0x05` -> `R+9`. Same slot as `0x43F1` wire
      `0x09`.

      **Position and width exact; the meaning is contested and is settled, if at all, in
      `mgo2_cmd_43f1_s2c.ksy`.** No reader of `R+9` names it: `0x8F9C00` copies it to game object
      `+661` and `0x8BE094` to another object's `+713`, and neither destination has a consumer that
      branches on the value. The server's own `0x43F1` writer treats this byte as a **rule id**, on
      evidence taken from the *source* side of the `0x49xx` parsers (`team+0x261`, read as a rule
      at four `strres` sites) rather than from a reader of `R+9`. That argument does not
      automatically carry to this packet, whose source is a different record.

      Confidence: **[UNKNOWN] meaning, [ELF] slot.** Send whatever `0x43F1` sends for the same
      session if this packet is ever implemented.
  - id: series_total
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_06`] wire `0x06` -> `R+12`. Unaligned on the wire; the
      read primitives are bytewise, so alignment is irrelevant. Same slot as `0x43F1` wire `0x0a`,
      which `0x43F1`'s four sibling writers all zero.

      **It is a count, paired with `series_index` below.** The predicate function `0x6EAC48`
      returns 1 exactly when `R+12 - 1 == R+16`:

      ```
      6eac90  lbz r0,8(r31) ; cmpwi 3 / cmpwi 5 ; else return 0     ; only for subtypes 3 and 5
      6eacc0  lwz r9,12(r31) ; lwz r0,16(r31) ; addi r9,r9,-1
      6eaccc  cmpw r9,r0 ; beq -> return 1
      ```

      `0x6EBF80` runs the identical test before calling `0xC8D790`. So `+12` is a **total** and
      `+16` a **zero-based position within it** — the pair answers "is this the last one". What is
      being counted is **[UNKNOWN]**: nothing in the binary labels the unit, and the two readers are
      both in the in-game round manager (`0x6Exxxx`), the same neighbourhood as the auto-balancer
      `0x6EB4F0`. "Matches in a tournament series" fits the subtype gate but is not proven; the
      name here says only what the arithmetic says.

      **Consequence for `0x43F1`:** these slots are not inherently zero. `0x43F1` zeroing them is
      safe only because the reader is gated on subtype 3/5 and automatching is subtype 2.
  - id: series_index
    type: u4
    doc: |
      [ELF 2026-08-02, renamed from `unknown_0a`] wire `0x0a` -> `R+16`. Same slot as `0x43F1` wire
      `0x0e`. The zero-based position compared against `series_total - 1` at `0x6EACC0` and
      `0x6EBFEC`. See `series_total` for the full derivation and for what is *not* established.

      Also read alone at `0x2753BC` and written at `0x28162C`, both in the roster module.
  - id: team0_chara_ids
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 2026-08-02, renamed from `unknown_array_a`] wire `0x0e`..`0x2d` -> `R+44+4i`. Eight
      u32s, read in an `i < 8` loop straight into the record.

      **Character ids of the players the server assigns to team 0.** When a roster entry is
      installed and `(game+3020 & 0x201) == 0x201`, `0x270CDC`-`0x270D8C` compares the joining
      player's own character id (`session+0x57D8 +0`, the id the server sends at `0x4101` wire
      `0x00`) against all eight of these; a hit branches to `0x270F4C`, which writes **0** into the
      roster entry's team byte (`entry+1`, character-record field 1 — see
      `mgo2_cmd_4440_c2s.ksy`).

      Team **0** here is the same 0-based value the auto-balance picker `0x6EB4F0` produces, and it
      leaves the wire as `1` in `0x4440` (`(v == 1) ? 2 : 1`).

      Unused slots: a zero entry simply never matches a real character id, so short rosters are
      expressed by zero-filling. The comparison is a plain equality with no terminator and no
      count, so all eight are always scanned.
  - id: team1_chara_ids
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 2026-08-02, renamed from `unknown_array_b`] wire `0x2e`..`0x4d` -> `R+100+4i`. Eight
      more. **Last read: 78 bytes total.**

      Same scan, interleaved with the first: a hit here branches to `0x270D9C`, which writes **1**
      into the roster entry's team byte. A player in neither list keeps the default written at
      `0x270694` — `stb r18,1(r28)` with `r18 = -1`, i.e. **255**, the unassigned sentinel (the
      "no team" sentinel written elsewhere in the client is `254`; this path writes `255`, and
      nothing in the image reconciles the two).

      The 28-byte gap between the two arrays in the record (`R+76`..`R+99`) is not filled from this
      packet — but [CORRECTED 2026-08-03] "not touched by any other `0xD3F7B0` caller" was
      false: that window is **team_block[1]'s id and name**, written by `0x4A13`'s parser at
      `0xD450E4`/`0xD45104`. The record is two 56-byte blocks at `R+0x14` and `R+0x4C`, each
      {id, name[16], 4 unused, ids[8]}; this packet fills only the id arrays.
