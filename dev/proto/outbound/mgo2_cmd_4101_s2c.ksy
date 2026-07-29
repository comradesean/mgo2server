meta:
  id: mgo2_cmd_4101_s2c
  title: "MGO2 0x4101 — character info, packet 1/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Reply 1 of the `0x4100` burst. Parser **0xd3c120** (GAME dispatcher 0xd38804, trampoline
  0xd39020). Consumes a fixed **0x142 = 322-byte** grid and never reads past it — fully traced
  0xd3c18c .. 0xd3c380, sixteen read-primitive calls, no loops except the two 32-iteration id
  arrays.

  Client struct base `r27 = ctx+22488` (0x57D8). All destinations below are relative to it except
  the 16-byte block at wire 0x12d, which goes to `ctx+0x10000+6096`.

  **There is no result field.** PROTOCOL.md flags this (item 4): the error path sends 4 bytes into
  a 322-byte grid, putting an error code where the character id goes, and the read primitives do
  **not** compare consumed bytes against the payload length — verified here, the primitives only
  bound the cursor against the 1024-byte receive buffer (`cmpwi r9,1020` etc.), never against the
  packet length. So a short `0x4101` reads the remaining 318 bytes out of stale buffer. Still
  unchecked what the client then does.

  The `0x142` size is a deliberate divergence from the reference servers' `0x243`; the parser
  confirms 322 is right — the friend and blocked arrays are **32 entries each**
  (`cmpdi cr6,r31,32` at 0xd3c2d0 and 0xd3c308), not 64.
doc-ref: dev/docs/PROTOCOL.md "0x4101 — character info, 0x142 = 322 bytes"
seq:
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED] Wire 0x000 -> +0x00, i.e. `netctx+0x57D8`.

      **This is the id space the rest of the session identifies players by** [ELF 2026-07-26,
      traced for chat]. Two consumers found so far, both outside this parser:

      - **In-game chat attribution.** `0x4401` carries a speaker id which the display consumer
        (`0xC9FFD8`) matches against `roster_entry+0x60` to resolve who spoke. That roster field is
        seeded from this value: the local player's peer descriptor is built at `0x9444BC` with
        `blob[0] = *(netctx+0x57D8)` (verified by disassembly; the descriptor's full 20-byte layout
        is in `dev/docs/STUN.md` "Where the checked address actually goes"), and the peer-join path reads a u32 from the session stream
        and compares it against `netctx+0x57D8` at `0x276694` to recognise itself before storing it
        to `entry+0x60` (`0x27687C`).
      - So a `0x4401` speaker id only renders a name if it equals the `0x4101` chara_id that
        player was sent. Confirmed live 2026-07-26: chat lines render with names.

      Practical consequence: this field is load-bearing beyond the connect burst, and changing what
      we put here would silently break chat attribution rather than failing visibly.
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: "[CONFIRMED] Wire 0x004 -> +0x04, fixed 16 (0xd5d018), NUL at +0x14."
  - id: dead_constants
    type: u2
    repeat: expr
    doc: |
      [CONFIRMED DEAD 2026-07-29] Four independent u16 — the parser writes them with four separate
      2-byte reads (`0xD3C1BC`, `0xD3C1D8`, `0xD3C1F4`, `0xD3C210`), so this is not one 8-byte field.

      **Nothing consumes them.** Each has exactly one reader — the bare getters `0x907EC0`,
      `0x907E98`, `0x907E70`, `0x907E48`, every one a plain `return u16;` with no comparison,
      arithmetic or formatting — and **none of those getters is ever called**. Zero `bl` sites, and a
      whole-image scan for any word equal to their OPD descriptors
      (`0x101C308`..`0x101C320`) found nothing, ruling out a vtable slot or TOC pointer. PPC64 emits a
      descriptor for every global function, so their existence is not evidence of use.

      We send the captured `0x16AE, 0x0338, 0x013E, 0x0150` because changing them buys nothing, and
      `MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS` zeros them for testing. The `0x0150` == 336 ==
      `0x4120` length coincidence has no code behind it and is not a lead.
  - id: experience
    type: u4
    doc: "[ELF] Wire 0x01c -> +0x120. PROTOCOL.md: the account's main exp if this is the main character, else alt exp. Also written by 0x4129's tail."
  - id: previous_login
    type: u4
    doc: "[ELF] Wire 0x020. Read as u32, widened and stored as a **u64** at +0x128 (`std` at 0xd3c274). Unix seconds; we send `now - 1`."
  - id: current_login
    type: u4
    doc: "[ELF] Wire 0x024. Same widening, stored at +0x130. Unix seconds."
  - id: unknown_028
    type: u1
    doc: "[UNKNOWN] Wire 0x028 -> +0x3328 (ctx+35584). We send zero; purpose unknown."
  - id: friend_ids
    type: u4
    repeat: expr
    repeat-expr: 32
    doc: |
      [ELF] Wire 0x029 -> +0x20 + i*4. Loop at 0xd3c2b0, bound `cmpdi r31,32`. Flat id array,
      not stats (the same conclusion the `0x4103` trace reached for its identical arrays).
      Always zero here — friends are not modelled.
  - id: blocked_ids
    type: u4
    repeat: expr
    repeat-expr: 32
    doc: "[ELF] Wire 0x0a9 -> +0xa0 + i*4. Loop at 0xd3c2e4, bound 32. Always zero."
  - id: unknown_129
    type: u1
    doc: "[UNKNOWN] Wire 0x129 -> +0x3329 (ctx+35585). Also written by 0x4129 (wire +9). We send zero."
  - id: unknown_12a
    size: 16
    doc: |
      [UNKNOWN] Wire 0x12a, fixed 16 bytes -> `ctx+0x10000+6096` = ctx+71632 — **the only field in
      this packet that does not land in the ctx+22488 block**, which is a hint that it is a
      different kind of thing (a name-shaped field in a far-away structure). We send zeros.
  - id: unknown_13a
    type: u4
    doc: "[UNKNOWN] Wire 0x13a -> +0x332c (ctx+35588). Also written by 0x4129. We send zero."
  - id: unknown_13e
    type: u4
    doc: "[UNKNOWN] Wire 0x13e -> +0x124. Sits immediately after `experience` in the struct, and 0x4129's tail writes both. We send zero."
