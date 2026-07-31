meta:
  id: mgo2_cmd_4582_s2c
  title: "MGO2 0x4582 — bulk roster entries (server -> client)"
  endian: be
doc: |
  Item packets of the 0x4580 roster triple (0x4581 start / N x 0x4582 / 0x4583 end). Parser
  0xD467C0 (ends 0xD469BC), dispatcher stub 0xD39350. PROTOCOL.md records 59-byte records with
  "only id and name of known meaning"; the ELF confirms the widths and the order.

  LOOP STRUCTURE. Records back to back with NO per-packet count: a 68-byte stack scratch is
  zeroed (memset r5=68, 0xD4685C), then the loop test 0xD5CEB0 (0xD46868) compares the read
  cursor against the payload length, the seven fields are read, the scratch is memcpy'd into the
  array (stride 68, mulli at 0xD46958) and the count incremented; back-edge at 0xD4697C. The
  client's table caps at 32 entries (cmpwi 31 / bail at 0xD46950) — note this is NOT the 100 of
  the otherwise byte-identical 0x4602 search record.

  WIRE 59 BYTES, CLIENT STRUCT 68. The three 16-byte strings are read with 0xD5D018, which
  NUL-terminates at dest[16], and the u16/u32 after each are re-aligned, so struct offsets drift
  ahead of wire offsets: struct 0/4/22/24/44/48/65 for wire 0/4/20/22/38/42/58.

  THE TAIL FIELDS ARE NOT COSMETIC — see mgo2_cmd_4583.ksy: the 0x4583 end handler DISCARDS every
  collected record whose u16 at wire 0x14 is zero. Serving zeros there yields an empty roster.
doc-ref: dev/docs/PROTOCOL.md "0x4580 — bulk roster fetch (answered empty)"
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: |
      [ELF 0xD46868] Records until the payload ends. Split across packets freely — the parser resumes from the
      cursor and the client keeps the running count itself.
types:
  entry:
    doc: "59 bytes on the wire, 68 in the client struct."
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED by PROTOCOL.md] character id -> struct+0x00. [ELF 0xD46880]"
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED by PROTOCOL.md] character name, NUL-padded -> struct+0x04. [ELF 0xD468A0]"
      - id: unknown_0x14
        type: u2
        doc: |
          [UNKNOWN] meaning, [ELF] position (0xD468BC) -> struct+0x16. **The 0x4583 end handler
          drops any record whose value here is 0** (lhz +30 relative to the array slot base, i.e.
          struct+0x16, at 0xD466D4 — see mgo2_cmd_4583.ksy), so this field decides whether the
          entry survives at all. PROTOCOL.md notes the tier-4 Nomad test payload for the
          byte-identical 0x4602 record puts 36 here and guesses level/rank; unverified.

          SERVED 2026-07-26: we send **1**. Only the nonzero-ness is evidenced — 1 is simply the
          smallest value that passes the gate, and it asserts nothing about the meaning. We did
          NOT copy Nomad's 36: a level/rank guess dressed as a value is exactly the tier-4 habit
          this project pays for. If a number ever appears on the friend row, this is the field to
          fingerprint, and the answer replaces the constant with real data.

          Note the asymmetry with the byte-identical 0x4602 search record: its end handler
          (0x4603) does NO such filtering, so zeros there display fine. Two records with the same
          layout, two different survival rules.
      - id: unknown_0x16
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [UNKNOWN] 16-byte string -> struct+0x18. [ELF 0xD468DC] PROTOCOL.md's guess for the
          0x4602 twin is a clan name or current lobby name; unverified.
      - id: unknown_0x26
        type: u4
        doc: "[UNKNOWN] -> struct+0x2C. [ELF 0xD468F8]"
      - id: unknown_0x2a
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[UNKNOWN] 16-byte string -> struct+0x30. [ELF 0xD46918]"
      - id: unknown_0x3a
        type: u1
        doc: "[UNKNOWN] last byte of the record -> struct+0x41. [ELF 0xD46934]"
