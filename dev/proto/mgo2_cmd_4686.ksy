meta:
  id: mgo2_cmd_4686
  title: "MGO2 0x4686 — match-detail record(s) (item packet of the 0x4684 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Item packet of the 0x4684 match-detail triple (0x4685 start {u32 result} / 0x4686 items /
  0x4687 end {u32 result}). The start/end u32 is a RESULT CODE, not a count — 0 required in
  both (nonzero → dialog 1034:%08X; handlers 0xd3abc8/0xd3aacc, same shape as the 0x4681
  family, ELF-traced 2026-07-23). Requested with the u32 entry id of a 0x4682 list row.
  Records packed back to back, parser 0xd3b42c reads to end of payload and the client counts
  them itself; table caps at 32, 93 bytes each on the wire (struct stride 0x60).

  Field POSITIONS are READ from the ELF parser; every LABEL is unestablished — plausibly
  per-player lines of one match (the 64-byte string is the widest in the whole protocol
  family). No reference payload exists (all upstreams stub this empty). Awaiting live
  fingerprint.
doc-ref: dev/docs/PROTOCOL.md "0x4600 / 0x4680 / 0x4684 — player search and match history"
seq:
  - id: records
    type: detail_record
    repeat: eos
types:
  detail_record:
    seq:
      - id: unknown_u32_a
        type: u4
        doc: "[UNKNOWN] — id? (character?)"
      - id: unknown_str64
        type: str
        size: 64
        doc: "[UNKNOWN] 64-byte string — widest string in the family; formatted line?"
      - id: unknown_str16
        type: str
        size: 16
        doc: "[UNKNOWN] 16-byte string — name-width."
      - id: unknown_u8
        type: u1
        doc: "[UNKNOWN]"
      - id: unknown_u32_b
        type: u4
        doc: "[UNKNOWN]"
      - id: unknown_u32_c
        type: u4
        doc: "[UNKNOWN]"
