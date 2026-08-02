meta:
  id: mgo2_cmd_4909_s2c
  title: "MGO2 0x4909 — server -> client: TOURNAMENT detail record, 867 bytes (identical body to 0x4905)"
  endian: be
  encoding: ISO-8859-1
doc: |
  **THIS IS THE SAME RECORD AS 0x4905 — IDENTIFIED 2026-08-02, tier 1.** Not a similar one, not a
  superset: the same 912 bytes at `session+0xD598`, filled from an **identical 867-byte wire
  body**. `0x4905`'s parser forms the destination with `addi r0,r28,-10856` at `0xD48218`; this
  one does it with the same instruction at `0xD4873C`, `r28 = session+0x10000` in both. Walking
  the two parsers side by side, every read primitive, every length argument and every destination
  offset matches, in order, from the first u32 to the last u8. The only two differences are:

    * the request-status slot each completes — **57** for 0x4904/0x4905, **58** for 0x4908/0x4909
      (`li r4,58` at 0xD486D4 / 0xD48B38 / 0xD48B50 here);
    * 0x4905 additionally requires the wire's `detail_id` to match what its sender stashed
      (0xD481E8-0xD4820C). **This parser has no echo check at all** — it accepts whatever arrives.

  **`0x4909` IS THEREFORE NOT A SUPERSET OF `0x4905`.** The two `.ksy` files differ in field count
  (60 vs 28) for a purely editorial reason: this file inlines a mirror of the
  shared 204-byte block as `block_204`, and `mgo2_cmd_4905_s2c.ksy` keeps the same 204 bytes
  opaque as `nested_block`. Every one of the 32 "extra" fields here is a field of that block.
  **There is no 0x4909-only wire field.** Read the two files as one map.

  **WHAT THE RECORD IS.** The **tournament detail record**, behind the *RULE DETAIL* panel of the
  tournament-select screen. `mgo2_cmd_4905_s2c.ksy` carries the full argument and the full
  offset-by-offset map; it is not repeated here. In short, the client names it itself: the single
  function that renders this struct, `0x901808`, drives widgets called
  `NULL_tournamentrule_time` / `_round` / `_ticket` (string literals at `0xE12E48` / `0xE12E70` /
  `0xE12E98`) with the formats `%d分` / `%d回` / `%d枚`, in a literal pool that also holds
  `obj_tournament_select`, `tournament_select_loop` and the caption `RULE DETAIL`.

  **NOT SERVED IN V1.** Tournament lobbies are Ver. 1.20 content, so neither 0x4908/0x4909 nor
  0x4904/0x4905 is sent. Mapping is in scope; building is not. **These mappings cannot reach
  tier 2** — no available client build exercises this family, so nothing below is or can be
  capture-backed. Every `[ELF ...]` tag means "read from the binary", never "confirmed against a
  client".

  **AND THIS ONE IS UNREACHABLE EVEN IN A LATER BUILD OF THIS DISC.** `0x4908`'s sender has no
  caller, so nothing on the client can ask for this reply; the tournament screen uses slot **57**
  (`0xD47624` polls it, `0xD47548` fetches its result), i.e. the 0x4904/0x4905 pair. Slot 58's
  accessor bank exists (`0xD4767C`, `li r4,58`) but nothing drives it. A dead accessor bank still
  declares the slot, which is why it is recorded rather than omitted — but it names nothing.

  **THE READER SET IS CLOSED, AND THE "no reader" ROWS BELOW ARE EXHAUSTIVE NEGATIVES.** The
  argument is in `mgo2_cmd_4905_s2c.ksy` and applies unchanged, because it is an argument about
  the destination struct rather than about either command: a full D-form sweep of
  `0x10230`-`0xDE9328` for displacements in `[-10856, -9945]` finds only the two parsers and the
  accessor `0xD47478`; that accessor has exactly two call sites (`0x8C31D8`, `0x901858`) under a
  branch sweep accepting `bl`, `b` and `bc`; and the record pointer escapes neither of them. The
  control — `struct+0x112`'s known reader at `0x8C31F0` — is found by the sweep.

  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4909` at `0xd38b90` and branches to the
  thunk at `0xd395d8`, which tail-calls the parser at `0xd48674`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  The largest parser in this block. It fills a 912-byte record of its own at `session+0xD598` —
  NOT the 680-byte team record the rest of this family shares. **The two are adjacent but
  disjoint, and the accessors prove it arithmetically**: `0xD47478` returns
  `session+0x10000-10856` = `session+0xD598`, `0xD491F8` returns `session+0x10000-9944` =
  `session+0xD928`, and `0xD598 + 912 = 0xD928` exactly — this record ends on the byte the team
  record begins. No offset of one can coincide with an offset of the other, so this record does
  **not** embed the team trailer (`+0x25C` lobby_id, `+0x260` subtype, `+0x298` tournament_id,
  `+0x2A4` entry_fee) and does not embed a lobby descriptor; the hub/lobby list at `ctx+0xB790` is
  a third base again. The one structure it does embed is the 204-byte `game_settings` block, and
  that is proved by the destination argument handed to `0xD4364C` (`struct+0x40`, at 0xD48950),
  not by offsets agreeing. Preconditions: `hdr.command == 0x4909` and request-status
  slot **58** must read as 1 (pending) via `0xD32E3C`, else `-70` and the packet is dropped
  [READ 0xd486d8]. Then a 4-byte result; **nonzero skips every field** and only the request
  slot is completed. On success the destination record is memset to **912 bytes** and filled
  in wire order below. Slot 58 is completed with the result at the end.

  One 204-byte sub-block is read by the shared reader `0xD4364C`. That reader has **nine** call
  sites, not two: `0xD445A4` (0x4313), `0xD48440` (0x4905), `0xD48964` (here), `0xD4B244`
  (0x4987), `0xD4CB08` (0x4950), `0xD5006C` (the shared 0x4A24/0x4A31 parser), `0xD51014`
  (0x4A00), `0xD5AF38` (0x4E10) and `0xD5B78C` (0x43F1). An earlier revision of this file said
  "also read by 0x4950 and 0x4987"; that list was seven short. [ELF, exhaustive `bl 0xd4364c`
  scan of 0xD30000-0xD60000, 2026-07-26]

  **The canonical model of this block lives in `mgo2_cmd_4313_s2c.ksy`, type `game_settings`.**
  That copy is the best-evidenced one: 0x4313's block is the same 204 bytes read by the same
  function, and its field names are backed by live capture of the `0x4310` push and the `0x4305`
  reply (OBSERVED.md). `block_204` below is retained as a mirror; where the two disagree, 0x4313
  wins.

  **"Whether the game-settings *semantics* apply to a 0x4909 record is [UNKNOWN]" — SUPERSEDED
  2026-08-02.** They do, and this record is the one carrier outside the game-details object where
  that is shown rather than assumed: the RULE DETAIL panel `0x901808` reads `block+0x10..+0x16` as
  stage ids through `strres(0x654515, map + 74)` and `block+0x6C..+0xA4` as the per-rule
  time/round/ticket table, both **through this record's own base**, and both land exactly where
  `game_settings` puts them. See the `block_204` type doc for the full argument, the offset
  bijection and the reader census.

  Note its leading loop is
  **interleaved**: it reads three bytes per iteration for 16 iterations, scattering them into
  three separate 16-byte arrays in the struct — so on the wire it is 16 triples, not three
  runs of 16.

  Total payload: 4 + 4+1+1+1+1 + 2+16 + 4*4 + 204 + 2*4+4 + 64 + 512 + 4*5 + 4+4 + 1
  = **867 bytes**. Nothing here is confirmed live; no capture of this id exists.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: "[ELF 0xd48700] 0 = success; nonzero skips every field below (4-byte payload)."
  - id: detail_id
    type: u4
    doc: |
      [ELF 0xd48724] First word after the result; T+0x000. Read into a stack slot, then stored
      after the 912-byte memset. **The tournament id.** Named from the 0x4905 twin, where the
      same wire word is checked against what 0x4904's sender stashed at `q+0x26D04`
      (`stw` 0xD47BD8, `lwz`/`cmpw`/`bne` 0xD48204-0xD4820C). **This parser performs no such
      check** — it stores the word unconditionally — so on this path the field is not even a
      pairing token. **No reader** afterwards (exhaustive; top-level doc).
  - id: unknown_08
    type: u1
    doc: |
      [UNKNOWN — meaning] T+0x004. Width and position [ELF 0xd48768].
      **No reader** (exhaustive; top-level doc).
  - id: rule
    type: u1
    doc: |
      [ELF 0xd48784] T+0x005. **The tournament's game rule**, enum
      `0=Deathmatch 1=Team Deathmatch 2=Rescue 3=Capture 4=Sneaking 5=Base 6=BOMB
      7=Team Sneaking`. Identified 2026-08-02 in the RULE DETAIL panel `0x901808`: `lbz r3,5(r31)`
      at 0x9019C8/0x901A14 then `addi r3,r3,22` and `bl 0x8E0BF0`, the disc-string getter for
      group hash **0x654515** (the rule/map master list) — ids 22..29 of that set are `DM`, `TDM`,
      `RES`, `CAP`, `SNE`, `BASE`, `BOMB`, `TSNE`, and the long forms at `2*rule` agree. The
      client bounds the field to **0..7** itself: `cmplwi r0,7` / `bgt` at 0x901A70 guards an
      8-way jump table at 0x901A90. Full derivation in `mgo2_cmd_4905_s2c.ksy`.

      Same enum as the team record's `+0x261` and `0x4310`'s rotation rule — **enum identity, not
      offset identity**; those live in a different struct (top-level doc).
  - id: unknown_0a
    type: u1
    doc: |
      [UNKNOWN — meaning] T+0x006. Width and position [ELF 0xd487a0].
      **No reader** (exhaustive; top-level doc).
  - id: flags
    type: u1
    doc: |
      [ELF 0xd487bc-0xd4888c] Read as a 1-byte raw block, then **bit-reversed** into T+0x007:
      wire bit 0 -> 0x80, 1 -> 0x40, 2 -> 0x20, 3 -> 0x10, 4 -> 0x08, 5 -> 0x04, 6 -> 0x02,
      7 -> 0x01. All eight bits are expanded (unlike the clan-record parser, which expands
      three). Individual meanings [UNKNOWN].

      **No reader** for any of the eight bits (exhaustive; top-level doc). The `ld`/`std` pair
      operates on the 64-bit word at T+0x000, so the bits land in its low byte — T+0x007 — and
      leave `detail_id` and the three u8 above it untouched.
  - id: unknown_0c
    type: u2
    doc: |
      [UNKNOWN — meaning] T+0x008. Width and position [ELF 0xd488a0].
      **No reader** (exhaustive; top-level doc).
  - id: name
    type: str
    size: 16
    doc: |
      [INFERRED] T+0x00a, 16-byte raw block; name-width by analogy. Width is [ELF 0xd488c0].

      **No reader** (exhaustive; top-level doc), and the inference is now weaker than it looks:
      the tournament's *displayed* title is the 64-byte block at T+0x118, which the RULE DETAIL
      panel loads directly, whereas nothing anywhere loads this. `str`/ISO-8859-1 is retained
      because it is a declared type and this batch does not change declarations — but treat it as
      "16 raw bytes of unknown role", not as a confirmed name.
  - id: unknown_1e
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x020 (stored 64-bit-wide). [ELF 0xd488e0/0xd488fc]
      **No reader** (exhaustive; top-level doc).

      Four consecutive u32-widened-to-u64 in a tournament record are the obvious place for
      open/close/start/end timestamps, and the widening is what this build does for time_t
      elsewhere. That is **a lead, not a finding**: no reader exists to name any of the four, and
      nothing in the ELF tells them apart.
  - id: unknown_22
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x028. [ELF 0xd48900/0xd4891c]
      **No reader** (exhaustive; top-level doc). See `unknown_1e`.
  - id: unknown_26
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x030. [ELF 0xd48920/0xd4893c]
      **No reader** (exhaustive; top-level doc). See `unknown_1e`.
  - id: unknown_2a
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x038. [ELF 0xd48940/0xd48960]
      **No reader** (exhaustive; top-level doc). See `unknown_1e`.
  - id: block
    type: block_204
    doc: |
      [ELF 0xd48964] The shared 204-byte block read by 0xD4364C into T+0x040. The destination
      argument is what proves the embedding; no offset coincidence is relied on.

      **Two regions of it are read through this record's base** by the tournament panel
      `0x901808` (2026-08-02): `block+0x10..+0x16`, the first seven `rotation_round.map` bytes,
      rendered as stage names via `strres(0x654515, map + 74)`; and `block+0x6C..+0xA4`, the
      per-rule time / round / ticket table, selected by the 8-way jump table on the `rule` field
      above. The second corroborates `mgo2_cmd_4313_s2c.ksy`'s `rule_timers` ordering slot for
      slot from an independent site, with the client's own widget names attached. The full table
      is written out in `mgo2_cmd_4905_s2c.ksy` under `nested_block`; it is not duplicated here,
      for the same anti-drift reason `block_204` itself is only a mirror.
  - id: unknown_fa
    type: u2
    doc: |
      [UNKNOWN — meaning] T+0x10c. [ELF 0xd48980]
      **No reader** (exhaustive; top-level doc).
  - id: unknown_fc
    type: u2
    doc: |
      [UNKNOWN — meaning] T+0x10e. [ELF 0xd4899c]
      **No reader** (exhaustive; top-level doc).
  - id: unknown_fe
    type: u2
    doc: |
      [UNKNOWN — meaning] T+0x110. [ELF 0xd489b8]
      **No reader** (exhaustive; top-level doc). It is the u16 immediately before
      `max_participants`, so a *current*-participants counter is the obvious guess — and the
      client **refutes** it: the "currently joined" numerator of disc string 731 is counted at
      0x8C3190-0x8C31C8 by walking eight 28-byte roster slots at `+380` in the *team* record
      (`0xD491F8`), never read from this struct.
  - id: max_participants
    type: u2
    doc: |
      [ELF 0xd489d4] T+0x112. **Maximum participant count.** Read at **0x8C31F0**
      (`lhz r29,274(r9)`, r9 = `0xD47478(session)`) and passed as the **second** `%d` of disc
      string **731**, "Number of Players Currently Joined: %d / %d" (`li r3,731`, `bl 0x8E0C24`,
      the getter for group hash 0xF914BF). The first `%d` comes from the team record, not here.

      This field is also the **control** for every negative claim in this file: a sweep that
      cannot find 0x8C31F0 is broken.
  - id: unknown_102
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x114. [ELF 0xd489f0]
      **No reader** (exhaustive; top-level doc).
  - id: title
    type: str
    size: 64
    doc: |
      [ELF 0xd48a10] T+0x118, 64-byte raw block — the same width as the 0x4902 text block.
      **The tournament's displayed title.** `0x901878` forms `r27 = record + 280` (280 = 0x118)
      and passes it as the text argument to the widget setter `0x246EC0` at 0x9018F0 and
      0x901928, filling the two children of the panel's title widget (`r23+116`) — text and
      shadow. It is handed over **raw**: no `strres` lookup, no formatting.

      The declared `str`/ISO-8859-1 is retained (declarations are evidence and are not changed
      here), but note the call site establishes only "these bytes are displayed as text"; the
      **encoding is [UNKNOWN]**, since the UI layer, not this code, interprets them.
  - id: text_512
    type: str
    size: 512
    doc: |
      [INFERRED] T+0x159 — note the odd destination: 64 bytes were written at T+0x118 and
      this lands at 0x159, one byte past 0x158. 512-byte raw block, the widest field in the
      lobby protocol. Text is inferred; the width is [ELF 0xd48a30].

      **No reader** (exhaustive; top-level doc) — and that is the notable part. A 512-byte field
      in a tournament record is description-shaped, but the RULE DETAIL panel does not load it and
      nothing else in the binary does either. Either the description is drawn by the lobby stage
      script rather than the ELF, or this build shipped the field without the screen that shows
      it. Telling those apart needs the lobby `.gcx`, not the disassembler, and has not been done.
  - id: unknown_346
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x364. [ELF 0xd48a4c] **No reader** (exhaustive; top-level doc).
      This and the seven fields below are a 44-byte trailer nothing in the binary reads. It is
      **not** the team record's `+0x25C..+0x2A4` lobby/tournament/entry-fee trailer — that belongs
      to a different struct beginning at `session+0xD928`, exactly where this one ends. The
      resemblance is in shape only; no offset bijection exists.
  - id: unknown_34a
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x368. [ELF 0xd48a68]
      **No reader** (exhaustive; top-level doc). See `unknown_346`.
  - id: unknown_34e
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x36c. [ELF 0xd48a84]
      **No reader** (exhaustive; top-level doc). See `unknown_346`.
  - id: unknown_352
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x370. [ELF 0xd48aa0]
      **No reader** (exhaustive; top-level doc). See `unknown_346`.
  - id: unknown_356
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x374. [ELF 0xd48abc]
      **No reader** (exhaustive; top-level doc). See `unknown_346`.
  - id: unknown_35a
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x378 (stored 64-bit-wide). [ELF 0xd48ad4/0xd48af0]
      **No reader** (exhaustive; top-level doc). Same time_t-shaped widening as T+0x020..+0x038;
      same lead, same absence of a reader to confirm it.
  - id: unknown_35e
    type: u4
    doc: |
      [UNKNOWN — meaning] T+0x380 (stored 64-bit-wide). [ELF 0xd48af4/0xd48b14]
      **No reader** (exhaustive; top-level doc). See `unknown_35a`.
  - id: unknown_362
    type: u1
    doc: |
      [UNKNOWN — meaning] T+0x388, last field; the 912-byte record ends at 0x390.
      [ELF 0xd48b18] **No reader** (exhaustive; top-level doc). T+0x389..+0x38F are memset-zero
      padding the wire never reaches.
types:
  block_204:
    doc: |
      [ELF 0xD4364C] Shared 204-byte block; nine call sites, listed in the top-level doc.
      **Canonical model: `mgo2_cmd_4313_s2c.ksy` type `game_settings`** — this remains a mirror,
      and where the two disagree that file wins. Offsets below are relative to the block's own
      destination. The leading section is **interleaved on the wire**: 16 iterations of
      {u8 -> +0x00+i, u8 -> +0x10+i, u8 -> +0x20+i}, so the wire order is triple(0), triple(1)
      ... triple(15) while the struct holds three 16-byte arrays.

      ## THE BIJECTION WITH `game_settings`, AND WHY THE NAMES NOW TRANSFER (2026-08-02)

      The line that used to close this doc — "every field's meaning is [UNKNOWN]; only positions
      and widths are established" — was true when written and is no longer. Two separate things
      had to be settled to retire it, and they are settled by different evidence.

      **1. Same struct, same offsets — by construction.** `0xD4364C` is ONE function whose
      destination base is `r29`, the block pointer; every field is a literal displacement off it.
      Disassembling `0xD4364C`-`0xD43BC0` yields exactly this displacement list, and it does not
      depend on which call site supplied `r29`:

          0..47   3x u8 per iteration, 16 iterations   (0xD4368C / 0xD436B0 / 0xD436D0)
          48 u8   49 u8   50 raw16   66 u8   67 u8   68 u32   72 u32   76 u32
          80 u16  82 u16  84 u32     88 u32  92 u16   94 u8    95 u8
          96..164 u32 x18 (unrolled)
          168 raw2  170 u16  172 u32  176 u8  177 raw2  179 u8
          180 u16   182 u16  184 u32  188 u8  189 u8    190 raw14   = 204 total

      `mgo2_cmd_4313_s2c.ksy` transcribes the same list from the same function, so there is no
      wire position at which the two types could disagree. This is offset identity, not
      resemblance.

      **2. The meanings carry into THIS record specifically** — and unusually for a post-launch
      command, that has a same-carrier proof rather than an argument by analogy. The tournament
      RULE DETAIL panel `0x901808` reads this block **through this record's own base**, and what
      it reads it as matches `game_settings` field for field:

      - `block+0x10..+0x16` — the first seven `triple.b` bytes — are resolved as stage names via
        `strres(0x654515, b + 74)`. That is `rotation_round.map`.
      - `block+0x6C..+0xA4` are selected in pairs and triples by an 8-way jump table on the
        record's `rule` byte and formatted with `%d分` / `%d回` / `%d枚` into widgets named
        `NULL_tournamentrule_time` / `_round` / `_ticket`. That is `rule_timers`, in the canonical
        order, including Deathmatch's missing rounds slot.

      So in a `0x4909` record this block is the event's game settings, with the same fields in the
      same places. Names below are transferred on that basis.

      **Tier, stated once.** Offsets and widths are [ELF]. The names originate in the
      capture-proven `0x4310` push and `0x4305` reply of the same 204 bytes (OBSERVED.md, plus the
      214 archived payloads in `../samples/4310/captures.psv`), so they are tier 2 **on the
      struct**. No available client build exercises `0x4909`, so nothing here is tier 2 *for this
      command* and no capture backs any statement about a tournament record.

      **What deliberately does NOT transfer: the canonical file's "no reader in the image"
      verdicts** for block +72, +76, +80, +82, +84, +88, +92, +170 and +172. Those were
      established against the **game-details object**, where the block sits at struct `+752` and a
      displacement sweep could use the marker offsets 802/818/819/846/847/940/941 to separate that
      object from every other. Here the block sits at `T+0x040` of a 912-byte tournament record,
      so the displacements are different numbers and the sweep does not carry across. **Liveness
      is a property of the carrier; layout is not.** Where a field below reports the canonical
      carrier's negative, it says so.

      ## THIS CARRIER'S OWN READER CENSUS — closed by construction, not by sampling (2026-08-02)

      Seven fields below carry a negative that IS this carrier's own. It rests on one experiment,
      stated once here rather than nine times below.

      **The record is at a fixed session offset, so the set of code that can hold its address is
      finite and enumerable.** `0xD47478` is the getter: `addis r3,r3,1` / `addi r0,r3,-10856`,
      i.e. **`session + 0xD598`**. Every route to that address was enumerated:

      - **`bl 0xD47478`** — exactly **two** call sites image-wide: `0x8C31D8` (the
        "Number of Players Currently Joined" screen) and `0x901858` (the RULE DETAIL panel).
      - **the same arithmetic inlined** — `addi rX,rY,-10856` occurs at exactly **three**
        addresses: `0xD47488` (inside the getter itself), `0xD48218` (the `0x4905` parser) and
        `0xD4873C` (the `0x4909` parser). Both parsers are writers.
      - **an alias from the neighbouring struct.** The team record at `session+0xD928` begins
        exactly where this record ends, so a reader could in principle hold that base and use
        negative displacements `-912..-1`. It cannot: the image contains **zero** load or store
        instructions with a negative three-digit displacement, for any field, including the ones
        whose readers are known. The route is unused, so it is not a hiding place.
      - **an indirect call through the getter's OPD.** `0xD47478`'s descriptor is at `0x1029880`
        (`{code 0xD47478, toc 0x010353A8}`, one of a run of sibling accessors). For anything to
        call it indirectly, that descriptor's *address* would have to appear in a data word: it
        occurs exactly once image-wide, at `0xC27605`, which is **not 4-byte aligned** and is
        therefore an incidental byte sequence inside other data, not a pointer slot. No
        registration exists.
      - **a spilled pointer.** Neither reader stores the base anywhere but its own stack frame, and
        neither passes it to a callee. The only derived pointer that escapes the panel is
        `r27 = r31 + 280`, the 64-byte title text at `T+0x118`, handed to widget setters — 280 is
        past the block, which ends at record offset 267.

      So the four functions above are the complete universe. Within them, the record base lives in
      `r31` and `r22` in the panel (`r31` is reused as a loop counter from `0x901F58`, after which
      only `r22` holds it) and in `r9` in the joined-count screen, live for four instructions.
      **Every access to the record anywhere in the image** is then:

          record +5            the `rule` byte (0x9019C8 / 0x901A14 / 0x901A6C)
          record +80..+86      block+0x10..+0x16, map[0..6], walked as a pointer
                               (`addi r26,r22,80` at 0x901F4C, `lbz`/`addi 1`, 7 iterations)
          record +172..+228    block+0x6C..+0xA4, `words[3..17]`, the per-rule timer table
                               (0x901ABC-0x901B10, an 8-way jump table on the rule byte)
          record +274          `max_participants` (0x8C31F0)
          record +280          the 64-byte title

      **This reproduces, by a different route, the negative already stated in this file's
      top-level doc** — that sweep worked forward from a displacement range (`[-10856, -9945]`
      against the session base) and a branch sweep accepting `bl`/`b`/`bc`; this one works
      backward from the record's own offsets. Two independent derivations, same four functions.
      The routes each adds to the other are noted above: the earlier sweep closes tail-call
      branches, this one closes the OPD and the negative alias.

      **Controls, which succeed.** `record+274` is reproduced (`lhz r29,274(r9)` at `0x8C31F0`),
      and so is the whole timer run at `+172..+228`. A census that failed to find either would be
      broken. Note also what the method had to survive: `record+80` is read by **pointer walk**,
      not by a literal displacement, so a displacement-only sweep would have missed it — the `addi`
      forms are enumerated for exactly that reason.

      **The residue.** Everything in the block outside `+0x10..+0x16` and `+0x6C..+0xA4` has **no
      reader in this carrier**. That includes fields that ARE named and live elsewhere
      (`weapon_restrictions`, `max_players`, `host_stance`, `common_ab`, `sneaking_snake_kills`,
      …) — being unread by the tournament screens says nothing about them in the game-details
      object, and the reverse holds too. It is stated below only for the seven fields that have no
      name from any carrier, because for those it is the whole of what is knowable here.
    seq:
      - id: triples
        type: triple
        repeat: expr
        repeat-expr: 16
        doc: "[ELF 0xd43678-0xd436e4] 16 wire triples scattering into three 16-byte arrays at +0x00/+0x10/+0x20."
      - id: unknown_30
        type: u1
        doc: |
          [UNKNOWN — meaning] +0x30 (block +48). Offset and width [ELF] `0xD436F4`.

          **No name exists to transfer**: the canonical file carries this byte as `unknown_48`
          too, so it is unnamed campaign-wide rather than merely un-caught-up here. What travels
          with the byte, recorded so the gap is explicit:

          - In the **game-details carrier** it is published and then read by nothing. `0x8CA460`
            copies struct `+800` into a scratch byte and `0x8CA6F0` publishes that scratch as
            client property-store **key 86**, an 8-byte record of which only bytes 1 and 5 are
            ever filled — this byte and `unknown_31`. The two ELF-side readers of those bytes,
            `0x7F4C98` and `0x7F4C50`, are **dead code**: no `bl` reaches either and neither OPD
            appears in the GCX native table, while their immediate neighbours' OPDs do (the
            control that shows the search finds registrations when they exist).
          - **Nothing in the create-game UI writes it**, so it is server-authoritative and simply
            round-trips through the client's own `0x4310`.
          - **Capture value: 0x00 in all 214 archived `0x4310` payloads.**

          None of that is claimed for a tournament record — see the liveness note in the type doc.
          The pairing with `unknown_31` is structural and does carry.
      - id: unknown_31
        type: u1
        doc: |
          [UNKNOWN — meaning] +0x31 (block +49). Offset and width [ELF] `0xD43710`. Canonical
          `unknown_49`; no name exists to transfer.

          Element 1 of the pair described under `unknown_30`: `0x8CA468` publishes it as key 86
          byte 5, its only ELF reader `0x7F4C50` is uncalled and unregistered, and no UI widget
          writes it. **Capture value: 0x00 in all 214 archived payloads.** Same carrier caveat.
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] +0x32, 16-byte raw block (0xD5D018 r5=16, [ELF 0xd43730]). **Not a
          string.** An earlier revision of this file typed it `str name`, "[INFERRED] name-width
          by analogy" — inferred from the width alone, against capture evidence that already
          existed. This is the weapon-restriction bitfield: one bit per item, 1 = locked, byte 0
          bit 0 the master enable. The 2026-07-22 single-variable sweep confirmed it weapon by
          weapon, nineteen for nineteen, at `0x4310` wire `0xD5`..`0xE4` (OBSERVED.md, "The
          weapon-restriction table, confirmed weapon by weapon"); `0x4310`'s copy of this block
          starts at wire `0xA3`, and `0xA3 + 0x32 = 0xD5`. The mapping is corroborated at six
          other offsets in the same capture — max characters `0xE5` = +66 (direct); then, with
          `0x4310` omitting the same fields `0x4305` omits, briefing `0xE6` = +68, tolerance
          `0xF7` = +95, level-limit base `0xF8` = +96, commonA/B `0x142`/`0x143` = +177/+178.
          16 bytes of ISO-8859-1 text is what a 16-byte bitfield looks like from the width alone.
      - id: max_players
        type: u1
        doc: |
          [ELF offset+width `0xD43744` -> +0x42 (block 66); name INFERRED from capture]
          **Maximum player count.** Renamed from `unknown_42` 2026-08-02.

          Capture-proven at `0x4310` wire `0xE5` — `0xA3 + 0x42`, with no omitted field before it,
          which is the shortest mapping in the whole block. 176 of the 214 archived payloads read
          `0x10` = 16, the game's own maximum; the other 38 read 2, 3 or 17.
      - id: player_count
        type: u1
        doc: |
          [ELF offset+width `0xD43760` -> +0x43 (block 67); name INFERRED] **Current player
          count.** Renamed from `unknown_43` 2026-08-02.

          The identification is a negative that happens to be sharp: `0x4305` (saved settings) and
          `0x4310` (host push) both omit **exactly this byte** out of this whole region, which is
          what a live-session field looks like in a saved-settings reply. In the game-details
          carrier the validator at `0x883FB4` rejects zero here. Whether a tournament record
          validates it is not claimed.
      - id: briefing_time
        type: u4
        doc: |
          [ELF offset+width `0xD4377C` -> +0x44 (block 68); name INFERRED from capture]
          **Briefing length.** Renamed from `unknown_44` 2026-08-02.

          Capture-proven at `0x4310` wire `0xE6`. The create-game adjuster at
          `0x8A6D14`-`0x8A6E74` steps it by ±1 with a ±30 jump and bounds-tests against 1 and 29,
          so the range is about [0,30]; `0x8CA588` publishes it as property-store **key 96**, and
          the units label is disc string 574. 172 of 214 archived payloads read 2, the other 42
          read 1.
      - id: unknown_48
        type: u4
        doc: |
          [UNKNOWN — meaning] +0x48 (**block 72**; note the id is the hex wire offset, not the
          canonical file's decimal `unknown_72`). Width [ELF] in both directions: the parser at
          `0xD43790` uses the u32 reader `0xD5CCD8` and the `0x4310` builder at `0xD449C8` the u32
          writer `0xD5C9BC` — so a captured `0x02000000` is the value 33554432, not a `2` with
          three pad bytes. The wire bytes are identical either way, which is why it needed
          checking.

          **No name to transfer.** In the game-details carrier the canonical file reports no
          reader and no writer anywhere in the image, and no accessor-bank getter either; that is
          a statement about struct `+824`, not about `T+0x88` of a tournament record, and is not
          re-asserted here.

          Captures read `0x02000000` in 182 of 214 and `0x00000000` in 32 — and that split is
          **exactly** the split of `common_flags_lsb` below, 214 for 214, the two never disagree.
      - id: unknown_4c
        type: u4
        doc: |
          [UNKNOWN — meaning] +0x4c (block 76), record offset **140**. Width [ELF] u32 reader
          `0xD5CCD8` at `0xD437AC`. Canonical `unknown_76`; no name to transfer.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 140 falls outside
          every range they touch — the nearest accesses are `record+86` and `record+172`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          **Nor is it carried by `0x4310` or `0x4305` at all**, so this family, `0x4313` and
          `0x43F1` are the only commands that can set it and no archived capture of it exists.
          Combined with the canonical carrier's own finding — no consumer of any kind at struct
          `+828`, not even a getter in the dead accessor bank — this field currently has **no
          identified reader in any carrier**. That is the strongest statement available and it is
          still not a meaning: the value is server-authored, stored, and echoed back.
      - id: unknown_50
        type: u2
        doc: |
          [UNKNOWN — meaning] +0x50 (block 80), record offset **144**. Width [ELF] u16 reader
          `0xD5CC14` at `0xD437C8` — a halfword, not the top half of a u32. Canonical
          `unknown_80`; no name to transfer.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 144 falls outside
          every range they touch — the nearest accesses are `record+86` and `record+172`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          Beware one false positive the census rejects on base-register grounds rather than on
          appearance: displacement 144 does occur inside both parsers, at `0xD48138`/`0xD48654`
          and `0xD48680`/`0xD48B78`, but every one of those is `std`/`ld` with base **`r1`** —
          callee-save slots in the parser's own stack frame, not this record.

          Capture value `0x0000` in all 214 archived `0x4310` payloads, and the canonical carrier
          reports no consumer and no accessor-bank getter either.
      - id: unknown_52
        type: u2
        doc: |
          [UNKNOWN — meaning] +0x52 (block 82). Width [ELF] **twice**: u16 reader `0xD5CC14` at
          `0xD437E4`, and an independent compiler-emitted `lhz r3,834(r3)` in the game-details
          accessor bank at `0x907784`. That bank is dead code, but a dead accessor still declares
          a width. Canonical `unknown_82`; no name to transfer. Not carried by `0x4310`/`0x4305`.
      - id: unknown_54
        type: u4
        doc: |
          [UNKNOWN — meaning] +0x54 (block 84), record offset **148**. Width [ELF] u32 reader
          `0xD5CCD8` at `0xD43800`. Canonical `unknown_84`; no name to transfer.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 148 falls outside
          every range they touch — the nearest accesses are `record+86` and `record+172`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          Capture value `0x00000000` in all 214 archived `0x4310` payloads; the canonical carrier
          reports no consumer and no accessor-bank getter. No identified reader in any carrier.
      - id: unknown_58
        type: u4
        doc: |
          [UNKNOWN — meaning] +0x58 (block 88), record offset **152**. Width [ELF] **twice**: u32
          reader `0xD5CCD8` at `0xD4381C`, and an independent compiler-emitted `lwz r3,840(r3)` in
          the game-details accessor bank at `0x90775C`. That bank is dead code — a dead accessor
          still declares a width, and only a width. Canonical `unknown_88`; no name to transfer.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 152 falls outside
          every range they touch — the nearest accesses are `record+86` and `record+172`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          Same stack-frame false positive as `unknown_50`: displacement 152 appears at `0xD48140`,
          `0xD4865C`, `0xD48688` and `0xD48B80`, all `std`/`ld` off **`r1`**.

          Not carried by `0x4310` or `0x4305`, so no capture of it exists.
      - id: unknown_5c
        type: u2
        doc: |
          [UNKNOWN — meaning] +0x5c (block 92), record offset **156**. Width [ELF] u16 reader
          `0xD5CC14` at `0xD43838`. Canonical `unknown_92`; no name to transfer.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 156 falls outside
          every range they touch — the nearest accesses are `record+86` and `record+172`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          It is the last field before `words[0]` (`level_limit_base`, record +160), and the panel's
          timer jump table starts at `words[3]` = record +172, so nothing in this carrier reads
          within 16 bytes of it in either direction. Capture value `0x0000`, 214 of 214; the
          canonical carrier reports no consumer and no accessor-bank getter.
      - id: host_stance
        type: u1
        doc: |
          [ELF offset+width `0xD43854` -> +0x5e (block 94); name CONFIRMED from the binary's own
          developer table] **The host stance.** Renamed from `unknown_5e` 2026-08-02.

          Better evidenced than a transferred name: the client carries nine NUL-padded 20-byte
          entries at **`0xE1BC48`** reading `HOST_STANCE_EASY`, `HOST_STANCE_REAL`,
          `HOST_STANCE_BEGINNER`, `HOST_STANCE_EVERYONE`, `HOST_STANCE_OTHER`,
          `HOST_STANCE_TRAINING`, `HOST_STANCE_INSTRUCTOR_ENTRY`, `HOST_STANCE_INSTRUCTOR_STARTED`,
          `HOST_STANCE_NONE` — ids 0..8 — and range-gates the value with `cmplwi 9 / bgt` at
          `0xA31230`. In the game-details carrier `0x8CA580` publishes it as property-store key 94
          and `0xD49530` copies it into a `0x4302` row at `T+0x24`, which that spec also calls
          stance. Archived payloads carry 0 (156), 2 (32), 6 (19) and 5 (7).
      - id: level_limit_tolerance
        type: u1
        doc: |
          [ELF offset+width `0xD43868` -> +0x5f (block 95); name INFERRED from capture]
          **The level-limit tolerance, in LEVELS** — applied as `base ± tolerance` around
          `words[0]`. Renamed from `unknown_5f` 2026-08-02.

          Capture-proven at `0x4310` wire `0xF7`, immediately before the level-limit base at
          `0xF8` (OBSERVED.md 2026-07-22). Corroborated twice in the game-details carrier:
          `0x8CA544` publishes it as property-store key 98, directly beside key 99 = the base, and
          the game picker at `0x93452C`-`0x93455C` tests a candidate's level against entry `+38`
          as a tolerance around entry `+40`. 211 of 214 archived payloads read `0x16` = 22, the
          level cap — i.e. hosts overwhelmingly leave the limit wide open.
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: |
          [ELF 0xd43884-0xd43a60] Eighteen consecutive 4-byte reads into +0x60 .. +0xa4; no loop
          in the code, eighteen unrolled call sites.

          **No longer all [UNKNOWN] (2026-08-02).** `mgo2_cmd_4313_s2c.ksy` splits this run as
          `level_limit_base` (+0x60) followed by `rule_timers[0..16]` (+0x64..+0xa4), and the
          tournament RULE DETAIL panel `0x901808` **independently reproduces that split and that
          ordering**, reading these words through *this* record's base:

              words[3]  +0x6c  CAP time     words[11] +0x8c  DM tickets
              words[4]  +0x70  CAP rounds   words[12] +0x90  BASE time
              words[5]  +0x74  RES time     words[13] +0x94  BASE rounds
              words[6]  +0x78  RES rounds   words[14] +0x98  BOMB time
              words[7]  +0x7c  TDM time     words[15] +0x9c  BOMB rounds
              words[8]  +0x80  TDM rounds   words[16] +0xa0  TSNE time
              words[9]  +0x84  TDM tickets  words[17] +0xa4  TSNE rounds
              words[10] +0x88  DM time

          The panel's 8-way jump table at `0x901A90` picks the pair (or triple) by the record's
          `rule` byte and formats them with `%d分` / `%d回` / `%d枚` into widgets literally named
          `NULL_tournamentrule_time` / `_round` / `_ticket`. `words[1]`/`words[2]` = SNE
          time/rounds are the pair the panel deliberately skips (rule 4 branches to the empty
          case), and `words[0]` = +0x60 is `level_limit_base`, which is why the per-rule table
          starts at `words[1]` and not `words[0]`.

          Field ids here are **left unrenamed on purpose**: `block_204` is a byte-accounting
          mirror and `mgo2_cmd_4313_s2c.ksy` is canonical. The naming belongs there.
      - id: pair_a8
        size: 2
        doc: |
          [ELF] +0xa8 (block 168), read as a **2-byte raw block**, not a u16 (`0xD5D018` with
          r5=2) — the parser draws no boundary between the two bytes, which is why the
          declaration stays raw. Renamed from `unknown_a8` 2026-08-02.

          The client itself does split them: in the game-details carrier `0x8CA5C0` and `0x8CA5C8`
          load struct `+920` and `+921` as two separate `lbz`, and `0x8CA87C` publishes the pair
          as a 2-byte property-store record, **key 134**. The canonical file names them
          `unique_red` / `unique_blue`; that name is **tier 4 and doubtful**, since unique
          characters were absent from this build's UI and untestable (OBSERVED.md).

          The archived captures argue against reading it as a per-team setting at all: **all 214
          read `00 01`**, never any other combination. A pair of independently chosen team values
          would vary; a constant would not. Meaning [UNKNOWN] — the observed value is not.
      - id: unknown_aa
        type: u2
        doc: |
          [UNKNOWN — meaning] +0xaa (block 170), record offset **234**. Width [ELF] **twice**: u16
          reader `0xD5CC14` at `0xD43A9C`, and `lhz r3,922(r3)` in the dead game-details accessor
          bank at `0x9074B4`. Canonical `unknown_170`; **no name to transfer**.

          One structural note that does carry, because it is about the parser rather than about a
          carrier: that accessor is separate from the indexed getter at `0x907174`, which walks
          `920 + idx` and stops short of 922. So this halfword sits **outside** the `pair_a8` pair
          rather than being a third element of it.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 234 falls outside
          every range they touch — the nearest accesses are `record+228` (the last timer) and `record+274`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          Not carried by `0x4310` or `0x4305`, so no capture of it exists.
      - id: unknown_ac
        type: u4
        doc: |
          [UNKNOWN — meaning] +0xac (block 172), record offset **236**. Width [ELF] **twice**: u32
          reader `0xD5CCD8` at `0xD43AB8`, and `lwz r3,924(r3)` in the dead game-details accessor
          bank at `0x90748C`. Canonical `unknown_172`; no name to transfer.

          **No reader in this carrier** [ELF 2026-08-02]. The record's address is reachable only
          from four functions (census in the type doc above), and record offset 236 falls outside
          every range they touch — the nearest accesses are `record+228` (the last timer) and `record+274`. Controls
          `record+274` and the `record+172..+228` timer run both reproduce.

          This is the field the canonical carrier calls its noisiest offset — struct `+924` appears
          in roughly two dozen unrelated functions there. **None of that noise exists here**, which
          is the practical advantage of a carrier whose base has an enumerable set of holders: the
          question is not "which of these clusters is the right object" but "can this function hold
          the address at all", and for all but four the answer is no.

          Not carried by `0x4310` or `0x4305`, so no capture of it exists.
      - id: common_flags_msb
        type: u1
        doc: |
          [ELF offset+width `0xD43AD4` -> +0xb0 (block 176); name ELF-derived] The **most
          significant byte of the 32-bit Common Settings flags word**. Renamed from `unknown_b0`
          2026-08-02.

          In the game-details carrier the word is the big-endian u32 at struct `+928`, i.e. this
          byte, then `common_ab`, then `common_flags_lsb`: bits 31..24 here, 23..16 =
          `common_ab[0]`, 15..8 = `common_ab[1]`, 7..0 = the lsb byte. 117 sites image-wide do
          `lwz rX,928(rB)` and bit-test the result, and **every tested bit lies in 8..23**, so no
          bit this byte owns is consumed anywhere. The name says what the byte IS; what a set bit
          would mean is [UNKNOWN].

          The bit arithmetic, because it is easy to get backwards: the tests are
          `rldicl. rX,r0,sh,63`, which selects LSB index **`64 - sh`**. The fifteen tests at
          `0x8CA2BC`-`0x8CA420` use `sh` in 41..56, i.e. bits 8..21 and 23. Control: `sh=49` gives
          bit 15, and bit 15 is independently the one the create-game team-kill row sets and clears
          with `ori 32768` / `rlwinm 16,1,31` at `0x8A5FA0`-`0x8A5FAC`.
      - id: common_ab
        size: 2
        doc: |
          [ELF] +0xb1 (block 177), 2-byte raw block. **The two live Common Settings toggle
          bytes** — `common_a` then `common_b` in the canonical file, bits 23..16 and 15..8 of the
          flags word described under `common_flags_msb`. Renamed from `unknown_b1` 2026-08-02.

          The two offsets are capture-proven at `0x4310` wire `0x142`/`0x143`; the individual bits
          are **not** all identified. Kept as one raw 2 because that is how the parser reads it and
          how both the `0x4310` builder and the `0x4302` row builder copy it.

          Archived values: `common_a` is `0x24` in 149 payloads, `0x2c` in 63, `0x25` and `0x34`
          once each; `common_b` is `0x00` in 170 and nonzero in 44. `common_a` bit 0 is the
          idle-kick enable, and the gate is confirmed 214 for 214 — the single payload with
          `common_a = 0x25` is the single payload with a nonzero `idle_kick`.
      - id: common_flags_lsb
        type: u1
        doc: |
          [ELF offset+width `0xD43B10` -> +0xb3 (block 179); name ELF-derived] The **least
          significant byte** (bits 7..0) of that same 32-bit flags word. Renamed from `unknown_b3`
          2026-08-02.

          It has its own u8 read, distinct from the raw-2 covering `common_ab`, and the `0x4310`
          builder splits the same way — so the four-byte word is three separate wire fields, not
          one. **Bits 0..7 are never tested** by any of the 117 flag-word sites, and the only load
          of struct `+931` in the game-details carrier is the dead accessor `0x9072AC`.

          Archived captures read `0x20` in 182 and `0x00` in 32, and that split is **exactly** the
          split of `unknown_48` (block 72) — 214 for 214, the two never disagree. All 26 payloads
          from lobby subtypes 7 and 8 (training) are in the zero group, plus six from subtypes 0
          and 1. So the byte covaries with something about the session while having no reader,
          which is a reason to echo it rather than to invent it. Meaning [UNKNOWN].
      - id: idle_kick
        type: u2
        doc: |
          [ELF offset+width `0xD43B2C` -> +0xb4 (block 180); name INFERRED from capture]
          **The idle-kick threshold, in MINUTES.** Renamed from `unknown_b4` 2026-08-02.

          The unit is read from the binary rather than guessed: in the game-details carrier
          `0x8CA424` loads struct `+932` and `0x8CA458` multiplies it by 60 before `0x8CA63C`
          publishes it as property-store **key 76**. Gated by `common_ab[0]` bit 0, and that gate
          is capture-confirmed 214 for 214 — see `common_ab`.
      - id: team_kill_kick
        type: u2
        doc: |
          [ELF offset+width `0xD43B48` -> +0xb6 (block 182); name INFERRED from capture]
          **Team kills tolerated before a kick.** Renamed from `unknown_b6` 2026-08-02.

          Published as property-store **key 69** at `0x8CA534`/`0x8CA608` — and note the client
          truncates there (`stb` after an `lhz`), so its own downstream copy cannot exceed 255 even
          though the wire field is 16 bits.

          **A gating claim the captures REFUTE, recorded so it is not re-derived.** The
          create-game screen keeps flags-word bit 15 in step with this field —
          `0x8A5F90`-`0x8A5FB0` sets the bit when the count is nonzero and clears it when zero —
          which invites the reading that a clear bit 15 makes a nonzero count inert. It does not.
          170 of the 214 archived `0x4310` payloads carry `common_b = 0x00`, i.e. bit 15 clear,
          **with this field = 3**, and the publisher at `0x8CA534` copies the value out with no bit
          test at all. The invariant is local to that one screen. `mgo2_cmd_4313_s2c.ksy`'s
          "Zeroed when commonB bit 7 is clear" is therefore too strong; its `idle_kick`
          counterpart is not.
      - id: host_ping
        type: u4
        doc: |
          [ELF offset+width `0xD43B64` -> +0xb8 (block 184); name ELF-derived, unit UNKNOWN]
          Renamed from `unknown_b8` 2026-08-02. **Not carried by `0x4310` or `0x4305`**, so this
          family, `0x4313` and `0x43F1` are the only ways to set it and no archived capture of it
          exists.

          In the game-details carrier the hosted-game row synthesiser `0xD493CC` does
          `lwz r0,936(r31)` at `0xD49548` and stores the result at the row's `T+0x20`, which
          `mgo2_cmd_4302_s2c.ksy` calls `ping` and which the game picker at
          `0x934574`-`0x934590` buckets against 20 and 80, preferring lower. **What is proven is
          the destination slot, not a unit**, and whether a tournament record ever reaches that
          synthesiser is not claimed.
      - id: capture_extra_time
        type: u1
        doc: |
          [ELF offset+width `0xD43B80` -> +0xbc (block 188); name CONFIRMED from disc strings]
          **Capture Mission "EXTRA TIME"** — extend the round until a victor emerges. Renamed from
          `unknown_bc` 2026-08-02.

          A plain toggle: handler `0x8A02B4` is `x = x ? 0 : 1`, drawn as disc string 33 "ON" / 34
          "OFF", row label 507 "EXTRA TIME" under header 498 "Capture Mission", help 541
          *"Enabling this adds extra time to the end of the round until a victor emerges."*
          Published as property-store key 132. Archived payloads read 0 in 207 and 1 in 7.
      - id: sneaking_snake_kills
        type: u1
        doc: |
          [ELF offset+width `0xD43B9C` -> +0xbd (block 189); name CONFIRMED from disc strings]
          **Sneaking Mission "SNAKE"** — how many times Snake must be defeated for Red and Blue to
          win. Renamed from `unknown_bd` 2026-08-02.

          It is a count, not a side index: `0x89D7B8` renders it as a number and the create-game
          adjuster `0x8A1AC8` clamps it to [1,5], where a side would be 0/1/2 drawn as a name. Disc
          row label 508 "SNAKE", units 520 "times", help 542 *"Set the number of times Snake must
          be defeated (victory condition for Red and Blue Teams)."* Published as property-store key
          131. Archived payloads read 3 (175), 5 (17), 2 (13) and 1 (9).

          It is deliberately **not** in the `words` timer array — Sneaking shows three settings and
          owns only two slots there; this is the third.
      - id: unread_tail
        size: 14
        doc: |
          [ELF] +0xbe (block 190..203), 14-byte raw block; ends the 204-byte block at +0xcc.
          Renamed from `unknown_be` 2026-08-02, matching the canonical file.

          **One raw read, so the parser draws no field boundaries inside it at all.** In the
          game-details carrier the client never reads or writes any byte of it: three touch points
          image-wide — the `0x4310` builder emitting it, the `0x4305` parser reading it, and the
          create-game initialiser memsetting it to zero at `0x89B5E8`. All 214 archived payloads
          carry it entirely zero.

          PROTOCOL.md's subdivision of this region — byte-sized timers for Stealth DM, Interval,
          Solo Capture and Race, a flag and four zeros — is a reference-server reading naming modes
          whose strings **do not exist on this disc**, and is not adopted. Splitting it needs live
          divergence testing, which no available build can perform for a `0x4909` record.
  triple:
    seq:
      - id: a
        type: u1
        doc: "[UNKNOWN] -> array A[i] at block+0x00+i."
      - id: b
        type: u1
        doc: |
          -> array B[i] at block+0x10+i. `mgo2_cmd_4313_s2c.ksy` calls this `rotation_round.map`
          and marks the id-to-map-name table [INFERRED], tier 4.

          **The table is tier 1 as of 2026-08-02.** The tournament panel `0x901808` walks
          `record+80 = block+0x10` for seven iterations (`r26 = r22+80` at 0x901F4C,
          `lbz r29,0(r26)`, `addi r26,r26,1`, bound `cmpwi r31,24` at 0x902138), skips zero
          entries, and for the rest calls `strres(0x654515, B[i] + 74)` (`addi r29,r29,74`,
          `bl 0x8E0BF0` at 0x902010/0x90205C). Ids 75..89 of that set are `JNGL, A.A., U.U.,
          G.G., B.TOWN, L.D, B.B., UNDER, CLOCK, N.SILO, M.DEPO, M.M., SANO, S.A, SHOP`; the long
          forms at `B[i] + 59` are ids 60..74, `Jungle` .. `Shopping Mall`. So map ids are
          **1-based, 1..15, and 0 means "empty slot"** — the client's own bound, not an inference
          from the table's length. (The panel renders only the first 7 of the 16 rotation slots;
          that is a property of this screen, not of the field.)

          Left unrenamed here on purpose: this type is a mirror, and
          `mgo2_cmd_4313_s2c.ksy` is canonical.
      - id: c
        type: u1
        doc: "[UNKNOWN] -> array C[i] at block+0x20+i."
