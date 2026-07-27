meta:
  id: mgo2_cmd_4b4c_c2s
  title: "MGO2 0x4b4c — second clan emblem fetch (client -> server)"
  endian: be
doc: |
  **A second clan-scoped emblem fetch**, sent right after the profile. 4-byte payload: one
  unsigned u32. Reply is `0x4b4d`, `{s4 result, byte[768]}` — the same shape as `0x4b49` and
  `0x4b4b`, and it occupies request slot 103.

  [CONFIRMED 2026-07-27] The 768-byte block is the **clan emblem**, not an opaque or unknown
  blob and not a name table — see mgo2_cmd_4b48_c2s.ksy for the correction, the parser
  addresses, and the applicant-names mistake that reading caused. The server answers 0x4b4c
  with the same emblem bytes it serves to 0x4b48 and 0x4b4a.

  [INFERRED] The u32 is the clan id, by shape and by the company it keeps: it is written by
  the same serializer as 0x4b4a's clan id, it is sent immediately after the clan profile
  exchange, and its reply is byte-identical in shape to the two fetches whose id *is*
  established. What has **not** been established is what distinguishes 0x4b4c from 0x4b4a —
  both are display fetches with the same request and the same reply — so this file stays a
  draft. The server currently ignores the payload and answers from the caller's own
  membership, which works, and therefore proves nothing about the field.

  Evidence (ELF, retail BLUS30109): sender 0xD56618. Builder `bl 0xD5CF40` at 0xD5668C
  (`li r4,0x4b4c` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only.

  On a successful flush the client advances its flow state with `0xD32E08(session, 103, 1)`.
  The sender does not name the reply id.

  To settle the field: trace the callers of 0xD56618 and see which screen supplies r4 and
  from where. Serving 0x4b4c a *different* emblem from 0x4b4a for the same clan would also
  distinguish them, and is the divergence experiment nobody has run.
seq:
  - id: clan_id
    type: u4
    doc: |
      [INFERRED] The clan id, by shape and by position in the exchange — not capture-proven,
      because the server has never had to read it. Position and width exact (unsigned,
      0xD5C9BC); the caller's u32 verbatim, unvalidated by the sender.
