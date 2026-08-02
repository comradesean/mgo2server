meta:
  id: mgo2_cmd_4905_s2c
  title: "MGO2 0x4905 — TOURNAMENT detail reply, 867 bytes (server -> client)"
  endian: be
doc: |
  **WHAT THIS IS — IDENTIFIED 2026-08-02, tier 1.** This is the **tournament detail record**: the
  payload behind the *RULE DETAIL* panel of the tournament-select screen. The client says so in
  its own words. The one function that renders this record, `0x901808`, drives three widgets whose
  GCX names are string literals in its own pool at `0xE12E48` / `0xE12E70` / `0xE12E98`:

      NULL_tournamentrule_time      NULL_tournamentrule_round      NULL_tournamentrule_ticket

  and the same pool carries `obj_tournament_select` (`0xE12D50`), `tournament_select_loop`
  (`0xE12D80`) and the panel caption `RULE DETAIL` (`0xE12E20`). The three value formats are
  `%d分` (`0xE12E40`), `%d回` (`0xE12E68`) and `%d枚` (`0xE12E98`-1 → `0xE12E90`) — minutes, rounds,
  tickets. Nothing about the identification is inferred from another server or from a neighbouring
  packet's field names.

  Consistent with that, `0x4904`'s sender `0xD47AFC` stores its one `detail_id` argument at
  `q+0x26D04` (`stw r0,27908(r9)` at `0xD47BD8`, `q = *(session+0x11904)`), and this parser
  refuses the reply unless the wire echo matches it (`lwz r9,27908(r9)` / `cmpw` / `bne` at
  `0xD48204`-`0xD4820C`). The write and the check are the only two references to that word in the
  binary; `0xD34668` is the third and it is the reset.

  **NOT SERVED IN V1.** Tournament lobbies are Ver. 1.20 content (CLAUDE.md "Target version"), so
  the server neither sends `0x4905` nor `0x4909`. Mapping is in scope; building is not. Because
  no available client build exercises this family, **nothing here is or can be capture-backed** —
  every claim below is tier 1 (read from `MGO2.elf`) and **cannot reach tier 2**. Do not read the
  `[ELF ...]` tags as "confirmed against a client".

  **0x4905 AND 0x4909 ARE ONE RECORD.** Both parsers memset and fill the SAME 912-byte
  destination at `session+0xD598` — `addi r0,r28,-10856` at `0xD48218` here and at `0xD4873C` in
  `0x4909`'s parser, with `r28 = session+0x10000` in both. Field for field, width for width, wire
  offset for wire offset, the two bodies are **identical**; the two parsers differ only in
  (a) the request-status slot they complete — 57 here, 58 there — and (b) this one's `detail_id`
  echo check, which `0x4909` has no equivalent of. `0x4909` is therefore **not** a superset:
  its `.ksy` merely lists more *fields* because it inlines a mirror of the shared 204-byte block
  that this file keeps opaque. See `mgo2_cmd_4909_s2c.ksy` for the same map.

  THE STRUCT, OFFSET BY OFFSET (`session+0xD598`, 912 = 0x390 bytes). "reader" means a site in
  `MGO2.elf` that loads the destination byte; see the closure argument below.

      +0x000  u32   detail_id, echoed          no reader (checked pre-store, then dead)
      +0x004  u8    -                          no reader
      +0x005  u8    RULE (0..7)                READ 0x9019C8, 0x901A14, 0x901A6C
      +0x006  u8    -                          no reader
      +0x007  u8    flags, bit-reversed        no reader
      +0x008  u16   -                          no reader
      +0x00A  [16]  -                          no reader
      +0x020  u64   - (u32 widened)            no reader
      +0x028  u64   - (u32 widened)            no reader
      +0x030  u64   - (u32 widened)            no reader
      +0x038  u64   - (u32 widened)            no reader
      +0x040  [204] shared game_settings       READ at +0x50 and +0xAC..+0xE4 (see nested_block)
      +0x10C  u16   -                          no reader
      +0x10E  u16   -                          no reader
      +0x110  u16   -                          no reader
      +0x112  u16   MAX PARTICIPANTS           READ 0x8C31F0 (disc string 731)
      +0x114  u32   -                          no reader
      +0x118  [64]  TOURNAMENT TITLE text      READ 0x9018E4, 0x901920
      +0x159  [512] -                          no reader
      +0x364  u32   -                          no reader
      +0x368  u32   -                          no reader
      +0x36C  u32   -                          no reader
      +0x370  u32   -                          no reader
      +0x374  u32   -                          no reader
      +0x378  u64   - (u32 widened)            no reader
      +0x380  u64   - (u32 widened)            no reader
      +0x388  u8    -                          no reader

  **WHY THE "no reader" ROWS ARE CLAIMS AND NOT BLANKS.** Three sweeps, each exhaustive, and one
  control:

  1. *Who can produce the base?* A sweep of every D-form instruction in `0x10230`-`0xDE9328`
     (opcodes 14/32/34/36/38/40/42/44/58/62, `rA != 0`) for a displacement anywhere in
     `[-10856, -9945]` — the struct's whole 912-byte span expressed in the `addis rX,rX,1` /
     negative-displacement idiom — returns **78 instructions and no others**. Every one is either
     the two parsers writing fields, or `0xD47488`. Both edges are justified: `-10856` is
     `+0x000`, `-9945` is `+0x38F`, the last byte of the 912. (The 33-strong `-9998` cluster in
     that output is a different idiom entirely — `addis r9,r9,N` + `addi r9,r9,-9998` building
     data pointers in `0x30xxxx`-`0x54xxxx`, nowhere near the session block.)
  2. *So the only accessor is `0xD47478`* — `if (r3) return r3 + 0x10000 - 10856;` — and its call
     sites are enumerable. Decoding every branch in the same range (opcode 18 `b/bl/ba/bla` and
     opcode 16 `bc`, absolute and relative forms both) targeting `0xD47478` yields exactly
     **two `bl`, zero `b`, zero `bc`**: `0x8C31D8` and `0x901858`. Its OPD descriptor is at
     `0x1029880` (`func=0xD47478, toc=0x10353A8`) and the only occurrence of that value in the
     file is at `0xC27605` — **unaligned**, therefore a coincidental byte match and not a
     function-pointer table entry. (Per the standing rule, the unreferenced descriptor is not
     offered as proof on its own; the branch sweep is the proof.)
  3. *Does the pointer escape?* At `0x8C31D8` the result lives in `r9`, is used once
     (`lhz r29,274(r9)`), and is never passed on. At `0x901858` it lives in `r31`/`r22`; the only
     value derived from it that leaves the function is `r27 = r31+280` at `0x901878`, passed as
     the text argument to the widget setter `0x246EC0`. Neither function stores the record
     pointer anywhere; the `std r22/r27/r31,...(r1)` in `0x901808`'s prologue are callee-saved
     spills.

  **Control.** The sweep must find the one reader that was already known — `0x8C31F0`, which loads
  `struct+0x112` as the second `%d` of disc string 731, "Number of Players Currently Joined:
  %d / %d". It does: `0x8C31F0` sits four instructions after call site 1. A sweep that missed it
  would be broken, and this one does not.

  Together: the destination is written only by the two parsers, is reached only through
  `0xD47478`, `0xD47478` is called only twice, and the pointer escapes neither caller. The reader
  set is **closed**, so "no reader" here is an exhaustive negative and not an absence of effort.

  **WHAT THE RECORD IS NOT.** It does **not** embed a lobby descriptor, and it does **not** carry
  the team record's tournament/entry-fee trailer. The two structs are *adjacent but disjoint*, and
  the accessors prove it arithmetically: `0xD47478` returns `session + 0x10000 - 10856` =
  `session+0xD598`, and the team record's accessor `0xD491F8` returns `session + 0x10000 - 9944`
  = `session+0xD928`. `0xD598 + 912 = 0xD928` exactly — this record ends on the byte the 680-byte
  team record begins. No offset of one can therefore coincide with an offset of the other, and
  the team trailer's `+0x25C` lobby_id / `+0x260` subtype / `+0x298` tournament_id / `+0x2A4`
  entry_fee are fields of *that* object. The hub/lobby list at `ctx+0xB790` is a third base again
  and shares no pointer with either. The one thing this record genuinely does embed is the
  204-byte `game_settings` block, and that is proved the right way: the shared reader `0xD4364C`
  is handed `struct+0x40` as its destination (`0xD4842C`).

  Parser 0xD4812C (338 instructions, ends 0xD48670), reached from the GAME dispatcher 0xD387C8 (compare tree at 0xD38804) via the
  stub at 0xD395C8. COMMANDS.md files 0x4905 under "0x49xx (0x4905–0x49C3) clan / GHQ / roster",
  parsed but never sent; neither PROTOCOL.md nor OBSERVED.md mentions it. Its request is one of
  the 0x4904–0x49C2 send-side gaps.

  This is a LARGE single-record reply — 867 bytes — not a result single. It is also the only id in
  this batch that calls a *shared* sub-record reader, so the layout below is in two parts.

  PRECONDITIONS AND GATES, in parser order:
    * header id check, cmpwi 0x4905 at 0xD4817C;
    * 0xD32E3C is called and its result compared with 1 (0xD48198) — a transaction-state
      precondition, not a wire field;
    * reader open 0xD5C844 (0xD481A4);
    * u32 result (0xD5CC64 at 0xD481B4). NONZERO branches to 0xD48604 and reads nothing more;
    * u32 (0xD5CCD8 at 0xD481D8). If the context object exists, this value must EQUAL the u32 at
      ctx+0x6D04 or the parser bails to 0xD4863C (0xD481FC–0xD4820C) — an echo of an id the
      client already holds, so it cannot be chosen freely by the server;
    * the 912-byte destination struct is memset to 0 (0xD48228) and the u32 above is stored at
      its offset 0 WITHOUT being re-read from the wire.
  On completion: status setter 0xD32E08 and result setter 0xD32E70, both on subsystem index
  0x39 (57) — 0xD48620 and 0xD48634.

  TOTAL WIRE LENGTH 867 BYTES (0x363): 46 before the nested block, **204** in it, 617 after.

  **CORRECTION (2026-07-26, re-derived from the ELF).** An earlier revision of this file called
  0xD4364C "a straight-line reader — no loop, no back-edge — of 48 fields totalling 159 wire
  bytes", and gave the total as 822. That was wrong and it was wire-breaking. The reader **does**
  loop: the back-edge is `bne cr6,0xd43678` at **0xD436E4** with bound `cmpdi cr6,r27,16` at
  **0xD436D8**. Sixteen iterations of three u8 reads (0xD4368C / 0xD436B0 / 0xD436D0) consume
  **48** wire bytes, not 3, so the block is **204 wire bytes** — identical to its 204-byte
  destination region, which is the independent check. 867 − 822 = 45 = 48 − 3, and every field
  after wire +0x2E moves 45 bytes later. Their offsets below were re-derived from the parser's
  own destination offsets (0xD4845C..0xD485F4), not obtained by adding 45.

  THE 204-BYTE NESTED BLOCK. At wire +0x2E the parser calls 0xD4364C (0xD48440) with a pointer to
  struct+0x40. That block is **not** private to 0x4905: 0xD4364C has **nine** call sites —
  0xD445A4 (0x4313), 0xD48440 (here), 0xD48964 (0x4909), 0xD4B244 (0x4987), 0xD4CB08 (0x4950),
  0xD5006C (the shared 0x4A24/0x4A31 parser), 0xD51014 (0x4A00), 0xD5AF38 (0x4E10) and
  0xD5B78C (0x43F1). "Shared" is therefore [ELF], not [INFERRED].

  **The block is modelled once, canonically, in `mgo2_cmd_4313_s2c.ksy` as type
  `game_settings`** — the best-evidenced copy, because 0x4313's is the one whose field names are
  backed by live capture (the 0x4310 push and the 0x4305 reply; see OBSERVED.md). It is kept
  opaque here so the two cannot drift. Whether the *semantics* of the game-settings block apply
  to a 0x4905 record is [UNKNOWN]; the 204 wire bytes and their internal boundaries are not.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CEB0 loop test.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: result
    type: u4
    doc: |
      [ELF 0xD481B4] Nonzero → the parser stops here (branch at 0xD481CC), so the packet is
      4 bytes. Zero → the full 867-byte body follows.
  - id: detail_id
    type: u4
    doc: |
      [ELF 0xD481D8] **The tournament id, echoed.** Must equal the u32 the client stashed when it
      sent 0x4904, or the whole packet is discarded (0xD4820C). **Identified 2026-08-02**: the
      0x4904 sender 0xD47AFC writes its single argument to `q+0x26D04` at 0xD47BD8, and this
      parser reads that same word back at 0xD48204 (`q = *(session+0x11904)`, then the
      `addis r9,r9,2` / +27908 idiom). Those two, plus the reset at 0xD34668, are the only three
      references to the word in the binary — so the check is a request/reply pairing check and
      nothing else. The correct server behaviour is to echo whatever the 0x4904 request carried.

      An earlier revision of this file said "ctx+0x6D04"; the `addis r9,r9,2` was dropped, so the
      true offset is **+0x26D04**.

      Stored at struct+0x000 after the check. **No reader** — the value is dead once stored (see
      the closure argument in the top-level doc). The screen keeps its own copy in the widget
      object it passed to 0x4904.
  - id: unknown_0x08
    type: u1
    doc: |
      [UNKNOWN — meaning] → struct+0x004. Width and position [ELF 0xD48244].
      **No reader** (exhaustive; top-level doc). Note it sits immediately before the rule byte and
      is one of four consecutive u8 the parser reads as separate calls, so the grouping is the
      parser's, not a guess.
  - id: rule
    type: u1
    doc: |
      [ELF 0xD48260] → struct+0x005. **The tournament's game rule.** Identified 2026-08-02 from
      three independent reads in the RULE DETAIL panel `0x901808`:

        * `0x9019C8` / `0x901A14` — `lbz r3,5(r31)`, `addi r3,r3,22`, `bl 0x8E0BF0`. `0x8E0BF0` is
          the disc-string getter for group hash **0x654515** (`lis r3,101; ori r3,r3,17685`), the
          rule/map master list (`$strres:0`-`$strres:341`; AUTOMATCH.md §10). Ids 22..29 of that
          set are **`DM`, `TDM`, `RES`, `CAP`, `SNE`, `BASE`, `BOMB`, `TSNE`** — so
          `rule + 22` names the mode and the enum is
          `0=Deathmatch 1=Team Deathmatch 2=Rescue 3=Capture 4=Sneaking 5=Base 6=BOMB
          7=Team Sneaking`. The long-form list at `2*rule` (ids 0,2,4,...,14) agrees exactly.
          The value is rendered into the panel's rule widget (slot `r23+120`) twice, as text and
          shadow.
        * `0x901A6C` — `lbz r0,5(r31)`, `cmplwi 7`, `bgt` to the empty case, then an 8-way jump
          table at `0x901A90`. So the client itself bounds the field to **0..7** and treats
          anything above 7 as "no timers". That is a tier-1 range, not an inference from the
          string table's length.

      Same enum as the team record's `+0x261` and as `0x4310`'s rotation rule — but that is
      **enum identity, not offset identity**: the two live in different structs (see the top-level
      doc) and nothing here should be inferred from the team record's neighbouring fields.
  - id: unknown_0x0a
    type: u1
    doc: |
      [UNKNOWN — meaning] → struct+0x006. Width and position [ELF 0xD4827C].
      **No reader** (exhaustive; top-level doc).
  - id: flags
    type: u1
    doc: |
      [UNKNOWN] A bit field: read as a 1-byte block (0xD5D018 r5=1 at 0xD48298) into a temp, then
      all 8 bits are expanded one at a time into a 64-bit word at struct+0x00 by the chain
      0xD482A4–0xD48368 (ori 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, then the sign bit as 0x01).
      Each bit is therefore a distinct boolean, exactly as in the 0x4902 entry.

      **No reader** for any of the eight bits (exhaustive; top-level doc). Note the expansion uses
      `ld`/`std` on the 64-bit word at struct+0x000, which lands the bits in the *low* byte —
      struct+0x007 — and leaves struct+0x000..0x006 (detail_id and the three u8) untouched. So the
      wire byte's fate is struct+0x007, bit-reversed.
  - id: unknown_0x0c
    type: u2
    doc: |
      [UNKNOWN — meaning] → struct+0x008. Width and position [ELF 0xD4837C].
      **No reader** (exhaustive; top-level doc).
  - id: unknown_0x0e
    size: 16
    doc: |
      [UNKNOWN — meaning] 16-byte block (0xD5D018 r5=16) → struct+0x00A; NUL-terminated on store,
      so name-shaped by width. [ELF 0xD4839C]

      **No reader** (exhaustive; top-level doc), which is the interesting part: the tournament's
      *displayed* title is the 64-byte block at struct+0x118, not this. A 16-byte name that no
      code loads is most likely a short/internal key, but that is a guess and is not offered as a
      finding.
  - id: unknown_0x1e
    type: u4
    doc: |
      [UNKNOWN — meaning] widened to 64 bits at struct+0x020 (std at 0xD483D8) — the time_t-shaped
      widening. [ELF 0xD483BC] **No reader** (exhaustive; top-level doc).

      Four consecutive u32-widened-to-u64 in a tournament record are the obvious place for
      open/close/start/end timestamps, and the widening is exactly what this build does elsewhere
      for time_t. That is **a lead, not a finding**: no reader exists to name any of them, and
      nothing in the ELF distinguishes the four from each other.
  - id: unknown_0x22
    type: u4
    doc: |
      [UNKNOWN — meaning] widened to 64 bits at struct+0x028. [ELF 0xD483DC]
      **No reader** (exhaustive; top-level doc). See `unknown_0x1e`.
  - id: unknown_0x26
    type: u4
    doc: |
      [UNKNOWN — meaning] widened to 64 bits at struct+0x030. [ELF 0xD483FC]
      **No reader** (exhaustive; top-level doc). See `unknown_0x1e`.
  - id: unknown_0x2a
    type: u4
    doc: |
      [UNKNOWN — meaning] widened to 64 bits at struct+0x038. [ELF 0xD4841C]
      **No reader** (exhaustive; top-level doc). See `unknown_0x1e`.
  - id: nested_block
    size: 204
    doc: |
      [ELF 0xD48440] 204 bytes read by the shared reader 0xD4364C into struct+0x40. Layout is
      modelled once in `mgo2_cmd_4313_s2c.ksy`, type `game_settings`; kept opaque here so the
      copies cannot drift. Note the leading 48 bytes are **interleaved**: 16 wire triples
      {u8 -> block+i, u8 -> block+0x10+i, u8 -> block+0x20+i}, not three contiguous runs.

      **This is the one thing the record provably embeds**, and the proof is the destination
      argument, not an offset coincidence: 0xD4364C is handed `struct+0x40` at 0xD4842C.

      **Two regions of it are read by the tournament panel `0x901808`** (2026-08-02) — worth
      recording here because they are read *through this record's base*, and because they
      corroborate `mgo2_cmd_4313_s2c.ksy` from a function that has nothing to do with 0x4310:

        * **block+0x10..+0x16** — `r26 = record+80` at `0x901F4C`, then `lbz r29,0(r26)` with
          `r26++` for seven iterations (`cmpwi r31,24` / `addi r31,r31,4` at 0x902138-0x902144).
          `record+80 = block+0x10`, i.e. `rotation_round.map[0..6]`. Zero hides the widget;
          otherwise the name is `strres(0x654515, map + 74)` (`addi r29,r29,74`, `bl 0x8E0BF0`,
          at 0x902010/0x90205C). Set ids 75..89 are `JNGL, A.A., U.U., G.G., B.TOWN, L.D, B.B.,
          UNDER, CLOCK, N.SILO, M.DEPO, M.M., SANO, S.A, SHOP`; the long forms at `map + 59` are
          ids 60..74, `Jungle` .. `Shopping Mall`. So map ids are **1-based, 1..15, 0 = empty**.
          The panel shows the first **7** of the 16 rotation slots.
        * **block+0x6C..+0xA4** — the per-rule timer table, selected by the 8-way jump table at
          `0x901A90` on `record+5` (the `rule` field above). Each case loads a time into r29, a
          round count into r25 and a ticket count into r26; those three are then formatted with
          `%d分` / `%d回` / `%d枚` into the widgets named `NULL_tournamentrule_time` /
          `_round` / `_ticket`. Record offsets, and their `rule_timers[]` indices in
          `mgo2_cmd_4313_s2c.ksy` (block base = record+0x40, `rule_timers[0]` = block+100 =
          record+164):

              rule 0  DM    time=+200 (idx 9)   tickets=+204 (idx 10)   no rounds
              rule 1  TDM   time=+188 (idx 6)   rounds=+192 (idx 7)     tickets=+196 (idx 8)
              rule 2  RES   time=+180 (idx 4)   rounds=+184 (idx 5)
              rule 3  CAP   time=+172 (idx 2)   rounds=+176 (idx 3)
              rule 4  SNE   nothing displayed   (its slots, idx 0/1, are the ones skipped)
              rule 5  BASE  time=+208 (idx 11)  rounds=+212 (idx 12)
              rule 6  BOMB  time=+216 (idx 13)  rounds=+220 (idx 14)
              rule 7  TSNE  time=+224 (idx 15)  rounds=+228 (idx 16)

          That reproduces `mgo2_cmd_4313_s2c.ksy`'s stated ordering — "SNE t/r, CAP t/r, RES t/r,
          TDM t/r/tickets, DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r" — **exactly, slot for
          slot**, from a completely independent site, and it does so with the client's own widget
          names attached to time / round / ticket rather than with an argument from which values
          get multiplied by 60.
  - id: unknown_0xfa
    type: u2
    doc: |
      [UNKNOWN — meaning] -> struct+0x10C. [ELF 0xD4845C]
      **No reader** (exhaustive; top-level doc).
  - id: unknown_0xfc
    type: u2
    doc: |
      [UNKNOWN — meaning] -> struct+0x10E. [ELF 0xD48478]
      **No reader** (exhaustive; top-level doc).
  - id: unknown_0xfe
    type: u2
    doc: |
      [UNKNOWN — meaning] -> struct+0x110. [ELF 0xD48494]
      **No reader** (exhaustive; top-level doc). It is the u16 immediately before
      `max_participants`, and a current-participants counter would be the obvious partner — but
      the client does **not** use it that way: the "currently joined" numerator in disc string 731
      is counted at 0x8C3190-0x8C31C8 by walking eight 28-byte roster slots in the *team* record
      (`0xD491F8`, `lwz r0,380(r9)`), not read from this struct. So that reading is refuted, not
      merely unproven.
  - id: max_participants
    type: u2
    doc: |
      [ELF 0xD484B0] -> struct+0x112. **Maximum participant count.** Read at **0x8C31F0**
      (`lhz r29,274(r9)`, r9 = `0xD47478(session)`) and passed as the **second** `%d` of disc
      string **731**, "Number of Players Currently Joined: %d / %d" (`li r3,731`, `bl 0x8E0C24`
      — the getter for group hash 0xF914BF, the online-lobby set — then `bl 0xDD0688` with
      `r5 = count`, `r6 = this`). The first `%d` is *not* from this record: it is computed at
      0x8C3190-0x8C31C8 by counting the non-zero of eight 28-byte roster slots at `+380` in the
      team record from `0xD491F8`. So this field is the denominator only.

      This is also the **control** for every negative claim in this file: any sweep that cannot
      find 0x8C31F0 is broken.
  - id: unknown_0x102
    type: u4
    doc: |
      [UNKNOWN — meaning] -> struct+0x114. [ELF 0xD484CC]
      **No reader** (exhaustive; top-level doc).
  - id: title
    size: 64
    doc: |
      [ELF 0xD484EC] 64-byte block (0xD5D018 r5=64) -> struct+0x118. **The tournament's displayed
      title.** Identified 2026-08-02: `0x901878` forms `r27 = record + 280` (280 = 0x118) and
      passes it as the text argument (`r5`) to the widget setter `0x246EC0` twice — at 0x9018F0
      and 0x901928 — into the two children of the panel's title widget (`r23+116`), the text and
      its shadow. It is handed to the setter **raw**, with no `strres` lookup and no formatting,
      so the bytes are displayed as-is; the encoding is whatever the UI layer assumes and is
      **[UNKNOWN]** here (0x4909's copy of this field is declared `str` with ISO-8859-1, which is
      an assumption inherited from other text fields, not something this call site establishes).
  - id: unknown_0x146
    size: 512
    doc: |
      [UNKNOWN — meaning] 512-byte block (0xD5D018 r5=512) -> struct+0x159 — note the destination
      jumps one byte past the 64-byte block's NUL at struct+0x158. The single largest field in the
      lobby protocol. [ELF 0xD4850C]

      **No reader** (exhaustive; top-level doc), and this one is a genuine surprise worth stating
      plainly: a 512-byte field in a tournament record is description-shaped, but the RULE DETAIL
      panel does not load it and neither does anything else in the binary. Either the description
      is rendered from the stage script rather than the ELF, or this build shipped the field
      without the screen that shows it. Distinguishing those two needs the lobby `.gcx`, not the
      disassembler, and has not been done.
  - id: unknown_0x346
    type: u4
    doc: |
      [UNKNOWN — meaning] -> struct+0x364. [ELF 0xD48528] **No reader** (exhaustive; top-level
      doc). This and the seven fields below form a 44-byte trailer that nothing in the binary
      reads. It is **not** the team record's `+0x25C..+0x2A4` lobby/tournament/entry-fee trailer:
      that trailer belongs to a different struct which begins at `session+0xD928`, exactly where
      this one ends (see the top-level doc). The resemblance is in shape only and no offset
      bijection exists between them.
  - id: unknown_0x34a
    type: u4
    doc: |
      [UNKNOWN — meaning] -> struct+0x368. [ELF 0xD48544]
      **No reader** (exhaustive; top-level doc). See `unknown_0x346`.
  - id: unknown_0x34e
    type: u4
    doc: |
      [UNKNOWN — meaning] -> struct+0x36C. [ELF 0xD48560]
      **No reader** (exhaustive; top-level doc). See `unknown_0x346`.
  - id: unknown_0x352
    type: u4
    doc: |
      [UNKNOWN — meaning] -> struct+0x370. [ELF 0xD4857C]
      **No reader** (exhaustive; top-level doc). See `unknown_0x346`.
  - id: unknown_0x356
    type: u4
    doc: |
      [UNKNOWN — meaning] -> struct+0x374. [ELF 0xD48598]
      **No reader** (exhaustive; top-level doc). See `unknown_0x346`.
  - id: unknown_0x35a
    type: u4
    doc: |
      [UNKNOWN — meaning] widened to 64 bits at struct+0x378 (std at 0xD485CC). [ELF 0xD485B0]
      **No reader** (exhaustive; top-level doc). The 64-bit widening is the same time_t-shaped
      pattern as struct+0x020..+0x038; same lead, same lack of a reader to confirm it.
  - id: unknown_0x35e
    type: u4
    doc: |
      [UNKNOWN — meaning] widened to 64 bits at struct+0x380 (std at 0xD485F0). [ELF 0xD485D0]
      **No reader** (exhaustive; top-level doc). See `unknown_0x35a`.
  - id: unknown_0x362
    type: u1
    doc: |
      [UNKNOWN — meaning] last byte of the 867 -> struct+0x388. [ELF 0xD485F4]
      **No reader** (exhaustive; top-level doc). The 912-byte destination runs to +0x38F, so
      struct+0x389..+0x38F are memset-zero padding the wire never reaches.
