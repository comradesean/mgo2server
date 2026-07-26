meta:
  id: mgo2_cmd_4313_s2c
  title: "MGO2 0x4313 — server -> client: game details (reply to 0x4312)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x4313` at `0xD38954` -> stub `0xD391F0` ->
  parser **`0xD44388`**, whose settings sub-structure is read by the shared helper
  **`0xD4364C`**. Request-status slot **36**.

  This spec transcribes the layout PROTOCOL.md already establishes from this binary, and adds
  two things the ELF settles:

  - **The settings block is exactly 204 bytes and its reader is shared.** `0xD4364C` reads a
    self-contained 204-byte structure whose destination offsets equal its wire offsets. That
    closes PROTOCOL.md's fixed-size arithmetic: `0xA8` header + `204` = `0x174` = **372**, the
    documented figure, with no slack. The same helper is called by the `0x43F1` in-match
    push, which afterwards memcpy's **204** bytes out of it — an independent confirmation of
    the size. `0x4305` reads a *subset* of the same structure (see `mgo2_cmd_4305.ksy`).
  - **A precondition.** Before reading anything the parser calls `0xD32E3C(ctx, 36)` and
    requires the request-status slot to read **1** (request outstanding). An unsolicited
    `0x4313` is discarded.

  Parse order and error behaviour, from `0xD44388`: verify `hdr.command == 0x4313` (else
  `-70`); open payload; read `result`; **on nonzero, stop** — the remaining fields are never
  read and the transaction completes as failed; else read `game_id` and, if a game is
  currently selected, require it to match the stored id; zero a 968-byte destination region;
  read the fixed part, the 204-byte settings block, then player entries while payload remains
  (`0xD5CEB0`). A truncated entry is `-71`, never a shorter list — the client keeps waiting.

  The read primitives bound-check only against the **1023-byte receive buffer**, not the
  payload length, so a short payload does not error where PROTOCOL.md suggests it would: it
  reads stale buffer bytes into real fields. Sending the full 372 is therefore required for
  correctness, not merely for parse success.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4313 — 372 bytes plus 28 per player"
seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] wire 0x000. Nonzero aborts the parse and surfaces the error; no field below is read. [ELF 0xD443F4-0xD44424]"
  - id: game_id
    type: u4
    doc: "[CONFIRMED] wire 0x004. If a game is currently selected the client requires this to match it."
  - id: name
    size: 16
    doc: "[CONFIRMED] wire 0x008. ISO-8859-1, NUL-padded. Raw read; the client's slot is 17 bytes (16 + terminator)."
  - id: comment
    size: 128
    doc: "[CONFIRMED] wire 0x018. ISO-8859-1."
  - id: unknown_098
    type: u1
    doc: "[UNKNOWN] wire 0x098. Read by 0xD5CB54 (a duplicate of the u8 primitive). PROTOCOL.md folds 0x098-0x099 into \"2 bytes zero\"; they are two separate u8 reads."
  - id: unknown_099
    type: u1
    doc: "[UNKNOWN] wire 0x099. As above."
  - id: lobby_subtype
    type: u1
    doc: "[CONFIRMED] wire 0x09a. Lobby subtype — the same byte the game-lobby 0x3003 appends as its trailing flag (LOBBIES.md / PROTOCOL.md 0x4902)."
  - id: average_experience
    type: s4
    doc: "[CONFIRMED] wire 0x09b. Average experience across current players. Note the field is **unaligned** — the parser reads bytewise, so alignment is irrelevant."
  - id: host_score
    type: u4
    doc: "[CONFIRMED] wire 0x09f."
  - id: host_votes
    type: u4
    doc: "[CONFIRMED] wire 0x0a3."
  - id: unknown_0a7
    type: u1
    doc: "[UNKNOWN] wire 0x0a7. echo writes 1 verbatim; meaning unknown. Regression guard only."
  - id: settings
    type: game_settings
    doc: |
      [ELF 0xD4364C] The 204-byte settings block, wire 0x0a8..0x173. Shared verbatim with
      `0x43F1` and, minus eight fields, with `0x4305`.
  - id: players
    type: player_entry
    repeat: eos
    doc: |
      [CONFIRMED] 28 bytes each, host's entry first, **size-driven** — read while
      `0xD5CEB0` reports payload remaining. No count field. PROTOCOL.md records the client's
      cap as 18, and 372 + 18*28 = 876 fits the transport's 0x400 (1024) payload limit.
