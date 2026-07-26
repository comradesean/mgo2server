meta:
  id: mgo2_cmd_43e4_s2c
  title: "MGO2 0x43e4 — server -> client: automatch state push (UNSOLICITED, no result field)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x43E4` at `0xD38A5C` -> stub `0xD39DAC` ->
  parser **`0xD5BDCC`**. Destination base `A = ctx+0x10000`.

  **This is not a reply.** Two things prove it:

  - **There is no result field.** The parser's first read is a byte of a 16-element array; no
    `0xD5CC64` u32 appears anywhere in the function, so there is no result code to check and no
    failure form.
  - **It completes no request slot.** Instead of `0xD32E08`/`0xD32E70` it calls
    `0xD33CD8(ctx, 42, <the byte from wire 0x12>)` — an event/notification dispatch carrying a
    value, not a request completion. `0x43F0` and `0x43F1` use the same helper with event ids
    43 and 44.

  So the server may send `0x43E4` at any time and the client will absorb it. It writes the
  automatch state block that `0x43E1` only partially fills: `A+0x14A1`..`A+0x14A4` plus two
  16-byte arrays at `A+0x14A5` and `A+0x14B5`, both memset to zero before the reads. Note the
  **odd read order** — the first 16-byte array comes first on the wire, then three scalars,
  then the second array, then a fourth scalar — which is why the destination offsets below run
  out of order.

  **36 bytes.** Neither PROTOCOL.md nor COMMANDS.md documents this id beyond listing it in the
  `0x43e*`/`0x43f*` unimplemented block. Nothing is known about the subsystem's semantics; the
  layout is exact and the meanings are entirely [UNKNOWN]. Since we never send it, the risk
  here is zero — this file exists so the id is enumerated and the shape recorded.
doc-ref: dev/docs/COMMANDS.md ("0x43e*/0x43f* — an in-match subsystem")
seq:
  - id: unknown_00
    size: 16
    doc: |
      [UNKNOWN] wire 0x00..0x0f -> `A+0x14A5`. Read as **sixteen separate u8 reads** in a
      `i < 16` loop, not one raw block — so it is an array of 16 single-byte values, not a
      string. Shape is that of a per-slot table (16 players? 16 lobbies?); unestablished.
  - id: unknown_10
    type: u1
    doc: "[UNKNOWN] wire 0x10 -> `A+0x14A1`. Shares its destination with 0x43E1's first status byte."
  - id: unknown_11
    type: u1
    doc: "[UNKNOWN] wire 0x11 -> `A+0x14A2`. Shares its destination with 0x43E1's second status byte."
  - id: unknown_12
    type: u1
    doc: "[UNKNOWN] wire 0x12 -> `A+0x14A3`. **This is the byte re-read and passed as the event value to `0xD33CD8(ctx, 42, value)`** — the only field of this packet the client acts on immediately, so it is the state/reason code and the rest is detail."
  - id: unknown_13
    size: 16
    doc: "[UNKNOWN] wire 0x13..0x22 -> `A+0x14B5`. Again sixteen separate u8 reads in a loop. Parallel array to `unknown_00`."
  - id: unknown_23
    type: u1
    doc: "[UNKNOWN] wire 0x23 -> `A+0x14A4`. **Last byte: 36 bytes total.**"
