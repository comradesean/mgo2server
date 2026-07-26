meta:
  id: mgo2_cmd_4964_s2c
  title: "MGO2 0x4964 — server -> client: clan notification carrying one 4-byte word"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: reply dispatcher `0xD38804` matches `cmpwi 0x4964` at `0xd38cbc` and branches to the
  thunk at `0xd397a0`, which tail-calls the parser at `0xd4c5ec`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **12** via `0xD33CD8(ctx, 12)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a single 4-byte read into a stack slot. This wrapper does **no** post-processing
  at all beyond raising event 12 — the word never reaches the clan record in this function
  [READ 0xd4c688-0xd4c6bc]. Payload 10 bytes.

doc-ref: dev/docs/COMMANDS.md
seq:
  - id: clan_id
    type: u4
    doc: |
      [ELF 0xd49274] Must equal the client's cached clan id (`clan+0x000`) or the packet is
      dropped with `-1018`.
  - id: clan_serial
    type: u2
    doc: |
      [ELF 0xd492b0] Must equal the u16 at `clan+0x29C` — the serial the clan-record replies
      set and `0x49a8` updates. Mismatch -> `-1018`, packet dropped.
  - id: unknown_06
    type: u4
    doc: |
      [UNKNOWN] read and consumed; not stored by this parser. Position exact. By analogy with
      its siblings (0x4960/0x4965/0x4966/0x4967) it is a character id, but that is [INFERRED]
      from the family, not from this function.
