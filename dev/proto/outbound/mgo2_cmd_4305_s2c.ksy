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
    doc: "[UNKNOWN] wire 0x0d6, block +48."
  - id: unknown_0d7
    type: u1
    doc: "[UNKNOWN] wire 0x0d7, block +49."
  - id: weapon_restrictions
    size: 16
    doc: "[CONFIRMED] wire 0x0d8, block +50. 16-byte lock bitfield, 1 = locked; byte 0 bit 0 is the master enable. Bit map in PROTOCOL.md. The server copies this block opaquely between 0x4310, 0x4313 and here."
  - id: max_players
    type: u1
    doc: |
      [ELF] wire 0x0e8, block +66. Position exact; the **name** is tier 4 and the request-side
      spec (`../inbound/mgo2_cmd_4310_c2s.ksy`) tags the same field `[ELF]`. Downgraded
      2026-07-26 — the two specs describe one field set and must not disagree about confidence.
  - id: briefing_time
    type: u4
    doc: |
      [ELF] wire 0x0e9, block +68. **Immediately follows max_players** — the current-player-count
      byte at block +67 is not on this wire. Position exact; **name tier 4** (downgraded
      2026-07-26, as `max_players`).
  - id: unknown_0ed
    type: u4
    doc: "[UNKNOWN] wire 0x0ed, block +72. This is where the server injects the constant 0x02; the client stored it and echoed it back in the next 0x4310 push (OBSERVED.md), so the slot is real and round-trips, but its meaning is unestablished."
  - id: unknown_0f1
    type: u2
    doc: "[UNKNOWN] wire 0x0f1, block +80."
  - id: unknown_0f3
    type: u4
    doc: "[UNKNOWN] wire 0x0f3, block +84."
  - id: unknown_0f7
    type: u2
    doc: "[UNKNOWN] wire 0x0f7, block +92."
  - id: stance
    type: u1
    doc: |
      [ELF] wire 0x0f9, block +94. **Tag downgraded 2026-07-26 from [CONFIRMED]:** "stance" is
      a reference-server name and the byte is absent from OBSERVED.md's single-variable sweep.
      Position exact; name [INFERRED], tier 4. See mgo2_cmd_4313_s2c.ksy.
  - id: level_limit_tolerance
    type: u1
    doc: |
      [ELF] wire 0x0fa, block +95. **The request spec calls this same value `unknown_0f7` and
      tags it [UNKNOWN]** — one byte cannot be capture-proven in the reply and unknown in the
      request. Downgraded 2026-07-26; the level-limit reading is [INFERRED] from its adjacency to
      `level_limit_base`, which OBSERVED.md's sweep did move.
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
      the timer run proper is 17 wide and starts at +100.) The rule-to-slot pairing is
      [INFERRED], tier 4.
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
  - id: unknown_147
    type: u1
    doc: "[UNKNOWN] wire 0x147, block +179. Where the server injects the constant 0x20; it came back in the next 0x4310 push, so the client stores it. echo zeroes the same slot in 0x4313."
  - id: idle_kick
    type: u2
    doc: |
      [ELF] wire 0x148, block +180. u16. **Was served as a single low byte until 2026-07-26** —
      `HostSettingsReply` copied one byte into this field's low half and left the high half zero,
      the third instance of the same truncation (see `../inbound/mgo2_cmd_4310_c2s.ksy` and
      `GameService`). Correct for values <= 255, silently wrong above. Name tier 4.
  - id: team_kill_kick
    type: u2
    doc: |
      [ELF] wire 0x14a, block +182. u16, same low-byte truncation as `idle_kick`, fixed the same
      day. Name tier 4.
  - id: capture_extra_time
    type: u1
    doc: |
      [ELF] wire 0x14c, block +188. Position exact; **the name is [UNKNOWN]** — a
      reference-server label, and nothing in OBSERVED.md moved this byte.
      **Follows team_kill_kick directly** — the u32 at block +184 (echo's verbatim 0x2e) is not
      on this wire.
  - id: sneaking_snake_side
    type: u1
    doc: |
      [ELF] wire 0x14d, block +189. Position exact; **the name is [UNKNOWN]**, same reason as
      capture_extra_time.
  - id: byte_timers_and_tail
    size: 14
    doc: |
      [UNKNOWN as a unit] wire 0x14e..0x15b, block +190..+203. One 14-byte raw read — the
      parser draws no boundaries inside it. PROTOCOL.md's subdivision (8 byte-sized timers,
      a zero, an extra-time flag byte, 4 zeros) is echo's and therefore [INFERRED].
      **This is the last read: the payload ends at 0x15C = 348.**
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
          [ELF] Third byte of the triple -> block+0x20+i, from the client's third 16-byte array
          (`src+784` on the 0x4310 write side). Position exact. Named "flags" from the write
          side's array grouping; **its contents are [UNKNOWN]** and it was not moved by any
          single-variable sweep in OBSERVED.md.
