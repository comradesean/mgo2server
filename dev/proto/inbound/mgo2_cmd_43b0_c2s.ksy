meta:
  id: mgo2_cmd_43b0_c2s
  title: "MGO2 0x43b0 — in-match eight-field report (client -> server)"
  endian: be
doc: |
  Builder function `0xD44D50` = `f(ctx, u32 a, u32 b, u32 c, u32 d, u32 e)` — five caller u32s
  staged at `r1+1432`/`1440`/`1448`/`1456`/`1464` (`0xD44D88`-`0xD44D98`), plus three fields
  read out of the client context. `bl 0xD5CF40` at `0xD44DF8` (`li r4,0x43B0` at `0xD44DF4`),
  seal `0xD5C828` at `0xD44E8C`, flush `0xD34CC0` at `0xD44E9C`. Not encrypted.
  **Total payload 29 bytes (0x1D).**

  Write order (`0xD44E00`-`0xD44E80`): `0xD5C9BC` u32 from `ctx+0x11558`, `0xD5C8A0` u8 from
  `ctx+0x11560`, `0xD5C9BC` u32 from `ctx+0x11568`, then the five caller u32s in argument order.
  (`r29` is the context after `addis r29,r29,1` at `0xD44DD8`, so the displacements 5464/5472/
  5480 are `0x10000 + 0x1558/0x1560/0x1568`.)

  **Cross-link worth keeping:** `ctx+0x11560` is exactly the byte the `0x4320` join builder
  latches at `0xD45308` — its join-kind discriminator (values 1/2/7/8). So `0x43B0` re-reports
  the context of the join this session made. That is the strongest handle anyone has on either
  field; see mgo2_cmd_4320.ksy.

  Meaning otherwise unestablished — `COMMANDS.md`/`PROTOCOL.md` list `0x43B0` only as a
  sendable, unanswered gap. Reply `0x43B1` (a result single the client parses), so it is a
  latent `FFFFFF60`.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: ctx_11558
    type: u4
    doc: "[UNKNOWN] 0x00. Read from client context `ctx+0x11558` — not a caller argument, so this is session state the client is reporting back, not a request parameter."
  - id: join_kind
    type: u1
    doc: |
      [INFERRED] 0x04. Read from `ctx+0x11560` — the same slot the `0x4320` builder writes its
      join-kind byte into (`0xD45308`), so this is that byte echoed back. Values seen in the
      `0x4320` guard: 1, 2, 7, 8. Meaning of the values themselves is [UNKNOWN].
  - id: ctx_11568
    type: u4
    doc: "[UNKNOWN] 0x05. Read from client context `ctx+0x11568`, adjacent to the two above — a three-slot local record."
  - id: unknown_09
    type: u4
    doc: "[UNKNOWN] 0x09. Caller argument 1 (`r4`), unvalidated."
  - id: unknown_0d
    type: u4
    doc: "[UNKNOWN] 0x0D. Caller argument 2 (`r5`), unvalidated."
  - id: unknown_11
    type: u4
    doc: "[UNKNOWN] 0x11. Caller argument 3 (`r6`), unvalidated."
  - id: unknown_15
    type: u4
    doc: "[UNKNOWN] 0x15. Caller argument 4 (`r7`), unvalidated."
  - id: unknown_19
    type: u4
    doc: "[UNKNOWN] 0x19. Caller argument 5 (`r8`), unvalidated. Frame ends at 0x1D."
