meta:
  id: mgo2_cmd_4114_c2s
  title: "MGO2 0x4114 — update chat macros (client -> server)"
  endian: be
doc: |
  **769 bytes (0x301), sent twice — once per macro type.** Evidence: builder call site
  `bl 0xd5cf40` at `0xd3c05c` (`li r4,16660` = `0x4114` at `0xd3c058`). Two write primitives
  before the seal (`bl 0xd5c828` at `0xd3c0a0`):

    * `bl 0xd5c86c` (write-u8) at `0xd3c06c`, source stack `1328(r1)` — the macro type;
    * `bl 0xd5d0ac` (write-blob, `r5 = 768`) at `0xd3c090`, source computed as
      `r26 + type * 768 + 304` (`lbz r4,1328(r1)` / `mulli r4,r4,768` / `add r4,r26,r4` /
      `addi r4,r4,304`) — the twelve 64-byte texts of that type.

  1 + 768 = **769**. Flush `bl 0xd34cc0` at `0xd3c0b0`, then the type counter is incremented and
  compared (`lbz r9,1328(r1)` / `addi r9,r9,1` / `cmplwi cr7,r0,1` / `bgt`) at
  `0xd3c0c0`..`0xd3c0d0`, so the function emits **two** packets, type 0 then type 1. [ELF]

  **No request-status slot is registered** for either packet: no `li r4,<slot>` /
  `bl 0xd32e08` pair follows the flush, unlike every other id in this family. That is the
  tier-1 explanation for PROTOCOL.md's live observation that `0x4114` is fire-and-forget and
  the client does not stall without `0x4115` — it is not tolerance, the client never arms a
  wait. It also settles the COMMANDS.md entry calling the `0x4115` reply "harmless ... but it
  should not be sent": there is nothing to answer. [ELF]

  Same enclosing function as `0x4110` — see `mgo2_cmd_4110.ksy` for the burst structure.
  Confirms PROTOCOL.md's layout ("`u8 type`, then twelve 64-byte ISO-8859-1 texts — the exact
  `0x4121` layout"). [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x4114 — update chat macros"
seq:
  - id: macro_type
    type: u1
    doc: |
      [CONFIRMED] 0 or 1. The loop bound is exactly `> 1` (`cmplwi cr7,r0,1` / `bgt`), so no
      third type exists on this build. What the two types *mean* is still undocumented
      anywhere we have. The source offset is `type * 768 + 304` into the client's settings
      object — the 304 being precisely the length of `0x4110`'s payload, i.e. the macro grid
      sits immediately after the gameplay-options block in the same struct. [ELF]
  - id: macros
    type: str
    size: 64
    encoding: ISO-8859-1
    repeat: expr
    repeat-expr: 12
    doc: |
      [CONFIRMED] Twelve 64-byte NUL-padded texts. Length is fixed at 768 in a single blob
      write, so the count is **not** size-driven and there is no per-entry length prefix — a
      short packet is malformed, not a shorter list.
