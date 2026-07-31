meta:
  id: mgo2_cmd_4941_s2c
  title: "MGO2 0x4941 — server -> client: result ack, 0x49xx clan/GHQ family"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4941` at `0xd38c7c` and branches to the
  thunk at `0xd396b0`, which tail-calls the parser at `0xd49b48`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  The parser is a bare result ack: verify `hdr.command == 0x4941` (mismatch -> `-70`, the
  no-handler code), rewind, **one** 4-byte read into a stack slot, end-of-read, then
  `0xD32E08(ctx, 68, 2)` to complete request-status slot 68 and `0xD32E70(ctx, 68, result)`
  to store it. Nothing is written into any clan/roster structure and no field is rendered.

  Not documented in PROTOCOL.md or OBSERVED.md — the `0x49xx` block is listed there only as
  "clan / GHQ / roster, parsed but never sent". What the paired request is has NOT been
  established from the send side; only the reply shape is.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xd49b48] The only field; the whole payload is 4 bytes. 0 = success. Signed: the
      client hands it to the request slot with `lwa`. The parser does not branch on the
      value.
