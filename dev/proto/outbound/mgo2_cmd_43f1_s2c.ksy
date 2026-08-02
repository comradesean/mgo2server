meta:
  id: mgo2_cmd_43f1_s2c
  title: "MGO2 0x43f1 — automatch match announcement (server -> client)"
  endian: be
doc: |
  **The match announcement**, pushed on channel 60 to every member of a formed cohort. **223 bytes:
  19 scalars then the 204-byte settings block.** That 19 + 204 = 223 is what settled the block size
  question; 19 + 159 would be 178.

  The elected host memcpys the block into its own game-settings object at `0x93D398` and then
  creates the game from it. **So this packet is how the server owns the rules** — the block is not
  padding, and it is not a message. Everyone else ignores the block and waits for `0x43f2`.

  Recipients decide their role by comparing `host_chara_id` against their own id (`0xD5B7F4` against
  `net+0x57D8`); it is never stored.

  ## What this packet does NOT carry

  **No game id, no timestamp, no player count.** Rule, map and flags live *inside* the block,
  selected by `rotation_index`. The game id arrives separately in `0x43f2`.

  ## The rotation encoding, and the loading hang

  [CONFIRMED LIVE 2026-07-29] The block's rotation is **16 interleaved `[rule, map, flags]` triples**
  — `block[3i]`, `block[3i+1]`, `block[3i+2]`. The parallel-array reading (all rules, then all maps)
  is the client's *in-memory* form after its sequential reader scatters them, not the wire form.

  Getting this wrong hung the game on the loading screen with no error: a Sneaking+TDM match on map 3
  arrived as entry 0 = `rule 4, map 1` (map 1 has no stage) and entry 1 = `map 0` (which terminates
  every walk). **Two test suites and a hand-decode all passed, because all three used the same wrong
  layout.**

  One or two rotation entries cannot always distinguish the two encodings. The case that settles it
  is **three distinct rules**, observed 2026-07-29: three clients requesting rules 4, 2 and 1 formed
  one game and the client rendered all three modes.

  ## Evidence

  GAME dispatcher `0xD387C8` (compare tree `0xD38804`) matches `cmpwi 0x43F1` at `0xD38A74` -> stub
  `0xD39D6C` -> parser **`0xD5B664`**.

  **No result field, and no request slot completed** — the parser ends with `0xD33CD8(ctx, 44, key)`,
  the fire-and-forget event helper. So the server may push it unprompted, and nothing times out
  waiting for it.

  Sequence: verify `hdr.command == 0x43F1` (else `-70`); `0xD3F7B0(ctx)` obtains record `R`;
  `0xD5C844` open; read the scalars; read the 204-byte block into `R+148` via the **shared helper
  `0xD4364C`** — the same reader `0x4313` uses, which is what makes the block identical by
  construction rather than by analogy; `0xD5C858` close.

  Then the part that independently confirms the block size: `0xD3A094(ctx)` is asked for the current
  game object, and **if it exists and its first word differs from `host_chara_id`**, `0xD3F71C(ctx)`
  is asked for another base and **204 bytes are memcpy'd (`0xDC95C0`) from `R+148` to that base +
  752**. `+752` is exactly where `0x4305` writes its settings block. Two independent confirmations
  in one code path: the block is 204 bytes, and `block + 752` is the struct offset.

  **A note on the first field's older reading.** This packet was originally filed as a generic
  "in-match game-settings push" whose first u32 was a *room/game key*, on the strength of that
  comparison against the current game object. The automatch trace identifies it as the **host
  character id** (compared at `0xD5B7F4` against `net+0x57D8`). Both readings describe the same
  comparison; the automatch one is the more specific and is confirmed live, but the generic path
  above is real and is why a mismatch overwrites the saved-host-settings view.

