meta:
  id: mgo2_cmd_4305_s2c
  title: "MGO2 0x4305 — server -> client: saved host settings (reply to 0x4304)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x4305` at `0xD38948` -> stub `0xD391D0` ->
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
      [CONFIRMED] wire 0x0a6..0x0d5, block +0..+47. Sixteen `{rule, map, flags}` triples.
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
    doc: "[CONFIRMED] wire 0x0e8, block +66."
  - id: briefing_time
    type: u4
    doc: "[CONFIRMED] wire 0x0e9, block +68. **Immediately follows max_players** — the current-player-count byte at block +67 is not on this wire."
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
    doc: "[CONFIRMED] wire 0x0f9, block +94."
  - id: level_limit_tolerance
    type: u1
    doc: "[CONFIRMED] wire 0x0fa, block +95."
  - id: rule_timers
    type: u4
    repeat: expr
    repeat-expr: 18
    doc: |
      [ELF] wire 0x0fb..0x142, block +96..+164. Eighteen consecutive u32 reads. `0x4313`'s
      first of these is the slot echo fills with a verbatim `0x16`; the remaining seventeen
      are the per-rule timers/rounds/tickets. Same run, same order, same widths here.
  - id: unique_red
    type: u1
    doc: "[ELF] wire 0x143, block +168. Read as a 2-byte raw block with unique_blue. +0x80 when random."
  - id: unique_blue
    type: u1
    doc: "[ELF] wire 0x144, block +169."
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
    doc: "[CONFIRMED] wire 0x148, block +180."
  - id: team_kill_kick
    type: u2
    doc: "[CONFIRMED] wire 0x14a, block +182."
  - id: capture_extra_time
    type: u1
    doc: "[ELF] wire 0x14c, block +188. **Follows team_kill_kick directly** — the u32 at block +184 (echo's verbatim 0x2e) is not on this wire."
  - id: sneaking_snake_side
    type: u1
    doc: "[ELF] wire 0x14d, block +189."
  - id: byte_timers_and_tail
    size: 14
    doc: |
      [UNKNOWN as a unit] wire 0x14e..0x15b, block +190..+203. One 14-byte raw read — the
      parser draws no boundaries inside it. PROTOCOL.md's subdivision (8 byte-sized timers,
      a zero, an extra-time flag byte, 4 zeros) is echo's and therefore [INFERRED].
      **This is the last read: the payload ends at 0x15C = 348.**
types:
  rotation_round:
    seq:
      - id: rule
        type: u1
      - id: map
        type: u1
      - id: flags
        type: u1
