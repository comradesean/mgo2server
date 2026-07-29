meta:
  id: mgo2_cmd_4991_s2c
  title: "MGO2 0x4991 — server -> client: game entry info — reply to 0x4990 (four 57-byte records)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4991` at `0xd38d04` and branches to the
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
  3. **a fixed loop of four iterations** (`cmpwi cr7,r20,3` at `0xd48f84`, `bne cr7,0xd48e44` at `0xd48fa0` — the address was mangled
     as `0xd4d/0xd48f84` in an earlier revision), each
     reading eleven fields (57 bytes) into `rec + 72*n`;
  4. after the loop, `rec+0x120` is compared with 4 and **overwritten with 4 if it differs**
     [READ 0xd48fb0-0xd48fc4], so whatever that word says the client behaves as if it were 4;
  5. `0xD32E08/0xD32E70(ctx, 70, result)`.

  The record area is memset to 296 bytes before the reads (`0xDD36F8`, `r5 = 296`), i.e.
  4 records of 72 bytes plus the trailing word at 0x120.

  SERVED 2026-07-26 at 236 bytes (`HubGameController`), with the four records zeroed because the
  57-byte layout is undecoded. The previous 172-byte reply was a reference-server length; the
  client read the missing 64 bytes out of stale receive buffer without erroring.

  So the payload the parser expects is **4 + 4 + 4*57 = 236 bytes**, not 172. The fixed
  answer both reference servers send is 64 bytes short; it "works" only because the readers
  bound-check against the 1023-byte receive buffer rather than the payload length, so the
  last record and a half are read out of whatever follows in the buffer. That is exactly the
  mechanism PROTOCOL.md documents for the truncated `0x4902` entries. **Untested against a
  real server capture** — the 172-byte answer was what we sent until 2026-07-26 and the screen advanced,
  which means the four records' contents have never mattered so far, not that they are absent.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
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
      - id: entry_key
        type: u4
        doc: |
          [CONFIRMED 2026-07-29] **The record key, and the slot-occupied flag.** Nonzero means this
          slot holds a pending entry (`0x8932FC`, `0x893470`); **zero means the slot is empty**, which
          is why an all-zero reply is the correct "no pending entries" answer rather than a
          placeholder.

          Also matched against the `0x4902` game-lobby list to find the entry that names this
          tournament (`0x8933B8`, `0x893568`), and used as the delete key by `0x4993` (`0xD48C88`).
      - id: unknown_04
        type: u1
        doc: |
          [UNKNOWN, and PARSED BUT NEVER READ — 2026-07-29] Position and width exact. **No reader
          exists anywhere in the client.** The reader set is closed and exhaustive: the only getter
          for this table (`0xD47494`) has exactly one caller (`0x8932CC`), and a scan of every
          displacement into the table's 296-byte area found just four sites — the startup memset,
          that getter, the `0x4993` handler and this parser. So zero is not merely safe here, it is
          unobservable.
      - id: unknown_05
        type: u1
        doc: |
          [UNKNOWN, and PARSED BUT NEVER READ — 2026-07-29] Position and width exact. **No reader
          exists anywhere in the client.** The reader set is closed and exhaustive: the only getter
          for this table (`0xD47494`) has exactly one caller (`0x8932CC`), and a scan of every
          displacement into the table's 296-byte area found just four sites — the startup memset,
          that getter, the `0x4993` handler and this parser. So zero is not merely safe here, it is
          unobservable.
      - id: unknown_06
        type: u4
        doc: |
          [UNKNOWN, and PARSED BUT NEVER READ — 2026-07-29] Position and width exact. **No reader
          exists anywhere in the client.** The reader set is closed and exhaustive: the only getter
          for this table (`0xD47494`) has exactly one caller (`0x8932CC`), and a scan of every
          displacement into the table's 296-byte area found just four sites — the startup memset,
          that getter, the `0x4993` handler and this parser. So zero is not merely safe here, it is
          unobservable.
      - id: unknown_0a
        type: u4
        doc: |
          [UNKNOWN, and PARSED BUT NEVER READ — 2026-07-29] Position and width exact. **No reader
          exists anywhere in the client.** The reader set is closed and exhaustive: the only getter
          for this table (`0xD47494`) has exactly one caller (`0x8932CC`), and a scan of every
          displacement into the table's 296-byte area found just four sites — the startup memset,
          that getter, the `0x4993` handler and this parser. So zero is not merely safe here, it is
          unobservable.
      - id: name_a
        type: str
        doc: |
          [INFERRED, and PARSED BUT NEVER READ] A 16-byte name field, plausibly the team name — the
          shared clan record at `0xD4AF34` uses 16-byte name fields at `0xD4B180`/`0xD4B284`.

          **Unfalsifiable from the ELF**: nothing reads it, so the inference cannot be confirmed or
          refuted from the binary, and no client behaviour can distinguish a correct value from
          zeros.
      - id: team_id
        type: u4
        doc: |
          [CONFIRMED 2026-07-29] **The team id.** Cached at `0x893304` / `0x89349C` and passed as the
          sole argument to `0xD4A90C` (command `0x4986`, acquire team entry information) and
          `0xD4D9E4` (command `0x491B`, rejoin team).
      - id: name_b
        type: str
        doc: |
          [INFERRED, and PARSED BUT NEVER READ] A 16-byte name field, plausibly the team name — the
          shared clan record at `0xD4AF34` uses 16-byte name fields at `0xD4B180`/`0xD4B284`.

          **Unfalsifiable from the ELF**: nothing reads it, so the inference cannot be confirmed or
          refuted from the binary, and no client behaviour can distinguish a correct value from
          zeros.
      - id: unknown_32
        type: u1
        doc: |
          [UNKNOWN, and PARSED BUT NEVER READ — 2026-07-29] Position and width exact. **No reader
          exists anywhere in the client.** The reader set is closed and exhaustive: the only getter
          for this table (`0xD47494`) has exactly one caller (`0x8932CC`), and a scan of every
          displacement into the table's 296-byte area found just four sites — the startup memset,
          that getter, the `0x4993` handler and this parser. So zero is not merely safe here, it is
          unobservable.
      - id: lobby_id
        type: u2
        doc: |
          [CONFIRMED 2026-07-29] **A lobby id**, in the same id space as `0x4902`'s lobby id at wire
          `0x08` — `0x891458` feeds that field to the same function. Read at `0x893320` / `0x8934D0`
          and passed to `0xD47CE0` -> `0xD35C7C`, which scans the 52-byte lobby array at `ctx+0x750`
          (`0xD35FC4`) and returns the lobby's **ordinal within its subtype group**. The result is set
          as text parameter 254.
      - id: unknown_35
        type: u4
        doc: |
          [UNKNOWN, and PARSED BUT NEVER READ — 2026-07-29] Position and width exact. **No reader
          exists anywhere in the client.** The reader set is closed and exhaustive: the only getter
          for this table (`0xD47494`) has exactly one caller (`0x8932CC`), and a scan of every
          displacement into the table's 296-byte area found just four sites — the startup memset,
          that getter, the `0x4993` handler and this parser. So zero is not merely safe here, it is
          unobservable.
