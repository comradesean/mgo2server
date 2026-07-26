meta:
  id: mgo2_cmd_43e1_s2c
  title: "MGO2 0x43e1 — server -> client: automatch status (reply to 0x43e0)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43E1` at `0xD38A34` -> stub `0xD39D3C` ->
  parser **`0xD5BF98`** (PROTOCOL.md cites `0xD5BFC0`, inside the same function).
  Request-status slot **50**. Destination base `A = ctx+0x10000`.

  Confirms PROTOCOL.md: a u32 result and, **only if that result is zero**, two u8s.
  `0xD32E08(ctx, 50, 2)` / `0xD32E70(ctx, 50, result)` run either way, so a nonzero result is a
  legitimate "nothing to report" rather than something the client chokes on. On the nonzero
  branch the parser calls `0xD5B41C` — the same error/teardown helper `0x4311` and `0x43E3` use.

  **6 bytes on success; 4 bytes is a valid "no status".** Neither reference server implements
  this command; the request is a single u8 (observed 11), sent on entry to the automatching
  lobby.

  The two bytes land at `A+0x14A1` / `A+0x14A2`, behind a "loaded" flag at `A+0x14A0` — and
  the same two bytes are written by the **unsolicited `0x43E4` push** (`mgo2_cmd_43e4.ksy`),
  which additionally fills `A+0x14A3`, `A+0x14A4` and two 16-byte arrays at `A+0x14A5` /
  `A+0x14B5`. That makes `0x43E1` a *partial* view of a larger automatch state block, and is
  the best available lead on what these bytes mean.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x43e0 — automatch status fetch"
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD5BFFC] wire 0x00. 0 = a status follows; nonzero = nothing to report (and the payload ends here). Not an error the client surfaces."
  - id: unknown_04
    type: u1
    doc: "[UNKNOWN] wire 0x04 -> `A+0x14A1`. We send 0. Also written by 0x43E4. No borrowed values exist for this command."
  - id: unknown_05
    type: u1
    doc: "[UNKNOWN] wire 0x05 -> `A+0x14A2`. We send 0. **Last byte: 6 bytes total.**"