seq:
  - id: host_chara_id
    type: u4
    doc: |
      [CONFIRMED] The **character id** of the elected host. Compared at `0xD5B7F4` against
      `net+0x57D8` to pick the host branch; never stored.
  - id: lobby_id
    type: u4
    doc: "[CONFIRMED] `lobbyObj+0x25C` in all four sibling writers of this object."
  - id: lobby_subtype
    type: u1
    doc: |
      [CONFIRMED] The same field as `0x4310[0xA2]` and `0x4316`'s u8.

      **Not a useful automatch discriminator**: in lobby 3 the ordinary subtype *is* 2, so this byte
      carries 2 whether or not automatching is involved. Only `0x4316`'s u8 discriminates.
  - id: lobby_subtype_sibling
    type: u1
    doc: |
      [UNKNOWN] `lobbyObj+0x261` -> `R+9`. Position and width exact; the meaning is not established
      **from any reader**. `0x8F9C00` copies `R+9` to the game object's `+661` and `0x8BE094` to
      another object's `+713`; neither destination has a consumer that branches on the value.

      The server currently sends the **rule id** here (`AutomatchPackets.writeMatchFound`), on
      evidence taken from the *source* side of the `0x49xx` parsers — `team+0x261`, read as a rule
      at four `strres` sites. That argument is about where the byte comes from in a different
      packet, not about what this client does with it, so the two readings are not in conflict and
      neither is decisive. Left `lobby_subtype_sibling` here so the name does not assert more than
      the destination trace supports; `0x43F0` carries the same byte onto the same slot, see
      `mgo2_cmd_43f0_s2c.ksy`.
  - id: zero_0a
    type: u4
    doc: |
      [CONFIRMED] **Zeroed by all four sibling writers.** Send 0.

      **Not an inert slot, though** [ELF 2026-08-02]. It lands on `R+12`, and `0x43F0` puts a real
      value there: `0x6EAC48` and `0x6EBF80` evaluate `R+12 - 1 == R+16` as an "is this the last
      one" predicate. That test is gated on `R+8` (`lobby_subtype`) being **3 or 5**, and
      automatching is subtype 2, so zero is safe *here* — by the gate, not by the slot being dead.
      See `mgo2_cmd_43f0_s2c.ksy` `series_total`.
  - id: zero_0e
    type: u4
    doc: |
      [CONFIRMED] Likewise. Send 0. Lands on `R+16`, the index half of the pair described under
      `zero_0a`; also read alone at `0x2753BC`. Same gate, same reasoning.
  - id: rotation_index
    type: u1
    doc: |
      [CONFIRMED] Which of the 16 rotation entries the match starts on.

      **It has a silent fallback the server must respect.** At `0x93D3BC`-`0x93D414`, in state 12
      immediately before the create task, the client reads `rules[idx]`, `maps[idx]` and `flags[idx]`
      out of the block — and **if `maps[idx] == 0` or `rules[idx] > 10` it discards the index and
      uses entry 0.** So naming an index only works when that entry has a nonzero map.
  - id: settings_block
    type: game_settings
    doc: |
      [PARTIAL] The host's 968-byte game-settings object, offsets 0-203 — the same bytes as `0x4313`
      wire `0xA8 + N`, and `block + 752` is the struct offset within the settings object at
      `net+0x8EF8`.

      Field map in `AUTOMATCH.md`; the server's writer is `mgo2server.game.AutomatchSettingsBlock`.
      The load-bearing parts:

      - **`0x00`-`0x2F`** — 16 interleaved `[rule, map, flags]` triples (see the doc above).
      - **`0x43` (67)** — current player count. **Must be nonzero**: the validator at `0x883FB4`
        rejects zero, and the server sends 1.
      - **`0x64` (100)** — the 17-u32 timer array: SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets,
        DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r.
      - **`0xBD` (189)** — the Sneaking SNAKE count, clamped to `[1,5]` by `0x8A1AC8` and rendered as
        a **number** at `0x89D7B8`. That it is a count rather than a side index is settled; that the
        count is specifically *kills of Snake* is not decidable from the binary.

