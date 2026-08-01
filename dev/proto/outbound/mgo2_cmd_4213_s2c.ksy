meta:
  id: mgo2_cmd_4213_s2c
  title: "MGO2 0x4213 — list end for the 0x4210 triple (server -> client)"
  endian: be
doc: |
  Parser **0xd3af24** (GAME dispatcher 0xd38804, trampoline 0xd39190), wait slot 32 (0x20) — the
  same slot `0x4211` uses, so this is the packet that completes the request.

  **Unreachable on this build.** `0x4210`'s sender `0xD3A76C` has zero `bl`/`b`/`bc` entries and
  the list at `T+0x3330` has zero readers — see `dev/proto/inbound/mgo2_cmd_4210_c2s.ksy`. The
  layout is exact; there is simply no live consumer, so this is not a stall candidate.

  ## Parser, instruction by instruction

  * `r27 = *(ctx+0x10000 + 6404) + 13104` (`0xd3af70`-`0xd3af74`) — the same `T+0x3330` head
    `0x4211` and `0x4212` use.
  * Guard: `lwz r0,0(r27); cmpwi r0,0; beq+ -> bail(-73)` (`0xd3af80`-`0xd3af90`) — the marker
    must be **non-zero**, i.e. `0x4211` must have opened the list.
  * `READ_BEGIN` `0xd5c844`, one u32 read (`0xd5cc64` at `0xd3afa4`) into `r1+112`,
    `READ_END` `0xd5c858`.
  * `0xd32e08(ctx, 32, 2)` at `0xd3afd4`, then `0xd32e70(ctx, 32, lwa[r1+112])` at
    `0xd3afe4`-`0xd3afe8`, then `marker = 0`.

  Note what is stored in the marker: `stw r28,0(r27)` where `r28` is the **read primitive's
  return code** (0 on success), not the value read. Same idiom as `0x200b`.

  ## Result code, not count

  [ELF 2026-08-01, batch 6] Same proof as `0x4211`: this parser is `0x4683`'s (`0xd3acf8`) with
  the slot and list base changed, and `0x4683`'s result semantics are the live-confirmed ones
  (2026-07-23, `1032:00000005` when a count was sent). The word is read once, **sign-extended
  with `lwa r5,112(r1)`** and passed straight to the request-status result setter
  `0xd32e70(ctx, slot, value)` — there is no arithmetic on it, no comparison, and no loop it
  could bound. Unconditional in this arm, so a nonzero end value overwrites the slot's result
  after a successful list.

  Handler note: send `0x4213{u32 0}`.
seq:
  - id: result
    type: u4
    doc: |
      [ELF] Wire 0x00, the only field. Read at `0xd3afa4`, sign-extended at `0xd3afe4`
      (`lwa r5,112(r1)`) and forwarded **unconditionally** as `0xd32e70(ctx, 32, value)`. The
      parser makes no comparison against 0 in this arm, so a nonzero value here overwrites the
      request's result even after a clean `0x4211`+`0x4212` sequence.

      **A RESULT CODE, not a record count** — `0x4212` is size-driven and maintains its own
      count at `T+0x3330 + 4`; nothing reads this word as a length. Contrast `0x2002`, whose
      body is provably not read at all.
