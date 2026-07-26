meta:
  id: mgo2_cmd_4400_c2s
  title: "MGO2 0x4400 — in-match 128-byte blob push (client -> server)"
  endian: be
doc: |
  Builder function `0xD52CEC` = `f(ctx, u8 kind, void *blob)`; a null `blob` aborts before any
  write (`0xD52D20`). `bl 0xD5CF40` at `0xD52D6C` (`li r4,0x4400` at `0xD52D68`), seal
  `0xD5C828` at `0xD52D9C`, flush `0xD34CC0` at `0xD52DAC`. Not encrypted.
  **Total payload 129 bytes (0x81).**

  Writes: `0xD5C8A0` (u8) at `0xD52D7C` from `r1+1432` (the `kind` argument, `stb r4` at
  `0xD52D14`), then `0xD5D0AC` with `r5=128` at `0xD52D90` copying the caller's buffer verbatim.

  Note what the sender does **not** do: no length argument, no `strlen`, no charset check — 128
  bytes are copied unconditionally. Compare `0x43C0`, whose 128-byte comment field *is* length
  checked; the absence here means the payload is a fixed-size record, not a string.

  Meaning unestablished. `COMMANDS.md` and `PROTOCOL.md` list `0x4400` only as a sendable,
  unanswered gap in the in-match/host family; reply `0x4401` is a result single the client
  parses, so an unanswered `0x4400` is a latent `FFFFFF60`.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: kind
    type: u1
    doc: "[UNKNOWN] 0x00. First argument, written verbatim with no validation. Named `kind` because a leading discriminator byte ahead of a fixed blob is the pattern in `0x4500`/`0x4510`/`0x4580`; unproven."
  - id: blob
    size: 128
    doc: "[UNKNOWN] 0x01-0x80. Raw 128-byte copy of the caller's buffer (`0xD5D0AC`, `r5=128`). No internal structure is visible from this function — the record is assembled by the caller, which would have to be traced separately to decompose it. Deliberately left as one opaque field rather than guessed at."
