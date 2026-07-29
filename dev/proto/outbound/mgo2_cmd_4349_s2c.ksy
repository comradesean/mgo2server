meta:
  id: mgo2_cmd_4349_s2c
  title: "MGO2 0x4349 — server -> client: reply to 0x4348 (subsystem unidentified)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4349` at `0xD3891C` -> stub `0xD395E8` ->
  parser **`0xD4E800`**. Request-status slot **59**. Destination base `D = ctx+0x10000`.

  Neither PROTOCOL.md nor COMMANDS.md documents this reply; COMMANDS.md only records the
  request `0x4348` as an unanswered gap in the in-match/host family, and notes that mgo2-server
  calls `0x4348` "host pass" while Nomad's pass-host is `0x43a0` (which we implement). **The
  parser does not support "host pass":** it reads a name and a 128-byte comment, which is a
  descriptive card, not a host transfer ack. What screen shows it is [UNKNOWN] — no live
  capture of `0x4348` exists, so the *meaning* of every field below rests on shape alone.

  Sequence: `0xD5D124(ctx+6408, pkt, 1)` (a pre-read hook shared with `0x4305`); `0xD5C844`
  open; memset a **680-byte** destination region; read `result`; **if nonzero, skip every
  field**; else the reads below; `0xD5C858` close; `0xD32E08(ctx, 59, 2)`,
  `0xD32E70(ctx, 59, result)`.

  **Total: 171 bytes (`0xAB`).**

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md (0x4348 listed as a sendable gap)
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD4E8A0] wire 0x00. Nonzero -> nothing else is read; the request completes as failed."
  - id: name
    size: 16
    doc: "[ELF 0xD4E8CC] wire 0x04. Raw 16-byte read -> `D-19223`; the client's slot is 17 bytes (16 + terminator), the same idiom every name field in this protocol uses. ISO-8859-1 assumed by analogy [INFERRED]."
  - id: comment
    size: 128
    doc: "[ELF 0xD4E8EC] wire 0x14. Raw 128-byte read -> `D-19206`. Same width as the game comment in 0x4310/0x4313/0x4305."
  - id: flags
    type: u1
    doc: |
      [ELF 0xD4E910] wire 0x94. Read as a 1-byte raw block into a temporary, then **bits 0..3
      are each tested and OR-ed into a single u32 at `D-19052+148`**; the parser reads the
      word, sets a bit, and writes it back, four times. So this byte is a 4-flag bitfield
      expanded into one client bitmask. Which flags [UNKNOWN].
  - id: unknown_95
    size: 16
    doc: "[UNKNOWN] wire 0x95. Raw 16-byte read -> `D-19076`. A second string-shaped field (clan tag? owner name?) — width and position exact, content unestablished."
  - id: unknown_a5
    type: u1
    doc: "[UNKNOWN] wire 0xa5 -> `D-19060`."
  - id: unknown_a6
    type: u1
    doc: "[UNKNOWN] wire 0xa6 -> `D-19059`. Note the destination gap to the next field: `D-19058`/`D-19057` are skipped, so this pair is not part of the following u32."
  - id: unknown_a7
    type: u4
    doc: "[UNKNOWN] wire 0xa7 -> `D-19056`. **Last read: the payload ends at 0xAB = 171 bytes.**"
