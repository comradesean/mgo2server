meta:
  id: mgo2_cmd_200a_s2c
  title: "MGO2 0x200a — news item (server -> client)"
  endian: be
doc: |
  Reply 2/3 to `0x2008`: one news item per packet in practice, but the parser is a loop.
  Parser arm 0xd365c8, GATE dispatcher 0xd361e8; records `memcpy`d into `ctx+0xDE8 + n*920`.

  **Record count is size-driven**, exactly as in `0x2003`: the loop head at 0xd365f4 zeroes a
  920-byte scratch and calls `MORE_DATA?` (0xd5ceb0); when the cursor has reached the payload
  length it exits to `READ_END`. So a single packet may legally carry several items.

  **Client capacity is 10 items total** across all `0x200a` packets:
  `lwz r3,4(r28); cmpwi r3,9; bgt -> bail(-71)` at 0xd366cc. An eleventh item aborts the parse.

  ### Contradiction with PROTOCOL.md — the body is not a fixed 886-byte field

  PROTOCOL.md documents the body as `0x089`, 886 bytes, NUL-padded, and flags the 886 as
  "not a round number and no rationale recorded — it is what makes the payload exactly the
  1023-byte maximum" (flagged item 24). The parser says otherwise: the body is read by
  **0xd5ce34, the NUL-terminated-string primitive** (`r5 = 0` delimiter), which consumes bytes up
  to and including the first terminator and no more. The body is therefore **variable length**,
  and 886 is a padding choice of ours, not a field width. Our fixed-886 encoding still parses
  correctly (the reader stops at the first NUL and the packet ends), so this is a documentation
  correction, not a bug — but a shorter packet would be equally valid, and a body with an
  embedded NUL would be truncated there.

  Read primitives in order (0xd36630 .. 0xd366b0): u32, u8, u32, fixed[128], cstring.
doc-ref: dev/docs/PROTOCOL.md "0x200a item — 1023 bytes"
seq:
  - id: items
    type: news_item
    repeat: eos
    doc: "[ELF] Size-driven repeat (MORE_DATA? at 0xd5ceb0). Max 10 across all 0x200a packets."
types:
  news_item:
    doc: |
      Wire size = 137 + strlen(body) + 1. The client struct record is 920 bytes: u32 at +0,
      u8 at +4, the timestamp widened to u64 at +8, title at +16, body at +145.
    seq:
      - id: news_id
        type: u4
        doc: "[ELF] Wire 0x000 -> struct +0x00. PROTOCOL.md: news id. Not compared against anything by the parser."
      - id: important
        type: u1
        doc: "[ELF] Wire 0x004 -> struct +0x04. PROTOCOL.md: important flag (0/1). No range check in the parser."
      - id: timestamp
        type: u4
        doc: |
          [ELF] Wire 0x005. Read as a u32 into scratch, then widened and stored as a **u64** at
          struct +0x08 (`lwz r0,112(r1); std r0,128(r1)` at 0xd36688). PROTOCOL.md: Unix seconds.
      - id: title
        size: 128
        type: str
        encoding: ISO-8859-1
        doc: "[ELF] Wire 0x009 -> struct +0x10, fixed 128 wire bytes (0xd5d018, r5=128), NUL written at dest[128]."
      - id: body
        type: strz
        encoding: ISO-8859-1
        doc: |
          [ELF] Wire 0x089 -> struct +0x91. **NUL-terminated, variable length** — read by the
          cstring primitive 0xd5ce34 with delimiter 0 at 0xd366b0, NOT a fixed 886-byte field.
          See the contradiction note in the top-level doc. Unverified live: no client has been
          observed rendering a news item.
