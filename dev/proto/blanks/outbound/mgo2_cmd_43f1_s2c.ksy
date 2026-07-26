meta:
  id: mgo2_cmd_43f1_s2c
  title: "MGO2 0x43f1 — server -> client: in-match game-settings push (UNSOLICITED, no result field)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x43F1` at `0xD38A74` -> stub `0xD39D6C` ->
  parser **`0xD5B664`**.

  **Not a reply, and the most interesting of the `0x43Fx` block:** it carries the **same
  204-byte game-settings structure as `0x4313`**, read by the same shared helper `0xD4364C`.
  That is what identifies the subsystem — this is a mid-match "the game's settings are now
  these" push, the in-match counterpart of the browser's `0x4313` details reply.

  No result field: the first read is a u32 that is used as a **room/game key**, and the parser
  completes no request slot — it ends with `0xD33CD8(ctx, 44, key)`, the event helper, passing
  that key as the event value. So the server may push it unprompted.

  Sequence: verify `hdr.command == 0x43F1` (else `-70`); `0xD3F7B0(ctx)` obtains record `R`;
  `0xD5C844` open; read `key`, four scalars, one u8, then the 204-byte settings block into
  `R+148` via `0xD4364C`; `0xD5C858` close; then the interesting part —
  `0xD3A094(ctx)` is asked for the current game object and **if it exists and its first word
  differs from `key`**, `0xD3F71C(ctx)` is asked for another base and **204 bytes are memcpy'd
  (`0xDC95C0`) from `R+148` to that base + 752**. `+752` is exactly where `0x4305` writes the
  settings block (`B+752` = rotation base), so the push overwrites the *saved host settings*
  view when the key does not match the current game. Independent confirmation that the block is
  204 bytes and that `0x4305`'s block base is `B+752`.

  **19 bytes of header + 204 = 223 bytes (`0xDF`).** COMMANDS.md files it under
  "`0x43e*`/`0x43f*` — an in-match subsystem". Field meanings in the header are [UNKNOWN]; the
  settings block is as well documented as `0x4313`'s. We never send it.
doc-ref: dev/docs/COMMANDS.md; dev/proto/blanks/mgo2_cmd_4313.ksy (the shared 204-byte block)
seq:
  - id: key
    type: u4
    doc: |
      [ELF 0xD5B6DC] wire 0x00. **Not stored in the record.** Compared against the first word of
      the current game object (`0xD3A094`), and passed as the value of event 44. On a mismatch
      the settings block is copied over the saved-host-settings region. Plausibly a game/room
      id [INFERRED from the comparison, not from any name in the binary].
  - id: unknown_04
    type: u4
    doc: "[UNKNOWN] wire 0x04 -> `R+4`."
  - id: unknown_08
    type: u1
    doc: "[UNKNOWN] wire 0x08 -> `R+8`."
  - id: unknown_09
    type: u1
    doc: "[UNKNOWN] wire 0x09 -> `R+9`."
  - id: unknown_0a
    type: u4
    doc: "[UNKNOWN] wire 0x0a -> `R+12`."
  - id: unknown_0e
    type: u4
    doc: "[UNKNOWN] wire 0x0e -> `R+16`."
  - id: unknown_12
    type: u1
    doc: "[UNKNOWN] wire 0x12 -> `R+352`. Note the destination is *past* the 204-byte settings block at `R+148`..`R+351`, so this byte is a sibling of the block, not part of it."
  - id: settings
    type: game_settings
    doc: |
      [ELF 0xD4364C] wire 0x13..0xDE, 204 bytes -> `R+148`. **The same structure as
      `0x4313`'s settings block**, same reader, same internal offsets. See
      `mgo2_cmd_4313.ksy` for the per-field documentation and confidence tags; it is not
      duplicated here to avoid two copies drifting apart.
types:
  game_settings:
    doc: |
      204 bytes, offsets relative to the block start. Read by the shared helper `0xD4364C`;
      each field's destination offset inside the block equals its wire offset. Documented
      field by field in `mgo2_cmd_4313.ksy` — the fields are named here only so the compiler
      accounts for all 204 bytes.
    seq:
      - id: rotation
        size: 48
        doc: "block +0. Sixteen {rule, map, flags} triples. [CONFIRMED via 0x4313]"
      - id: unknown_48
        type: u1
        doc: "block +48. [UNKNOWN]"
      - id: unknown_49
        type: u1
        doc: "block +49. [UNKNOWN]"
      - id: weapon_restrictions
        size: 16
        doc: "block +50. [CONFIRMED via 0x4313]"
      - id: max_players
        type: u1
        doc: "block +66. [CONFIRMED via 0x4313]"
      - id: player_count
        type: u1
        doc: "block +67. [CONFIRMED via 0x4313]"
      - id: briefing_time
        type: u4
        doc: "block +68. [CONFIRMED via 0x4313]"
      - id: unknown_72
        type: u4
        doc: "block +72. [UNKNOWN]"
      - id: unknown_76
        type: u4
        doc: "block +76. [UNKNOWN]"
      - id: unknown_80
        type: u2
        doc: "block +80. [UNKNOWN]"
      - id: unknown_82
        type: u2
        doc: "block +82. [UNKNOWN]"
      - id: unknown_84
        type: u4
        doc: "block +84. [UNKNOWN]"
      - id: unknown_88
        type: u4
        doc: "block +88. [UNKNOWN]"
      - id: unknown_92
        type: u2
        doc: "block +92. [UNKNOWN]"
      - id: stance
        type: u1
        doc: "block +94. [CONFIRMED via 0x4313]"
      - id: level_limit_tolerance
        type: u1
        doc: "block +95. [CONFIRMED via 0x4313]"
      - id: unknown_96
        type: u4
        doc: "block +96. [UNKNOWN] — echo's verbatim 0x16."
      - id: rule_timers
        type: u4
        repeat: expr
        repeat-expr: 17
        doc: "block +100..+167. [ELF] Per-rule timers/rounds/tickets."
      - id: unique_red
        type: u1
        doc: "block +168. [ELF]"
      - id: unique_blue
        type: u1
        doc: "block +169. [ELF]"
      - id: unknown_170
        type: u2
        doc: "block +170. [UNKNOWN]"
      - id: unknown_172
        type: u4
        doc: "block +172. [UNKNOWN]"
      - id: unknown_176
        type: u1
        doc: "block +176. [UNKNOWN]"
      - id: common_a
        type: u1
        doc: "block +177. [CONFIRMED via 0x4313]"
      - id: common_b
        type: u1
        doc: "block +178. [CONFIRMED via 0x4313]"
      - id: unknown_179
        type: u1
        doc: "block +179. [UNKNOWN]"
      - id: idle_kick
        type: u2
        doc: "block +180. [CONFIRMED via 0x4313]"
      - id: team_kill_kick
        type: u2
        doc: "block +182. [CONFIRMED via 0x4313]"
      - id: unknown_184
        type: u4
        doc: "block +184. [UNKNOWN] — echo's verbatim 0x2e."
      - id: capture_extra_time
        type: u1
        doc: "block +188. [ELF]"
      - id: sneaking_snake_side
        type: u1
        doc: "block +189. [ELF]"
      - id: byte_timers_and_tail
        size: 14
        doc: "block +190..+203. [UNKNOWN as a unit] One 14-byte raw read; no field boundaries in the parser."