types:
  game_settings:
    doc: |
      204 bytes. Offsets below are relative to the block start (wire 0x0a8 in this command),
      and equal the client struct offsets — `0xD4364C` writes each field at its own wire
      offset inside a 204-byte destination.
    seq:
      - id: rotation
        type: rotation_round
        repeat: expr
        repeat-expr: 16
        doc: |
          [CONFIRMED] block +0..+47. **Sixteen** triples, not fifteen: the parser's loop runs
          `i < 16`. Each triple's three bytes land in three *parallel* 16-byte arrays in the
          client, not interleaved — which is why `0x4305`'s destinations look scattered.
          `rule == 0 && map == 0` ends the rotation (PROTOCOL.md 0x4310).
      - id: unknown_48
        type: u1
        doc: "[UNKNOWN] block +48 (wire 0x0d8). echo zeroes it."
      - id: unknown_49
        type: u1
        doc: "[UNKNOWN] block +49 (wire 0x0d9). echo zeroes it."
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] block +50 (wire 0x0da). One bit per item, 1 = locked; byte 0 bit 0 is the
          master enable. Per-bit map in PROTOCOL.md, with the bits confirmed weapon-by-weapon
          against this build marked there; the rest are reference-derived and unverifiable here.
      - id: max_players
        type: u1
        doc: "[CONFIRMED] block +66 (wire 0x0ea)."
      - id: player_count
        type: u1
        doc: "[CONFIRMED] block +67 (wire 0x0eb). Current player count. **Absent from 0x4305** — the only live-session field in the block, and the saved-settings reply skips exactly it."
      - id: briefing_time
        type: u4
        doc: "[CONFIRMED] block +68 (wire 0x0ec)."
      - id: unknown_72
        type: u4
        doc: "[UNKNOWN] block +72 (wire 0x0f0). First of PROTOCOL.md's \"seven fields the parser reads and echo zeroes\". Present in 0x4305, where the server injects the constant 0x02 at the corresponding wire offset 0x0ED and the client stores it (OBSERVED.md)."
      - id: unknown_76
        type: u4
        doc: "[UNKNOWN] block +76 (wire 0x0f4). **Not read by 0x4305.**"
      - id: unknown_80
        type: u2
        doc: "[UNKNOWN] block +80 (wire 0x0f8)."
      - id: unknown_82
        type: u2
        doc: "[UNKNOWN] block +82 (wire 0x0fa). **Not read by 0x4305.**"
      - id: unknown_84
        type: u4
        doc: "[UNKNOWN] block +84 (wire 0x0fc)."
      - id: unknown_88
        type: u4
        doc: "[UNKNOWN] block +88 (wire 0x100). **Not read by 0x4305.**"
      - id: unknown_92
        type: u2
        doc: "[UNKNOWN] block +92 (wire 0x104). Last of the seven."
      - id: stance
        type: u1
        doc: "[CONFIRMED] block +94 (wire 0x106)."
      - id: level_limit_tolerance
        type: u1
        doc: "[CONFIRMED] block +95 (wire 0x107)."
      - id: unknown_96
        type: u4
        doc: "[UNKNOWN] block +96 (wire 0x108). echo writes 0x16 verbatim — regression guard only. It is the first of a run of **eighteen** consecutive u32 reads; PROTOCOL.md splits the run as 1 + 17, which is a semantic split, not a structural one."
      - id: rule_timers
        type: u4
        repeat: expr
        repeat-expr: 17
        doc: |
          [ELF] block +100..+167 (wire 0x10c..0x14f). Per-rule timers, rounds and tickets.
          echo's ordering (SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets, DM t/tickets, BASE t/r,
          BOMB t/r, TSNE t/r) accounts for 17 slots and is the only naming available; the
          parser itself just reads seventeen u32s, so the pairing is [INFERRED].
      - id: unique_red
        type: u1
        doc: "[ELF] block +168 (wire 0x150). Unique character, red team; +0x80 when random. Read as part of a 2-byte raw block together with unique_blue."
      - id: unique_blue
        type: u1
        doc: "[ELF] block +169 (wire 0x151)."
      - id: unknown_170
        type: u2
        doc: "[UNKNOWN] block +170 (wire 0x152). **Not read by 0x4305.**"
      - id: unknown_172
        type: u4
        doc: "[UNKNOWN] block +172 (wire 0x154). **Not read by 0x4305.**"
      - id: unknown_176
        type: u1
        doc: "[UNKNOWN] block +176 (wire 0x158). **Not read by 0x4305.**"
      - id: common_a
        type: u1
        doc: "[CONFIRMED] block +177 (wire 0x159). Same bitfield as the 0x4302 entry. Read as a 2-byte raw block with common_b."
      - id: common_b
        type: u1
        doc: "[CONFIRMED] block +178 (wire 0x15a)."
      - id: unknown_179
        type: u1
        doc: "[UNKNOWN] block +179 (wire 0x15b). echo zeroes it; in 0x4305 the server injects the constant 0x20 at the corresponding wire offset 0x147 and the client stores and replays it (OBSERVED.md), so it is a live field, not padding."
      - id: idle_kick
        type: u2
        doc: "[CONFIRMED] block +180 (wire 0x15c). Zeroed by the client when commonA bit 0 is clear."
      - id: team_kill_kick
        type: u2
        doc: "[CONFIRMED] block +182 (wire 0x15e). Zeroed when commonB bit 7 is clear."
      - id: unknown_184
        type: u4
        doc: "[UNKNOWN] block +184 (wire 0x160). echo writes 0x2e verbatim — regression guard only. **Not read by 0x4305.**"
      - id: capture_extra_time
        type: u1
        doc: "[ELF] block +188 (wire 0x164)."
      - id: sneaking_snake_side
        type: u1
        doc: "[ELF] block +189 (wire 0x165)."
      - id: byte_timers_and_tail
        size: 14
        doc: |
          [UNKNOWN as a unit] block +190..+203 (wire 0x166..0x173). **One 14-byte raw read**,
          so the parser draws no field boundaries here at all. PROTOCOL.md subdivides it from
          echo as 8 byte-sized timers (SDM t/r, INT t, DM r, SCAP t/r, RACE t/r), a zero byte,
          an extra-time flag byte (bit 1 = non-stat game), and 4 zero bytes — [INFERRED],
          tier 4 for the names.
  rotation_round:
    seq:
      - id: rule
        type: u1
      - id: map
        type: u1
      - id: flags
        type: u1
  player_entry:
    doc: "28 bytes. Host first."
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED] +0x00."
      - id: name
        size: 16
        doc: "[CONFIRMED] +0x04. ISO-8859-1, NUL-padded."
      - id: ping
        type: u4
        doc: "[CONFIRMED] +0x14. Fed from the 0x4398 report."
      - id: experience
        type: u4
        doc: "[CONFIRMED] +0x18. From the account's main/alt pool per character."
