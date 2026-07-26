meta:
  id: mgo2_cmd_4b10_c2s
  title: "MGO2 0x4b10 — clan/GHQ value adjust (client -> server)"
  endian: be
doc: |
  6-byte payload: u8, s32, u8 — in that order.

  Evidence (ELF, retail BLUS30109): sender 0xD58164. Builder `bl 0xD5CF40` at 0xD582AC
  (`li r4,0x4b10` at 0xD582A8), then
  `bl 0xD5C86C` at 0xD582BC (u8 from stack 1480),
  `bl 0xD5C95C` at 0xD582CC (**signed** u32 serializer — the `sraw` variant, distinct from
  the unsigned 0xD5C9BC every other 0x4Bxx sender uses — from stack 1328), and
  `bl 0xD5C86C` at 0xD582DC (u8 from stack 1488),
  then the seal `bl 0xD5C828` at 0xD582E8 and the flush `bl 0xD34CC0` at 0xD582F8.
  On success the flow state advances via `0xD32E08(session, 100, 1)`.

  The sender is (session, u8 kind, u8 arg2). `kind` is spilled to 1480, `arg2` to 1488, and
  the s32 is *computed*, not passed: `kind` must be <= 4 (else -24) and indexes a jump table
  at 0xD58238 whose arms read a u32 at offset +0x08 of a global clan block
  (`[global+0x2_2868]+8`, resolved at 0xD58204):

  | kind | s32 written | note |
  | --- | --- | --- |
  | 0 | 0 | table arm falls through to the builder; the stack slot was zeroed at 0xD581B8 |
  | 1 | value - 100 | and if `value < 0` the client **rewrites kind to 3** (0xD5826C) |
  | 2 | value + 100 | |
  | 3 | 0 | same arm as kind 0 |
  | 4 | value | verbatim |

  So the wire carries a signed delta or absolute in units where 100 is the step, and the
  client picks the arm. Reading [INFERRED]: a clan/GHQ points or funds adjust — deposit /
  withdraw / query, with kind 3 as the "insufficient" path. Nothing here is capture-proven;
  the ±100 step and the signed serializer are the only hard facts.

  Never observed live; not answered by this server.
seq:
  - id: kind
    type: u1
    doc: |
      [ELF] Position and width exact (0xD5C86C, 1 byte). Range 0..4, enforced at 0xD58218.
      Selects which arm computes `amount` below, and may be rewritten from 1 to 3 by the
      client when the source value is negative. Meanings [UNKNOWN] — the table structure
      (subtract / add / passthrough / two no-ops) is all the evidence there is.
  - id: amount
    type: s4
    doc: |
      [ELF] Signed 4 bytes (0xD5C95C, the `sraw` serializer — the sign is real evidence,
      not an assumption, and the kind-1 arm can produce a negative). Derived client-side
      from `[clan_block+0x08]` as tabulated above; never a caller argument.
  - id: unknown_0005
    type: u1
    doc: |
      [ELF] Position and width exact (0xD5C86C). The sender's second u8 parameter, passed
      through with no validation and untouched by the jump table. Meaning [UNKNOWN].
