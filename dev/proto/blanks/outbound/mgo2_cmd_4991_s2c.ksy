meta:
  id: mgo2_cmd_4991_s2c
  title: "MGO2 0x4991 — server -> client: game entry info — reply to 0x4990 (four 57-byte records)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: reply dispatcher `0xD38804` matches `cmpwi 0x4991` at `0xd38d04` and branches to the
  thunk at `0xd396d0`, which tail-calls the parser at `0xd48d40`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read,
  `0xD5CEB0` bytes-remaining test (`cursor < hdr.payload_len ? cursor : -1`).
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a payload shorter than the parser expects does not fail — it silently reads whatever
  follows in the buffer (the failure mode PROTOCOL.md documents for `0x4902`).

  **This contradicts PROTOCOL.md.** PROTOCOL.md §`0x4990` describes the reply as 172 bytes:
  `u32 0, u32 1, 0xa4 zero bytes`, "the client only skips this block". The parser does not
  skip it. It reads:

  1. a 4-byte result (`0xD5CC64`); nonzero -> every remaining read is skipped;
  2. a 4-byte word into `rec+0x120`;
  3. **a fixed loop of four iterations** (`cmpwi r20,3` / `bne` at `0xd4d/0xd48f84`), each
     reading eleven fields (57 bytes) into `rec + 72*n`;
  4. after the loop, `rec+0x120` is compared with 4 and **overwritten with 4 if it differs**
     [READ 0xd48fb0-0xd48fc4], so whatever that word says the client behaves as if it were 4;
  5. `0xD32E08/0xD32E70(ctx, 70, result)`.

  The record area is memset to 296 bytes before the reads (`0xDD36F8`, `r5 = 296`), i.e.
  4 records of 72 bytes plus the trailing word at 0x120.

  So the payload the parser expects is **4 + 4 + 4*57 = 236 bytes**, not 172. The fixed
  answer both reference servers send is 64 bytes short; it "works" only because the readers
  bound-check against the 1023-byte receive buffer rather than the payload length, so the
  last record and a half are read out of whatever follows in the buffer. That is exactly the
  mechanism PROTOCOL.md documents for the truncated `0x4902` entries. **Untested against a
  real server capture** — the 172-byte answer is what we send today and the screen advances,
  which means the four records' contents have never mattered so far, not that they are absent.
doc-ref: dev/docs/PROTOCOL.md "0x4990 — get game entry info"
seq:
  - id: result
    type: s4
    doc: "[ELF 0xd48df4] 0 = success; nonzero skips the count and all four records."
  - id: entry_count
    type: u4
    if: result == 0
    doc: |
      [ELF 0xd48e1c] Stored at `rec+0x120`, then **forced to 4** after the loop if it is not
      already 4 [READ 0xd48fb0]. PROTOCOL.md calls this "always 1"; the client rewrites 1 to
      4. The loop count is hardcoded at four regardless of this value, so it is advisory at
      best. [UNKNOWN] whether the original server varied it.
  - id: entries
    type: entry
    repeat: expr
    repeat-expr: 4
    if: result == 0
    doc: |
      [ELF 0xd48e44-0xd48fa0] Exactly four records, 57 wire bytes each, strided 72 bytes in
      the client struct. Count source is the **hardcoded loop bound**, not `entry_count`.
types:
  entry:
    doc: "57 wire bytes; client stride 72 (`rec + 72*n`)."
    seq:
      - id: unknown_00
        type: u4
        doc: "[UNKNOWN] rec+0x00 of the record."
      - id: unknown_04
        type: u1
        doc: "[UNKNOWN] rec+0x04."
      - id: unknown_05
        type: u1
        doc: "[UNKNOWN] rec+0x05."
      - id: unknown_06
        type: u4
        doc: "[UNKNOWN] read into a stack slot then stored 64-bit-wide at rec+0x08."
      - id: unknown_0a
        type: u4
        doc: "[UNKNOWN] rec+0x10."
      - id: name_a
        type: str
        size: 16
        doc: "[INFERRED] rec+0x14, 16-byte raw block; name-width by analogy. Width is [ELF 0xd48ee8]."
      - id: unknown_1e
        type: u4
        doc: "[UNKNOWN] rec+0x28."
      - id: name_b
        type: str
        size: 16
        doc: "[INFERRED] rec+0x2c, second 16-byte raw block. Width is [ELF 0xd48f24]."
      - id: unknown_32
        type: u1
        doc: "[UNKNOWN] rec+0x3d — note the 1-byte gap after the string (0x3c is not written)."
      - id: unknown_33
        type: u2
        doc: "[UNKNOWN] rec+0x3e."
      - id: unknown_35
        type: u4
        doc: "[UNKNOWN] rec+0x40, the last field of the record."
