meta:
  id: mgo2_cmd_3003_c2s
  title: "MGO2 0x3003 — check session (client -> server, payload Blowfish-encrypted)"
  endian: be
doc: |
  **Two senders, two lengths: 20 bytes on an ACCOUNT lobby, 21 on a GAME lobby.**
  This spec models the 21-byte game-lobby form and marks the trailing byte optional, because
  the two differ only by that byte.

  Evidence, ACCOUNT sender `0xd38180` (builder `bl 0xd5cf40` at `0xd381fc`):
    * `bl 0xd5c9bc` (write-u32) at `0xd3820c`, value loaded from `336(r27)` = ctx+0x150
      (`lwz r0,336(r27)` at `0xd381e4`);
    * `bl 0xd5d0ac` (write-blob, `r5 = 16`) at `0xd38224`, source `r27 + 340` = ctx+0x154;
    * seal `bl 0xd5c828` at `0xd38230`. Wait slot `0x05`.

  Evidence, GAME sender `0xd39f18` (builder `bl 0xd5cf40` at `0xd39fd4`):
    * `bl 0xd5c9bc` (write-u32) at `0xd39fe4`, value from `bl 0xd36f8c` (`0xd39f6c`);
    * `bl 0xd5d0ac` (write-blob, `r5 = 16`) at `0xd39ff8`, source the pointer returned by
      `bl 0xd36c5c` (`0xd39f7c`);
    * `bl 0xd5c8a0` (write-u8) at `0xd3a008`, from stack `1448(r1)` — the sender's `r4`
      argument, spilled at `0xd39f50`;
    * seal `bl 0xd5c828` at `0xd3a014`. Wait slot `0x06`.

  Both senders then call `bl 0xd5d124` (`0xd3824c` / `0xd3a030`) between the seal and the
  flush — the **Blowfish encrypt** step, with `r3 = ctx + 0x11908` (the key/context) and
  `r5 = 0`. Across all 28 client -> server ids traced in this pass, only `0x3003` and `0x4310`
  call `0xd5d124`, which independently reproduces the `DECRYPT_COMMANDS` membership
  PROTOCOL.md documents. [ELF]

  Confirms PROTOCOL.md's 20-byte account request built from ctx+0x150 / ctx+0x154, and its
  note that "the game-lobby sender at `0xD39F18` additionally appends a trailing flag byte".
  [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x3003 — check session"
seq:
  - id: claimed_id
    type: u4
    doc: |
      [CONFIRMED] The **account id** on an account lobby (ctx+0x150), the **character id** on a
      game lobby (from `0xd36f8c`).
  - id: session_field
    size: 16
    doc: |
      [CONFIRMED] The login token run through `nomad.common.crypto.SessionField` — not the
      token itself. See dev/docs/CRYPTO.md.

      One detail visible only in the GAME sender: the pointer is strlen-checked before the
      packet is built (`bl 0xdcc7f8` at `0xd39fa8`, `cmplwi cr7,r3,16`, `bgt` to the -73 error
      exit), so the client treats this as a NUL-terminated string of length <= 16 and a
      16-character value arrives with **no** terminator inside the field. The ACCOUNT sender
      applies no such check and copies ctx+0x154 raw. [ELF]
  - id: lobby_flag
    type: u1
    if: not _io.eof
    doc: |
      [UNKNOWN] Present only in the GAME-lobby form (sender `0xd39f18`), absent from the
      ACCOUNT form (`0xd38180`) — so its presence is itself the direction signal. The value is
      the sender's caller-supplied argument; no range check. Our server never reads it.
      Same open question as `0x4150`'s single byte, and PROTOCOL.md's numbered finding 18
      ("`0x3003`'s trailing flag byte") is still the live entry for it.
