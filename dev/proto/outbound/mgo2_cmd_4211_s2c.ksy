meta:
  id: mgo2_cmd_4211_s2c
  title: "MGO2 0x4211 — list start for the 0x4210 triple (server -> client)"
  endian: be
doc: |
  Parser **0xd3b01c** (GAME dispatcher 0xd38804, trampoline 0xd39170), wait slot 32 (0x20).
  Start packet of the `0x4211` / `0x4212` / `0x4213` triple.

  **The request that would produce this triple cannot be sent by this build** — `0x4210`'s
  sender `0xD3A76C` has zero `bl`/`b`/`bc` entries, and the list this triple fills has zero
  readers. See `dev/proto/inbound/mgo2_cmd_4210_c2s.ksy` for the derivation and its controls.
  The layout below is still exact; it just has no live consumer, so this packet is not a
  stall candidate.

  ## Parser, instruction by instruction

  * `r28 = *(ctx+0x10000 + 6404) + 13104` — the list head at `T+0x3330`
    (`lwz r9,6404(r9)` / `addi r9,r9,13104` at `0xd3b068`-`0xd3b06c`).
  * Guard: `lwz r0,0(r28); cmpwi r0,0; bne+ -> bail(-73)` (`0xd3b078`-`0xd3b088`) — the list
    marker must already be 0.
  * `READ_BEGIN` `0xd5c844`, one u32 read (`0xd5cc64` at `0xd3b09c`) into `r1+112`,
    `READ_END` `0xd5c858`.
  * `lwz r31,112(r1); cmpwi r31,0` at `0xd3b0c0`-`0xd3b0c4` branches:
    * **value == 0** (`0xd3b100`): `0xd32e70(ctx, 32, 0)`, then `count = value = 0`
      (`stw r31,4(r28)`) and `marker = -1` (`stw r0,0(r28)`, `r0 = -1`). This opens the list;
      `0x4213` refuses to run unless the marker is non-zero.
    * value != 0 (`0xd3b0d8`): `0xd32e08(ctx, 32, 2)` then
      `0xd32e70(ctx, 32, lwa[r1+112])` — the value goes to the UI as the request's result and
      the list is **not** opened; the marker instead takes the read primitive's return code
      (`stw r27,0(r28)`).

  ## Result code, not count — PROVED by identity with 0x4681

  [ELF 2026-08-01, batch 6] The campaign's standing hazard is sending a count where a result
  belongs (live 2026-07-23: `0x4681` carrying 5 produced dialog `1032:00000005`). This packet
  is on the **result** side, and the proof is not shape-matching:

  **`0x4211`'s parser is `0x4681`'s parser (`0xd3adf4`) with two constants changed** — the
  slot number and the list base. Compare the tails:

  | `0x4211` | `0x4681` |
  | --- | --- |
  | `0xd3b0c0 lwz r31,112(r1)` | `0xd3ae9c lwz r31,112(r1)` |
  | `0xd3b0c4 cmpwi cr7,r31,0` | `0xd3aea0 cmpwi cr7,r31,0` |
  | `0xd3b0c8 li r4,32` | `0xd3aea4 li r4,29` |
  | `0xd3b0cc li r5,2` | `0xd3aea8 li r5,2` |
  | `0xd3b0d8 bl 0xd32e08` | `0xd3aeb4 bl 0xd32e08` |
  | `0xd3b0e8 lwa r5,112(r1)` | `0xd3aec4 lwa r5,112(r1)` |
  | `0xd3b0ec bl 0xd32e70` | `0xd3aec8 bl 0xd32e70` |
  | `0xd3b0f8 stw r27,0(r28)` | `0xd3aed4 stw r27,0(r28)` |

  The `lwa` is the tell: the word is **sign-extended** and handed to the request-status result
  setter `0xd32e70`, never to an allocator or a loop bound. That is `0x4901`'s shape (one u32
  read, refuse to open the list when nonzero) and the exact opposite of `0x2002`'s
  (`READ_BEGIN`/`READ_END` back to back with no read primitive at all).

  Handler note, should the triple ever be served: send `0x4211{u32 0}`, then the `0x4212`
  records, then `0x4213{u32 0}`.
seq:
  - id: result
    type: u4
    doc: |
      [ELF] Wire 0x00, the only field. **Must be 0** to open the list (`cmpwi cr7,r31,0` at
      `0xd3b0c4`). Non-zero is sign-extended (`lwa r5,112(r1)` at `0xd3b0e8`) and forwarded to
      the UI as the request's result via `0xd32e70(ctx, 32, value)`; no list is opened and the
      marker takes the read primitive's return code instead.

      **A RESULT CODE, not a record count** — see the doc block's instruction-level identity
      with `0x4681`'s parser `0xd3adf4`, whose result semantics were live-confirmed
      2026-07-23. Neither parser uses this word as a length: `0x4212` is size-driven and
      counts its own records.
