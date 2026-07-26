meta:
  id: mgo2_cmd_4320_c2s
  title: "MGO2 0x4320 — join game (client -> server)"
  endian: be
doc: |
  Sender located 2026-07-26: builder function `0xD451C8`, `bl 0xD5CF40` at `0xD45324`
  (`li r4,0x4320` at `0xD45320`), sealed by `0xD5C828`, **Blowfish-encrypted in place by
  `0xD5D124`** (matching `DECRYPT_COMMANDS`) and flushed by `0xD34CC0` at `0xD45390`.
  Payload writers, in order: `0xD5C9BC` (u32), `0xD5D0AC` with `r5=16` (raw 16-byte copy),
  `0xD5C86C` (u8). **Total payload 21 bytes (0x15).**

  Signature of the sender: `f(ctx, u32 game_id, char *password_or_null, u8 join_kind)`.
  Guards taken before anything is written (`0xD45210`-`0xD45248`): if the password pointer is
  non-null its `strlen` must be **3..16** (`0xDCC7F8`, then `<=2` or `>16` aborts with -61) and
  it must pass the charset validator `0xD32DD0`. The 17-byte staging buffer at `r1+1336` is
  zeroed first (`0xD4527C`-`0xD4528C`) and `strcpy`'d only when a password exists — so the
  field is always present on the wire, NUL-filled when the game has no password.

  **CONTRADICTS `dev/docs/PROTOCOL.md` "0x4320 — join game"**, which says "Sender not yet
  located in the binary, so the exact request width is unconfirmed" and lists a 20-byte
  `{u32, char[16]}` request with the password as an echo-only extra. The real request is
  **21 bytes** and the password field is unconditional; the trailing u8 is undocumented there.
doc-ref: dev/docs/PROTOCOL.md "0x4320 — join game"
seq:
  - id: game_id
    type: u4
    doc: "[ELF] 0x00. Third argument of `0xD451C8`, staged at `r1+1480`, written by `0xD5C9BC` at `0xD4532C`. Agrees with PROTOCOL.md and with the live-verified handler."
  - id: password
    size: 16
    doc: |
      [ELF] 0x04. Raw 16-byte copy (`0xD5D0AC`, `r5=16`, at `0xD4533C`) of a zero-initialised
      17-byte staging buffer, so: ISO-8859-1, NUL-padded, **always sent**, all zero when the
      game is unlocked. Validated client-side to 3..16 printable characters before send.
  - id: join_kind
    type: u1
    doc: |
      [UNKNOWN] 0x14 — position exact, meaning unestablished. Written by `0xD5C86C` at
      `0xD45348` from `r1+1328`, which is built at `0xD452A0`-`0xD45308`:
      default **1**; overwritten by `lbz r3+608` if both `0xD4908C` and `0xD491F8` return
      non-null; then overwritten by the sender's 4th argument if that argument is one of
      **1, 2, 7, 8** — and in that case the same byte is also latched into the client context
      at `ctx+0x11560`. That same context slot is what `0x43B0` re-sends as its second field
      (see mgo2_cmd_43b0.ksy), so this is a *mode/route* discriminator for the join, plausibly
      the lobby-subtype or match-kind the join is for. Values outside {1,2,7,8} leave the
      default/derived byte in place. Not read by the server today.
