meta:
  id: mgo2_cmd_4305_s2c
  title: "MGO2 0x4305 — server -> client: saved host settings (reply to 0x4304)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4305` at `0xD38948` -> stub `0xD391D0` ->
  parser **`0xD4548C`**. Request-status slot **34**. The only payload this server Blowfish-
  **encrypts** outbound (PROTOCOL.md: `ENCRYPT_COMMANDS = { 0x4305 }`).

  **Total payload: 348 bytes (`0x15C`).** This contradicts PROTOCOL.md, which gives
  "`0x163` populated" (355). `0x163` is the length of the reference server's structure, one
  tier below the binary; the parser's own read sequence consumes `0x15C` and stops. The seven
  extra bytes are harmless — the reader is cursor-based and never looks at them — so nothing
  is broken today, but 348 is the number the client actually defines.

  **What the structure is.** After a 166-byte header (result, name, comment, and three fields
  around a 16-byte string), the parser reads the **same settings structure as `0x4313`**
  (`0xD4364C`, 204 bytes) — but inlined here rather than called, and with **eight fields
  omitted**. Every destination offset matches `0x4313`'s block layout, which is how the
  correspondence is established, so the omissions are exact:

  | omitted | 0x4313 block off | what PROTOCOL.md calls it |
  | --- | --- | --- |
  | u8 | +67 | current player count |
  | u32 | +76 | one of the seven unknowns at 0x0f0 |
  | u16 | +82 | " |
  | u32 | +88 | " |
  | u16 | +170 | unknown before commonA |
  | u32 | +172 | " |
  | u8 | +176 | " |
  | u32 | +184 | echo's verbatim 0x2e |

  Dropping the **current player count** is the tell that this is genuinely a saved-settings
  reply and not a game snapshot: it is the block's only live-session field, and it is the only
  named field removed.

  This corroborates PROTOCOL.md's account of the shape ("the subtype byte is dropped, two
  constants are inserted (`0x02` at `0x0ED`, `0x20` at `0x147`) and every offset is re-based").
  Both injected constants land on real fields: wire `0x0ED` is the u32 at block +72, and wire
  `0x147` is the u8 at block +179 — the two slots `0x4313`'s block leaves unnamed. That the
  next `0x4310` push returned them at the corresponding request offsets is the live proof that
  the client stores these positions (OBSERVED.md, "Where the Common Settings toggles live").

  **Caveat on the empty path.** PROTOCOL.md says a host with nothing saved gets 128 zero
  bytes. The parser reads 348 regardless: `result` gates only the *rest* of the read
  (nonzero -> skip everything), so with result 0 and a 128-byte payload the remaining 220
  bytes come out of stale receive-buffer content — the primitives bound-check the 1023-byte
  buffer, not the payload length. The destination region is memset to zero before the reads,
  so a *previously unused* buffer yields zeros, which is why the empty path appears to work.
  It is not a guarantee. Serving 348 zero bytes would be.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4305 — 128 bytes empty, 0x163 populated"
seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] wire 0x000. Nonzero -> every field below is skipped and the transaction completes as failed. [ELF 0xD4553C]"
  - id: name
    size: 16
    doc: "[CONFIRMED] wire 0x004. Last-hosted game name, ISO-8859-1. Client slot is 17 bytes."
  - id: comment
    size: 128
    doc: "[CONFIRMED] wire 0x014."
  - id: password_enabled
    type: u1
    doc: "[INFERRED] wire 0x094. Position exact (0xD5CB54, the duplicate u8 primitive). Named from the 0x4310 request's field order (password flag immediately before the 15/16-byte password), which is the structure this reply mirrors back."
  - id: password
    size: 16
    doc: "[INFERRED] wire 0x095. Position exact; named as above."
  - id: dedicated
    type: u1
    doc: "[INFERRED] wire 0x0a5. Position exact. The 0x4310 request has the dedicated flag here; PROTOCOL.md notes the request's *subtype* byte is the one dropped from this reply, and the field count agrees."
  - id: rotation
    type: rotation_round
    repeat: expr
    repeat-expr: 16
    doc: |
      [ELF] wire 0x0a6..0x0d5, block +0..+47. Sixteen `{rule, map, flags}` triples — the count is
      tier 1 (parser loop `cmpdi r27,16` at 0xD45648), the per-field names are tier 4.

      **SERVED SHORT UNTIL 2026-07-26:** `HostSettingsReply` copied 45 bytes (15 triples), so
      round 16 went out zeroed and a host with a full rotation lost its last round on the Create
      Game pre-fill. Fixed to 48. The 15 was a reference-server figure defended by a
      reference-derived terminator claim ("the reader stops at the first `rule==0 && map==0`")
      that the writer contradicts — it always emits all sixteen.
      The parser scatters them into three parallel 16-byte client arrays (rules at B+752,
      maps at B+768, flags at B+784, B = ctx+0x10000-29904), which is the same storage
      `0x43F1` writes and the same 48 wire bytes as `0x4313`.
  - id: unknown_0d6
    type: u1
    doc: |
      [UNKNOWN — meaning; ELF — fate, 2026-07-30] wire 0x0d6, block +48, struct **+800**. Parser
      write `0xD45658`.

      **Consumed, and the consumer is named.** `0x8CA460` (`lbz r0,800(r9)`) copies it to
      `stb r0,125(r1)` inside an 8-byte scratch zeroed at `0x8CA444`-`0x8CA450`, and
      `0x8CA6E4`-`0x8CA6F0` publishes that scratch as `0x27F258(obj, key=86, len=8, src=r1+124)` —
      **property-store key 86, byte 1**, matching what `../inbound/mgo2_cmd_4310_c2s.ksy` recorded
      for the same wire byte. So it leaves the ELF into the lobby stage script's namespace; the
      ELF-side accessor `0x90786C` is dead (no `bl`, OPD only, `ET_EXEC` with no relocations).

      No meaning established and none guessed.

      [ELF 2026-08-01] **Two things are now settled about it that were not, and both are shape
      rather than meaning.**

      *It is half of a pair, and the property record says so.* The key-86 buffer is 8 bytes at
      `r1+124`, zeroed in one go at `0x8CA444`-`0x8CA450` (`sth r0,0/2/4/6(r9)`, `r9 = r1+124`),
      and **only bytes 1 and 5 are ever written** — `+800` to byte 1 (`0x8CA464`) and `+801` to
      byte 5 (`0x8CA46C`). Two big-endian u16 slots four bytes apart, each carrying a u8 in its low
      half. So the client publishes these two bytes as **two elements of one array**, not as two
      unrelated settings, and whatever `unknown_0d6` is, `unknown_0d7` is the same kind of thing.

      *No client-side widget can change them.* `+801` is a rare displacement and its census is
      complete — **15 instructions image-wide**, every one accounted for:

      | site | what |
      | --- | --- |
      | `0xD45674` | this parser's read (`addi r4,r29,801` into the struct) |
      | `0xD43710` | `0x4313`'s block-relative equivalent (`+49`) |
      | `0xD44974` | the **`0x4310` create-game builder** putting it back on the wire (`bl 0xD5C8A0`, put_u8) — sits between `+800` at `0xD44960` and the 16-byte weapon block at `0xD44988` |
      | `0x8CA468` | the property-store publisher |
      | `0x907844` | the dead accessor |
      | `0xBC32C4`, `0xBC33D0`, `0xBC36E8`, `0xBC3890`, `0xBC3E58`, `0xBC4078` | the developer-console string parser — same function family as `0xBC4A0C`, which `strtol`s into the character-list header |
      | `0x644FC0`, `0xA4E1A8`, `0xA53F9C`, `0xA53FC4`, `0xA54B54` | other objects. `0x644FBC`/`0x644FC0` is decisive on its own: it writes a 9-byte run at `+800..+808` beside another at `+784..+792` and fields at `+750`/`+751`, i.e. a stride-16 table. On this struct `+802..+817` is `weapon_restrictions` and `+750` is outside the settings block entirely, so it cannot be this object |

      Every site that touches `+801` touches `+800` in the same breath and in the same way, which is
      what carries the conclusion across to `+800` — whose own displacement is far too common (771
      raw hits) to enumerate. **The pair is server-authoritative and round-trips: parser in,
      `0x4310` builder out, publisher sideways. Nothing in the create-game UI writes either byte.**
      That also means the obvious experiment — change the setting in game and watch the wire —
      cannot exist, because there is no control bound to them in this build.
  - id: unknown_0d7
    type: u1
    doc: |
      [UNKNOWN — meaning; ELF — fate, 2026-07-30] wire 0x0d7, block +49, struct **+801**. Parser
      write `0xD45674`. Same fate: `0x8CA468` copies it to `stb r0,129(r1)` = **key 86, byte 5** of
      the same 8-byte record. Dead accessor `0x907844`. Meaning [UNKNOWN].

      [ELF 2026-08-01] It is the **second element** of the key-86 array — see `unknown_0d6`, which
      carries the 15-site census of this displacement, the proof that no create-game widget writes
      either byte, and the reason the two must be read as a pair. The one experiment that could
      still decide them is on the **stage-script** side, not the wire: key 86 is consumed by the
      lobby `.gcx` script, so dumping that script's property reads (`dev/tools/gcx`) and finding
      what it does with elements 0 and 2 of record 86 is the remaining route. Nothing in the ELF
      can answer it.
  - id: weapon_restrictions
    size: 16
    doc: "[CONFIRMED] wire 0x0d8, block +50. 16-byte lock bitfield, 1 = locked; byte 0 bit 0 is the master enable. Bit map in PROTOCOL.md. The server copies this block opaquely between 0x4310, 0x4313 and here."
  - id: max_players
    type: u1
    doc: |
      [CONFIRMED — upgraded 2026-07-30] wire 0x0e8, block +66, struct **+818**. Position exact
      (`0xD456B0`).

      The name is no longer tier 4. `0xD49528` copies `+818` into the `0x4302` game-list entry's
      T+0x1c, which that spec has as `max_players` [CONFIRMED]; and the list picker at `0x9345D0`
      computes `entry+28 − entry+31` (T+0x1c minus the player count) and buckets the result at 5
      and 10 — arithmetic that only makes sense as free slots, so `+818` is a capacity. Also
      published as property-store key 65 at `0x8CA524`/`0x8CA5F4`.
  - id: briefing_time
    type: u4
    doc: |
      [ELF] wire 0x0e9, block +68. **Immediately follows max_players** — the current-player-count
      byte at block +67 is not on this wire. Position exact; **name tier 4** (downgraded
      2026-07-26, as `max_players`).
  - id: unread_824
    type: u4
    doc: |
      [CONFIRMED 2026-07-29] wire 0x0ed, struct **+824**, and a **u32** — the parser reads four bytes
      here (`0xd5ccd8` at `0xD456E8`), not one. It spans wire 0x0ed..0x0f0, so what reads as three
      bytes of padding after it is the rest of this field.

      **Nothing in the binary reads +824.** A sweep of every access at that offset returns 105 sites,
      none in the screen, settings, accessor or parser ranges — against a control run at +848, the
      capture-proven level-limit base, which correctly finds its live readers.

      The server used to write a hardcoded `0x02` here, inherited from another implementation; with
      three zero pad bytes that produced exactly the `0x02000000` seen in captures. **That capture
      was circular** — Create Game entry memcpys the saved object into the screen (`0x89B90C`) and the
      `0x4310` builder re-emits it, so the value coming back was our own byte completing a round
      trip. Echoed from the request now.
  - id: unknown_0f1
    type: u2
    doc: |
      [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] wire 0x0f1, block +80, struct **+832**. Parser
      write `0xD45704` (u16 reader `0xD5CC14`). Corresponds to `0x4310` wire `0x0EE`, whose spec
      independently reports "no reader anywhere in the binary".

      Every in-range hit at `+832` belongs to a **u32-strided TOC global** (`lwz r9,-32768(r30)`)
      read in contiguous `lwz` runs at `0x9D6508`, `0x9DC66C`, `0x9DCFD4`, `0x9DDB30`, `0x9E1860`,
      `0xA0A684` — which cannot be this struct, because it reads `+846`/`+847` inside u32s while
      here those are two u8 fields. There is **no accessor-bank wrapper** for `+832` either.
      Full method and the other two decoy families are in `mgo2_cmd_4313_s2c.ksy`'s
      `game_settings` doc.
  - id: unknown_0f3
    type: u4
    doc: |
      [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] wire 0x0f3, block +84, struct **+836**. Parser
      write `0xD45720`. Corresponds to `0x4310` wire `0x0F0`, likewise with no reader.

      All in-range hits are the same u32-strided TOC global (`0x9D64C8`, `0x9DC670`, `0x9DCFD8`,
      `0x9DDB48`, `0x9E1878`, `0xA0A68C`). **No accessor-bank wrapper.**
  - id: unknown_0f7
    type: u2
    doc: |
      [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] wire 0x0f7, block +92, struct **+844**. Parser
      write `0xD4573C`. Corresponds to `0x4310` wire `0x0F4`, likewise with no reader.

      All in-range hits are the u32-strided TOC global (`0x9D64D0`, `0x9DC678`, `0x9DCFE0`,
      `0x9DDB50`, `0x9E1880`, `0xA0A698`) or `+112` aliases of `+956` in the create-game screen.
      **No accessor-bank wrapper.**
  - id: host_stance
    type: u1
    doc: |
      [CONFIRMED — corrected 2026-07-30] wire 0x0f9, block +94, struct **+846**. Position exact
      (`0xD45758`). **The host stance**, a u8 enum 0..9 named in the client's own developer table at
      `0xE1BC48`+ and range-gated at `0xA31230`; full table in
      `../inbound/mgo2_cmd_4310_c2s.ksy`, which confirmed it outright on 2026-07-29.

      **This retracts the 2026-07-26 downgrade above.** Two consumers pin it: `0x8CA580` publishes
      `+846` as property-store key 94, and `0xD49530` copies it into the game-list entry's T+0x24,
      which `0x4302` also calls stance.
  - id: level_limit_tolerance
    type: u1
    doc: |
      [CONFIRMED — corrected 2026-07-30] wire 0x0fa, block +95, struct **+847**. Position exact
      (`0xD45774`).

      **The 2026-07-26 note above is resolved in this field's favour, and the request spec has been
      corrected to match** — it called the same byte `unknown_0f7`. Two consumers settle it:
      `0x8CA544` publishes `+847` as property-store key 98, immediately beside key 99 = `+848`
      (level-limit base); and `0xD49550` copies it into game-list entry T+0x26, which `0x4302`
      calls `level_limit_tolerance` and which the picker at `0x93452C`-`0x93455C` uses as
      `±tolerance` around entry `+40` (the base) when level-testing a candidate.
  - id: level_limit_base
    type: u4
    doc: |
      [CONFIRMED] wire 0x0fb, block +96. **Identified 2026-07-26; was the first element of the
      18-wide `rule_timers` array.** OBSERVED.md's 2026-07-22 sweep proved the level-limit base
      is a u32 at `0x4310` wire `0xF8`, which is this field: `0x4310` carries the same block
      from wire 0xA3 with the same omissions as here, and 0xA3 + 96 - 11 = 0xF8. echo's
      verbatim `0x16` is 22 — OBSERVED.md's calibration point ("50,000 experience renders as
      level 22", the base tracking the hosting character's level). See mgo2_cmd_4313_s2c.ksy.
  - id: rule_timers
    type: u4
    repeat: expr
    repeat-expr: 17
    doc: |
      [ELF] wire 0x0ff..0x142, block +100..+167. Seventeen consecutive u32 reads — the
      per-rule timers/rounds/tickets, same run, same order and same widths as `0x4313`'s.
      (Corrected 2026-07-26: this used to say 18 reads spanning "block +96..+164". Eighteen
      u32 starting at +96 span +96..+167, and the first of them is level_limit_base above, so
      the timer run proper is 17 wide and starts at +100.)

      **The rule-to-slot pairing is no longer tier 4** (corrected 2026-07-30). The order is SNE t/r,
      CAP t/r, RES t/r, TDM t/r/tickets, DM t/tickets, BASE t/r, BOMB t/r, TSNE t/r, corroborated
      three ways in `../inbound/mgo2_cmd_4310_c2s.ksy` and reproduced from the binary here:
      `0x8CA470`-`0x8CA4CC` multiplies exactly eight of the seventeen by 60 before publishing them,
      and the eight are struct `+888, +876, +868, +860, +852, +896, +904, +912` = indices
      **9, 6, 4, 2, 0, 11, 13, 15** — precisely the eight time fields under this ordering, with no
      count scaled and no time left unscaled.
  - id: unique_red
    type: u1
    doc: |
      [ELF] wire 0x143, block +168, the first byte of a **2-byte raw block** — the parser draws
      no boundary between +168 and +169, so the split into two u8s is [INFERRED]. The names,
      the "unique character per team" reading and the "+0x80 when random" encoding are tier 4
      and **[UNKNOWN] here**: OBSERVED.md records that unique characters could not be tested in
      this build. What the ELF supports is "2 raw bytes".
  - id: unique_blue
    type: u1
    doc: |
      [ELF] wire 0x144, block +169, second byte of the same raw block. Position [ELF]; name and
      meaning [UNKNOWN], untestable in this build.
  - id: common_a
    type: u1
    doc: |
      [CONFIRMED] wire 0x145, block +177. Read as a 2-byte raw block with common_b.
      **Note the wire gap:** block +170..+176 (a u16, a u32 and a u8 in 0x4313) are absent
      here, so commonA follows unique_blue directly. Bit map as in the 0x4302 entry;
      capture-proven at 0x142/0x143 of the 0x4310 push (OBSERVED.md).
  - id: common_b
    type: u1
    doc: "[CONFIRMED] wire 0x146, block +178."
  - id: common_flags_lsb
    type: u1
    doc: |
      [CONFIRMED 2026-07-29; renamed from `unread_931` 2026-07-30] wire 0x147, block +179, struct
      **+931** — the **least significant byte (bits 0-7) of the 32-bit Common Settings flags word**
      based at +928, read as its own u8 at `0xD459C8`. `../inbound/mgo2_cmd_4310_c2s.ksy` carries
      the same byte as `common_c` at its wire 0x144.

      The name says what the byte is; what it would mean if set is [UNKNOWN] — see the negative
      below, and note the word's other unread byte, `+928`, is not on this wire at all.

      **Bits 0-7 of that word are never tested.** Every test is `rldicl.` with a shift landing in
      bits 8-23, plus `andis. 1` (bit 16) and `andi. 0x8000` (bit 15) — the seventeen Common Settings
      toggles, which the disc's help rows (set `2f0293`, ids 591-610) enumerate exactly. The only
      load of +931 anywhere is the dead accessor bank.

      Previously a hardcoded `0x20`, which sets bit 5 — inert. Echoed from the request now.
  - id: idle_kick
    type: u2
    doc: |
      [ELF] wire 0x148, block +180. u16. **Was served as a single low byte until 2026-07-26** —
      `HostSettingsReply` copied one byte into this field's low half and left the high half zero,
      the third instance of the same truncation (see `../inbound/mgo2_cmd_4310_c2s.ksy` and
      `GameService`). Correct for values <= 255, silently wrong above. Name tier 4.

      [ELF 2026-07-30] The **unit is minutes**: `0x8CA424` loads struct `+932` and `0x8CA458`
      multiplies it by 60 before publishing it as property-store key 76 (`0x8CA63C`). That is
      evidence about the quantity, not about "idle" — the name stays tier 4.
  - id: team_kill_kick
    type: u2
    doc: |
      [ELF] wire 0x14a, block +182, struct **+934**. u16, same low-byte truncation as `idle_kick`,
      fixed the same day. Name tier 4.

      [ELF 2026-07-30] Published as property-store key 69 at `0x8CA534`/`0x8CA608`, and note the
      client does it **as a single byte** (`stb r0,273(r1)` after an `lhz`) — so the client's own
      downstream copy truncates above 255 even though the wire field is 16 bits.
  - id: capture_extra_time
    type: u1
    doc: |
      [CONFIRMED — corrected 2026-07-30] wire 0x14c, block +188, struct **+940**. Position exact
      (`0xD45A1C`). **Capture Mission "EXTRA TIME"** — extend the round until a victor emerges. A
      plain toggle: handler `0x8A02B4` is `x = x ? 0 : 1`, drawn as disc string 33 "ON" / 34 "OFF".
      Named from the disc on 2026-07-29: row label 507 "EXTRA TIME" under header 498 "Capture
      Mission", help 541 *"Enabling this adds extra time to the end of the round until a victor
      emerges."* **The "name is [UNKNOWN], reference-server label" note is superseded.**

      **Follows team_kill_kick directly** — the u32 at block +184 is not on this wire. That field is
      now named `host_ping` in `mgo2_cmd_4313_s2c.ksy`; its absence here is consistent, since a
      saved-settings reply has no live host to measure.
  - id: sneaking_snake_kills
    type: u1
    doc: |
      [CONFIRMED 2026-07-29] **Sneaking Mission "SNAKE"** — how many times Snake must be defeated for
      Red and Blue to win. Renamed from `sneaking_snake_side`, which was wrong.

      Two independent routes settle it. The client **renders it as a number** (`0x89D7B8`) and clamps
      it to `[1,5]` in the create-game adjuster (`0x8A1AC8`) — a side index would be 0/1/2 and drawn
      as a name or sprite. And the disc names it directly: row label 508 "SNAKE", units 520 "times",
      help 542 *"Set the number of times Snake must be defeated (victory condition for Red and Blue
      Teams)."*
  - id: unread_tail
    size: 14
    doc: |
      [PARTIAL] wire 0x14e..0x15b, block +190..+203, struct **+942..+955**. One 14-byte raw read
      (`0xD45A54`) — the parser draws no boundaries inside it.
      **This is the last read: the payload ends at 0x15C = 348.**

      **The client never reads OR WRITES any byte of it.** Three touch points in the whole binary:
      the `0x4310` builder emitting it (`0xD44C3C`), this parser (`0xD45A54`), and the create-game
      initialiser memsetting it to zero (`0x89B5E8`). Default is fourteen zero bytes; all 214
      archived captures carry it zero.

      **Renamed from `byte_timers_and_tail` on 2026-07-30 because that name asserted something
      false.** PROTOCOL.md's subdivision into byte-sized timers for Stealth DM / Interval / Solo
      Capture / Race is echo's, and it names modes whose strings do not exist on this disc at all —
      the online-lobby set enumerates exactly eight rules and the ELF developer table agrees. See
      `../inbound/mgo2_cmd_4310_c2s.ksy`'s `unread_tail`, which also retracts the "server decodes
      `non_stat` from byte 10" claim as circular.
