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
  (60 vs 28, 48 bare vs 24) for a purely editorial reason: this file inlines a mirror of the
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
  reply (OBSERVED.md). `block_204` below is retained only as a byte-accounting mirror; where the
  two disagree, 0x4313 wins. Whether the game-settings *semantics* apply to a 0x4909 record is
  [UNKNOWN] — the byte boundaries are not.

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
      **Canonical model: `mgo2_cmd_4313_s2c.ksy` type `game_settings`** — this is a mirror kept
      for byte accounting only. Offsets below are
      relative to the block's own destination. The leading section is **interleaved on the
      wire**: 16 iterations of {u8 -> +0x00+i, u8 -> +0x10+i, u8 -> +0x20+i}, so the wire
      order is triple(0), triple(1) ... triple(15) while the struct holds three 16-byte
      arrays. Every field's meaning is [UNKNOWN]; only positions and widths are established.
    seq:
      - id: triples
        type: triple
        repeat: expr
        repeat-expr: 16
        doc: "[ELF 0xd43678-0xd436e4] 16 wire triples scattering into three 16-byte arrays at +0x00/+0x10/+0x20."
      - id: unknown_30
        type: u1
        doc: "[UNKNOWN] +0x30."
      - id: unknown_31
        type: u1
        doc: "[UNKNOWN] +0x31."
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
      - id: unknown_42
        type: u1
        doc: "[UNKNOWN] +0x42."
      - id: unknown_43
        type: u1
        doc: "[UNKNOWN] +0x43."
      - id: unknown_44
        type: u4
        doc: "[UNKNOWN] +0x44."
      - id: unknown_48
        type: u4
        doc: "[UNKNOWN] +0x48."
      - id: unknown_4c
        type: u4
        doc: "[UNKNOWN] +0x4c."
      - id: unknown_50
        type: u2
        doc: "[UNKNOWN] +0x50."
      - id: unknown_52
        type: u2
        doc: "[UNKNOWN] +0x52."
      - id: unknown_54
        type: u4
        doc: "[UNKNOWN] +0x54."
      - id: unknown_58
        type: u4
        doc: "[UNKNOWN] +0x58."
      - id: unknown_5c
        type: u2
        doc: "[UNKNOWN] +0x5c."
      - id: unknown_5e
        type: u1
        doc: "[UNKNOWN] +0x5e."
      - id: unknown_5f
        type: u1
        doc: "[UNKNOWN] +0x5f."
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
      - id: unknown_a8
        size: 2
        doc: "[UNKNOWN] +0xa8, read as a 2-byte raw block (not a u16 — 0xD5D018 with r5=2)."
      - id: unknown_aa
        type: u2
        doc: "[UNKNOWN] +0xaa."
      - id: unknown_ac
        type: u4
        doc: "[UNKNOWN] +0xac."
      - id: unknown_b0
        type: u1
        doc: "[UNKNOWN] +0xb0."
      - id: unknown_b1
        size: 2
        doc: "[UNKNOWN] +0xb1, 2-byte raw block."
      - id: unknown_b3
        type: u1
        doc: "[UNKNOWN] +0xb3."
      - id: unknown_b4
        type: u2
        doc: "[UNKNOWN] +0xb4."
      - id: unknown_b6
        type: u2
        doc: "[UNKNOWN] +0xb6."
      - id: unknown_b8
        type: u4
        doc: "[UNKNOWN] +0xb8."
      - id: unknown_bc
        type: u1
        doc: "[UNKNOWN] +0xbc."
      - id: unknown_bd
        type: u1
        doc: "[UNKNOWN] +0xbd."
      - id: unknown_be
        size: 14
        doc: "[UNKNOWN] +0xbe, 14-byte raw block; ends the 204-byte block at +0xcc."
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
