meta:
  id: mgo2_cmd_4b50_c2s
  title: "MGO2 0x4b50 — clan/GHQ bulk block write (client -> server)"
  endian: be
doc: |
  769-byte payload: one u8 followed by a fixed 768-byte block. The block is copied verbatim
  by 0xD5D0AC (bounded `memcpy` of exactly r5 bytes) from a caller-supplied pointer — the
  sender inspects none of it, so its internal structure is entirely unknown from this side.

  Evidence (ELF, retail BLUS30109): sender 0xD5804C. Builder `bl 0xD5CF40` at 0xD580CC
  (`li r4,0x4b50` at 0xD580C8), then
  `bl 0xD5C8A0` at 0xD580DC (u8, from stack 1440 = the sender's r5 parameter, spilled at
  0xD58074) and `0xD5D0AC(pkt, r4_param, 0x300)` at 0xD580F0,
  then the seal `bl 0xD5C828` at 0xD580FC and the flush `bl 0xD34CC0` at 0xD5810C.
  Note the argument order is inverted relative to the C signature: the *second* argument
  (r5, the u8) is written first, the pointer's contents second.

  Preconditions: session != NULL and the pointer != NULL — that is all; no clan-record gate,
  no length or content validation of the 768 bytes. On success the flow state advances via
  `0xD32E08(session, 104, 1)`.

  768 = 0x300 exactly, with no count field, so the block is a fixed-size struct or a fixed
  array (e.g. 0x300 = 48 x 16, or 64 x 12, or 96 x 8 — the ELF gives no divisor here; the
  producing code that fills the caller's buffer was not traced). Do NOT guess a record size:
  this project's 0x4902 lesson is that a wrong stride silently loses every entry after the
  first. Recovering the substructure means tracing the callers of 0xD5804C.

  Reading [INFERRED]: clan / GHQ family, a write-back of a whole editable table (the u8
  plausibly a page or slot selector, given 0x4B10's kind-first pattern). Never observed
  live; not answered by this server.
seq:
  - id: unknown_0000
    type: u1
    doc: |
      [ELF] Position and width exact (0xD5C8A0, 1 byte). The sender's r5 parameter,
      unvalidated. Meaning [UNKNOWN].
  - id: unknown_0001
    size: 768
    doc: |
      [UNKNOWN] Exactly 768 bytes (0x300), `memcpy`'d from the caller's pointer with no
      inspection by the sender — the ELF at 0xD580E4..0xD580F0 gives the width and nothing
      else. Substructure deliberately not modelled: no count field precedes it and no
      stride is evidenced. Trace the callers of 0xD5804C to fill this in.