types:
  rotation_round:
    doc: |
      [CONFIRMED] One rotation entry, 3 wire bytes. Sixteen of them open the 204-byte settings
      block. `rule == 0 && map == 0` terminates the rotation (PROTOCOL.md 0x4310). Note the
      **wire is interleaved**: the parser reads triple i as {rule -> +i, map -> +0x10+i,
      flags -> +0x20+i}, so the three fields of one entry are adjacent on the wire but land in
      three separate 16-byte arrays in the client.
    seq:
      - id: rule
        type: u1
        doc: |
          [CONFIRMED] Game rule (mode) id for this rotation slot -> block+0x00+i. Capture-proven
          as a rotation entry via the 0x4310 push, whose copy of this block starts at wire 0xA3
          and whose 16 triples occupy 0xA3..0xD2 (OBSERVED.md / PROTOCOL.md 0x4310). The
          rule-id-to-mode mapping itself is [INFERRED], tier 4.
      - id: map
        type: u1
        doc: |
          [CONFIRMED] Map id for this rotation slot -> block+0x10+i. Position and role as above;
          the id-to-map-name table is [INFERRED], tier 4.
      - id: flags
        type: u1
        doc: |
          [ELF] Third byte of the triple -> block+0x20+i, i.e. struct+784+i, from the client's third
          16-byte array (`src+784` on the 0x4310 write side). Position exact.

          [ELF 2026-07-30] For **round 0** the label is now backed: `0xD49520` copies `struct+784`
          into the `0x4302` game-list entry at T+0x1b, beside `+752` -> `rule` and `+768` -> `map`,
          and GATES.md §2's reader `0x6A9948` treats the per-round third byte as a three-way radio
          (`0` Normal, `2` Drebin Points, `4` Headshots Only). Rounds 1..15 have no traced consumer,
          bit meanings beyond that radio are [UNKNOWN], and no single-variable sweep in OBSERVED.md
          has moved the byte.
