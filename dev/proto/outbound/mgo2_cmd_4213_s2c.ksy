meta:
  id: mgo2_cmd_4213_s2c
  title: "MGO2 0x4213 — list end for the 0x4210 triple (server -> client)"
  endian: be
doc: |
  Parser **0xd3af24** (GAME dispatcher 0xd38804, trampoline 0xd39190), wait slot 32 (0x20) — the
  same slot `0x4211` uses, so this is the packet that completes the request.

  Guard: `lwz r0,0(r27); cmpwi r0,0; beq -> bail(-73)` where `r27 = *(ctx+0x10000+6404) + 13104`
  — the marker must be non-zero, i.e. `0x4211` must have opened the list. Then one u32 read
  (0xd5cc64 at 0xd3afa4), `notify(32, state 2)`, `notify(32, value)`, and `marker = 0`.

  Note what is stored in the marker: `stw r28,0(r27)` where `r28` is the **read primitive's return
  code** (0 on success), not the value read. Same idiom as `0x200b`.
seq:
  - id: result
    type: u4
    doc: "[ELF] Wire 0x00. Forwarded verbatim as `notify(32, value)`. The parser makes no comparison against 0 in this arm."