types:
  game_settings:
    doc: |
      204 bytes, offsets relative to the block start. Read by the shared helper `0xD4364C`.
      **Canonical model: `mgo2_cmd_4313_s2c.ksy`, type `game_settings`** — documented field by
      field there; the fields are named here only so the compiler accounts for all 204 bytes.

      Destination offsets equal wire offsets from block+0x30 onward, **but not before**: the
      leading 48 bytes are interleaved, wire triple i landing at block+i / +0x10+i / +0x20+i.

      **TAG NOTE (2026-07-26).** Eleven fields here previously carried "[CONFIRMED via 0x4313]".
      That is exactly the mirror-label failure CLAUDE.md forbids: confidence inherited from a
      sibling packet. 0x43F1 has never been captured, and neither has 0x4313. What IS
      capture-proven is the same 204-byte region as it appears in the `0x4310` push and the
      `0x4305` reply (OBSERVED.md, 2026-07-22 single-variable sweeps). So for every field below:
      the **offset and width are [ELF]** — same reader function, so they are identical by
      construction, not by analogy — while the **name is [INFERRED]** from those two captures.
      Nothing in this packet is [CONFIRMED].

      ## The reader sweep behind every "no reader" claim below (2026-08-02)

      Ten fields here are recorded as having no consumer. That is one experiment, stated once:

      **Method.** The block lands at **struct `+752`** of the game-settings object, so block offset
      `N` is struct offset `752 + N`. Every load/store in the image with a literal displacement in
      `[752, 959]` and a base register other than `r1` was enumerated and clustered by address
      proximity. A cluster counts as *this* struct only if it also touches one of the **marker
      offsets** — `802` (weapon restrictions), `818`/`819` (max/current players), `846` (stance),
      `847` (level tolerance), `940`/`941` (capture extra, SNAKE) — which no other structure in the
      image touches together.

      **Result — the complete set of functions that operate on this object:**

      | site | what it is |
      | --- | --- |
      | `0x883FB4`-`0x884020` | the host-information validator (`768`, `819`) |
      | `0x89CB44`-`0x89DFF8` | timer/SNAKE rendering |
      | `0x8A1110`-`0x8A2408` | create-game timer adjusters |
      | `0x8A5158`, `0x8A5CB0`-`0x8A6FC8`, `0x8A8A2C`-`0x8A9344` | the create-game settings screen |
      | `0x8CA2BC`-`0x8CA5C8` | the in-game publisher: copies settings into **record 0** |
      | `0x907038`-`0x90786C` | the accessor bank — **entirely dead code**, see below |
      | `0xD49510`-`0xD49558` | the `0x4302` game-list row builder |
      | `0xD4364C` / `0xD449xx` | this block's own parser and builder |

      **Controls.** The sweep reproduces every field whose reader was already known: `818` (12
      sites), `847` (12), `941` (9), `848`, `820`, `846`, `936`. The false-positive families it
      correctly rejects are the several unrelated structs in `0x13Dxxx`, `0x31xxxx`, `0x77xxxx`,
      `0x83xxxx` and `0x9Dxxxx` that happen to have u32 arrays at 4-byte strides across 824-844 or
      912-956, and the unrolled 320-stride graphics copy at `0x644F10`-`0x64525C` that writes
      *every* byte of `704..959` on a different object. Each was disqualified by base-object
      identity, not by looking odd.

      **The accessor bank at `0x907024`-`0x907944` is dead.** It is a complete per-field getter API
      over this struct — `lbz 800`, `lbz 801`, `lhz 834`, `lwz 840`, `lhz 922`, `lwz 924`, the
      16 `lwz 928` bit tests, indexed getters for `rules[]`/`maps[]`/`flags[]`/`weapons[]`, and so
      on, each preceded by `bl 0xD3F71C`. **Not one of them is called and not one is registered.**
      There is no `bl` to any of them, their OPD descriptors (`0x101C0E0`-`0x101C238`) appear in no
      data word, and the image is `ET_EXEC` with no relocations, so a runtime-patched reference is
      impossible. It is not reachable through the GCX native table either — that table is a sorted
      `{u32 hash, u32 opd}` array around `0x1030000`-`0x1031800`, and none of these OPDs occurs in
      it (control: the level-table native `0x6F9370` does, at `0x1031584`, and two functions in the
      neighbouring in-game rules API do, at `0x1031060` and `0x1031090`).

      That bank is still **useful as evidence**: it is the game's own declaration of each field's
      width, produced by a different compiler pass from the parser, and it agrees with `0xD4364C`
      on every offset. It is **not** evidence that anything reads the value.
    seq:
      - id: rotation
        size: 48
        doc: "block +0. Sixteen {rule, map, flags} triples. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: unknown_48
        type: u1
        doc: |
          block +48, struct **+800**. Meaning [UNKNOWN]; width [ELF] twice over (`lbz` in the
          parser at `0xD436F4`, `lbz 800(r9)` in the dead accessor `0x907854`).

          **It is the one field in this group that leaves the settings object**, and the trail is
          worth recording because it ends in a wall rather than a name:

          ```
          8ca460  lbz r0,800(r9) ; stb r0,125(r1)     ; the in-game publisher
          8ca6f0  RecordSet(record 0, key 86, len 8, &r1[124])
          ```

          `r1[124..131]` is zeroed as four u16s at `0x8CA444`-`0x8CA450`, then byte 125 takes this
          field and byte 129 takes `unknown_49`. So record 0 key 86 is **four u16s**, of which slot
          0 carries block `+48` and slot 2 carries block `+49`. Record 0 is the 144-byte "global"
          record of the client property store (`CLIENT_STORE.md` §1), and its access rule makes
          writer/reader searches closed by construction: **`0x8CA6F0` is the only writer of key
          86.**

          The **only two readers** are `0x7F4C98` (returns key 86 byte 1 = this field) and
          `0x7F4C50` (returns byte 5 = `unknown_49`) — a pair of one-line getters in the in-game
          rules API. **Both are dead.** No `bl` reaches either, and neither OPD (`0x1018990`,
          `0x1018988`) appears in the GCX native table, while their immediate neighbours
          `0x7F4CE0` (current rotation entry's map) and `0x7F4D68` (its flags) *are* registered, at
          `0x1031060` and `0x1031090`. That contrast is the control: the search finds registrations
          when they exist.

          So the value is **server-authored, published into the client's global record, and read by
          nothing**. Our server sends **0**; there is no evidence for any other value and no reader
          that could tell the difference. Hazard, not bug.
      - id: unknown_49
        type: u1
        doc: |
          block +49, struct **+801**. Meaning [UNKNOWN]; width [ELF] (`lbz` at `0xD43710`; dead
          accessor `0x90782C`).

          Same trail as `unknown_48` and the same dead end: `0x8CA468` copies it to `r1[129]`, it
          rides record 0 key 86 as u16 slot 2, and its only reader `0x7F4C50` is uncalled and
          unregistered. Our server sends **0**. Hazard, not bug.

          The two travel together and are adjacent in both the block and the record, so whatever
          they are, they are a pair.
      - id: weapon_restrictions
        size: 16
        doc: "block +50. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: max_players
        type: u1
        doc: "block +66. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: player_count
        type: u1
        doc: "block +67. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: briefing_time
        type: u4
        doc: "block +68. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: unknown_72
        type: u4
        doc: |
          [ELF 2026-07-29] A **genuine u32**, proven in both directions: the parser reads it with
          `0xd5ccd8` at `0xD43784` (the same u32 reader used for `+68`, `+84`, `+88`, `+96` and all 17
          timers) and the builder writes it with `0xd5c9bc` at `0xD449C8`. So the captured
          `0x02000000` is the value **33554432**, not a `2` with three padding bytes — the wire bytes
          would be identical either way, which is why it needed checking.

          **No reader and no writer exists in the binary.** An exhaustive scan for `,824(rN)` found
          zero sites in the MGO ranges, and there is no accessor for it in the bank at
          `0x907030`-`0x907A70`. Every identified neighbour does appear at its literal offset — `818`
          max players (12 sites), `820` briefing (10), `847` tolerance (11), `941` SNAKE (8) — so
          `824` is a hole rather than a gap in the search. The create-game screen never stores to it.

          The value is therefore **server-authored and merely echoed back by the client**. Meaning
          [UNKNOWN]; the disc's Common Settings label run (13671-13820) has nothing between briefing
          time and friendly fire, so no UI label corresponds to it either.

          **HYPOTHESIS, unproven and marked as such.** The captured u32 is `0x02000000` — a `2` in the
          *most significant* byte. A server writing a single byte into the first octet of a u32 slot
          produces exactly this, so the most economical reading is a **u8 field at +72 holding 2**,
          with three bytes of padding the client happens to read as part of a u32. That is consistent
          with its neighbours: +66 and +67 are u8 counts and +68 is a u4 holding the small value 2.
          What it counts or selects is unknown. **Nothing in the binary can confirm or refute this** —
          the field has no reader — so it must not be promoted without evidence from outside our
          artifacts.
      - id: unknown_76
        type: u4
        doc: |
          block +76, struct **+828**. [UNKNOWN]. Width [ELF]: the parser reads it with the u32
          reader `0xd5ccd8` at `0xD437AC`.

          **No consumer of any kind** [ELF 2026-08-02]. The reader sweep in the block doc above
          found no site in any settings-object function, and — unlike `+82`, `+88`, `+170` and
          `+172` — there is not even a getter for it in the dead accessor bank. It is in the same
          category as `+72`: a hole the client parses, stores, echoes back in its own `0x4310`, and
          never looks at.

          Our server sends **0** and always has. There is no captured non-zero value for it, so
          unlike `+72` and `+179` zero is not a change we are making — it is what a create-game
          screen leaves here too (the screen never writes it either). Hazard, not bug.
      - id: unknown_80
        type: u2
        doc: |
          block +80, struct **+832**. [UNKNOWN]. Width [ELF]: u16 reader `0xd5cc14` at `0xD437C8`.

          **No consumer of any kind**, and no accessor-bank getter. Same category as `+76`. Our
          server sends **0**. Hazard, not bug.
      - id: unknown_82
        type: u2
        doc: |
          block +82, struct **+834**. [UNKNOWN]. Width [ELF] **twice**: u16 reader `0xd5cc14` at
          `0xD437E4`, and `lhz r3,834(r3)` in the accessor bank at `0x907784` — an independent
          compiler-emitted declaration that this is a halfword, not two bytes and not the top half
          of a u32.

          **No live consumer.** That accessor is dead code (see the block doc: the whole bank is
          uncalled and unregistered), and the sweep found nothing else. The nearby `lhz ...,834(...)`
          cluster at `0x7ED52C`-`0x7F4628` is a *different* object — none of those functions touches
          any marker offset of this struct — and was disqualified on that basis, not on appearance.

          Our server sends **0**. Hazard, not bug.
      - id: unknown_84
        type: u4
        doc: |
          block +84, struct **+836**. [UNKNOWN]. Width [ELF]: u32 reader `0xd5ccd8` at `0xD43800`.

          **No consumer of any kind**, and no accessor-bank getter. Same category as `+76` and
          `+80`. Our server sends **0**. Hazard, not bug.
      - id: unknown_88
        type: u4
        doc: |
          block +88, struct **+840**. [UNKNOWN]. Width [ELF] **twice**: u32 reader `0xd5ccd8` at
          `0xD4381C`, and `lwz r3,840(r3)` at `0x907744` in the dead accessor bank.

          **No live consumer.** Our server sends **0**. Hazard, not bug.
      - id: unknown_92
        type: u2
        doc: |
          block +92, struct **+844**. [UNKNOWN]. Width [ELF]: u16 reader `0xd5cc14` at `0xD43838`.

          **No consumer of any kind**, and no accessor-bank getter. Our server sends **0**. Hazard,
          not bug.
      - id: stance
        type: u1
        doc: "block +94. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: level_limit_tolerance
        type: u1
        doc: "block +95. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: level_limit_base
        type: u4
        doc: |
          block +96. [ELF offset+width via 0xD4364C]. Name [INFERRED] from the 0x4310 capture:
          OBSERVED.md pins the level-limit base as a u32 at 0x4310 wire 0xF8, which maps to
          block +96. See mgo2_cmd_4313_s2c.ksy for the derivation.
      - id: rule_timers
        type: u4
        repeat: expr
        repeat-expr: 17
        doc: "block +100..+167. [ELF] widths and count; the per-rule pairing is [INFERRED], tier 4."
      - id: unique_red
        type: u1
        doc: |
          block +168. [ELF] position only — it is the first byte of a 2-byte RAW block, so even
          the split into two u8s is [INFERRED], and the name is [UNKNOWN] (unique characters
          were untestable in this build, OBSERVED.md).
      - id: unique_blue
        type: u1
        doc: "block +169. [ELF] position only; second byte of that raw pair. Name [UNKNOWN]."
      - id: unknown_170
        type: u2
        doc: |
          block +170, struct **+922**. [UNKNOWN]. Width [ELF] **twice**: u16 reader `0xd5cc14` at
          `0xD43A9C`, and `lhz r3,922(r3)` at `0x9074B4` in the dead accessor bank.

          **No live consumer.** Note the contrast with its immediate neighbours `+168`/`+169`
          (struct 920/921), which *are* live: `0x8CA5C0`-`0x8CA5CC` copies both into record 0 key
          134, and the bank has an indexed getter at `0x907174` reading `920 + idx`. That getter
          stops short of 922 — 922 has its own separate halfword accessor — so `+170` is outside the
          920/921 pair rather than a third element of it.

          Our server sends **0**. Hazard, not bug.
      - id: unknown_172
        type: u4
        doc: |
          block +172, struct **+924**. [UNKNOWN]. Width [ELF] **twice**: u32 reader `0xd5ccd8` at
          `0xD43AB8`, and `lwz r3,924(r3)` at `0x90748C` in the dead accessor bank.

          **No live consumer.** `924` is the noisiest offset in this whole sweep — it appears in
          roughly two dozen unrelated functions (`0x83xxxx`, `0x93xxxx`, `0x99xxxx`, `0xA3xxxx`,
          `0xA4xxxx`) that all have u32 arrays striding 912-956 or byte fields at 924 on other
          objects. Every one was disqualified because none touches a marker offset of this struct;
          several use `stb` where this field is a u32, which is the tell.

          Our server sends **0**. Hazard, not bug.
      - id: common_flags_msb
        type: u1
        doc: |
          block +176, struct **+928** — the **most significant byte** of the 32-bit flags word whose
          middle bytes are `common_a` (+177) and `common_b` (+178) and whose low byte is
          `common_flags_lsb` (+179). Renamed from `unknown_176` 2026-07-30.

          [ELF] 117 sites do `lwz rX,928(rB)` and bit-test the result; **every tested bit lies in
          bits 8-23**, i.e. in `common_a`/`common_b` only. Nothing tests bits 24-31, which are this
          byte. Canonical block documentation lives in `mgo2_cmd_4313_s2c.ksy` — this packet carries
          the identical 204-byte block, so findings there apply here unchanged.
      - id: common_a
        type: u1
        doc: "block +177. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: common_b
        type: u1
        doc: "block +178. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: common_flags_lsb
        type: u1
        doc: |
          Renamed from `unknown_179` 2026-07-30, once `+176` was established as the same word's MSB.
          Canonical block documentation is in `mgo2_cmd_4313_s2c.ksy`; the evidence below is this
          file's own and is retained because it is the fuller derivation.

          [ELF 2026-07-29] A u8 with **its own read** — `0xD43B10` uses the u8 reader `0xd5cb8c`,
          while `+177`/`+178` are covered by a single raw-2 read at `0xD43AE4`. The builder splits the
          same way (`0xD44BD8` u8 at struct `931`; `0xD44BC0` raw-2 at `929`), and the game-list row
          builder `0xD49488` copies exactly two bytes from `929` and never touches `931`.

          **It is the low byte of the 32-bit flags word at struct `+928`**, and that is what settles
          it: 117 sites do `lwz rX,928(rB)` and bit-test the result, and **every tested bit lies in
          bits 8-23** — i.e. in `+177`/`+178` only. Nothing anywhere tests bits 0-7. `0x20` sets bit
          5, which no site consumes.

          The sole load of struct `+931` is the accessor `0x9072AC`, which returns the raw byte with
          no compare, mask, index or formatter — and it is **dead code**: its only appearance is its
          OPD descriptor at `0x101C118`, there is no `bl` to it, and the file is `ET_EXEC` with no
          relocations, so a runtime-patched reference is impossible.

          Meaning [UNKNOWN]. The disc's Common Settings list is ~16 items, exactly matching the 16
          bits at 8-23, so no leftover label is available for this byte.

          **HYPOTHESIS, unproven and marked as such.** Bits 8-23 of this flags word are the ~16 Common
          Settings toggles, matching the disc's label run one-for-one. Bits 0-7 are a whole unused
          byte inside the same word, and our capture has **bit 5** set. The economical reading is a
          **second bank of toggles this build does not implement** — later-version settings, or ones
          cut before release — which would explain a flag the client faithfully stores, echoes and
          never consults.

          That is speculation with one supporting observation and no proof: the accessor for this byte
          exists (`0x9072AC`) but is dead code, which is what a build with a feature compiled out
          tends to leave behind. If a later client version is ever compared against this one, **this
          byte is the first place to look** — a bit that goes live there would name itself.
      - id: idle_kick
        type: u2
        doc: "block +180. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: team_kill_kick
        type: u2
        doc: "block +182. [ELF offset+width via the shared reader 0xD4364C; name INFERRED — see the tag note in the block doc]"
      - id: host_ping
        type: u4
        doc: |
          block +184, struct **+936**. Renamed from `unknown_184` 2026-07-30 — the note "no reader
          has been traced" is superseded; one was.

          [ELF] `0xD49548` does `lwz 936(r31)` and stores the result at `T+0x20`, which is the
          `ping` field of a `0x4302` game-list row. That function is the client building a game-list
          record straight out of a game-details object of this exact shape. Corroborated by the
          game-selection picker at `0x934580`, which buckets the same value at 20 ms and 80 ms.

          Canonical block documentation is in `mgo2_cmd_4313_s2c.ksy`.
      - id: capture_extra_time
        type: u1
        doc: "block +188. [ELF] position only; the name is a tier-4 label, meaning [UNKNOWN]."
      - id: sneaking_snake_count
        type: u1
        doc: |
          block +189. [ELF] position and width. **Renamed from `sneaking_snake_side` 2026-07-29**:
          the create-game adjuster at `0x8A1AC8` clamps it to `[1,5]`, and `0x89D7B8` passes it to
          the formatter as an integer — it is **rendered as a number, not looked up as a name**,
          which is what rules out a side index (0/1/2 drawn as a name or sprite). That it is a count
          is settled; that the count is specifically *kills of Snake* is **not decidable from the
          ELF** — that label lives on the disc.
      - id: unread_tail
        size: 14
        doc: |
          block +190..+203, struct **+942..+955**. **One 14-byte raw read**, so the parser draws no
          field boundaries here at all. Renamed from `byte_timers_and_tail` 2026-07-30, because that
          name asserted a subdivision that is not ours to assert.

          **The client never reads or writes any byte of it.** Three touch points image-wide: the
          `0x4310` builder emitting it, the `0x4305` parser reading it, and the create-game
          initialiser memsetting it to zero. Default is fourteen zero bytes.

          The subdivision PROTOCOL.md carries — 8 byte-sized timers for Stealth DM, Interval, Solo
          Capture and Race, then a flag byte and 4 zeros — is a reference-server reading, and it
          names modes whose **strings do not exist on this disc**. Splitting this region needs live
          divergence testing, not disassembly. Canonical block documentation is in
          `mgo2_cmd_4313_s2c.ksy`.
