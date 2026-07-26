meta:
  id: mgo2_cmd_4981_s2c
  title: "MGO2 0x4981 — server -> client: clan-member list START (opens the 0x4981/0x4982/0x4983 triple)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: reply dispatcher `0xD38804` matches `cmpwi 0x4981` at `0xd38c9c` and branches to the
  thunk at `0xd39620`, which tail-calls the parser at `0xd49fac`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  One 4-byte read, then a **branch that matters**: if the result is 0 the parser does NOT
  complete the request — it stores `-1` at `list+0x000` and 0 at `list+0x004` (the entry
  count) and returns, leaving request-status slot **62** pending so the following `0x4982`
  records and the `0x4983` end packet are accepted [READ 0xd4a060-0xd4a0c0]. If the result is
  nonzero it completes slot 62 immediately with that value and no list is opened.

  This is the same start/end contract PROTOCOL.md records for the `0x4601`/`0x4603`,
  `0x4681`/`0x4683` and `0x4685`/`0x4687` triples: **a single u32 result, 0 for success —
  never a count.** The client counts `0x4982` records itself.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xd4a03c] The only field. 0 = success and opens the list; nonzero completes
      request-status slot 62 with the error and no records are accepted.
      [INFERRED from the 0x46xx triples] Sending a count here is the mistake that produced
      the `1032:00000005` error documented in OBSERVED.md for the search triple.
