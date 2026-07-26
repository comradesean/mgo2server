meta:
  id: mgo2_cmd_4925_s2c
  title: "MGO2 0x4925 — server -> client: clan notification carrying u32 + 16-byte string"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: reply dispatcher `0xD38804` matches `cmpwi 0x4925` at `0xd38c5c` and branches to the
  thunk at `0xd39750`, which tail-calls the parser at `0xd4ce0c`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **8** via `0xD33CD8(ctx, 8)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then u32 and a 16-byte raw block. The u32 lands at clan+0x280; the 16 bytes are
  copied over clan+0x284 after that field is cleared to 17 bytes, and if the string is
  non-empty the flag word at clan+0x094 gets 0x40 set [READ 0xd4cf28-0xd4cf64]. Those are the
  `unknown_g` / `name_b` pair of the shared clan record — this is a rename of that pair.
  Payload 26 bytes; event 8.

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
    doc: "[UNKNOWN] -> clan+0x280 (`unknown_g` of the shared clan record)."
  - id: name
    type: str
    size: 16
    doc: |
      [INFERRED] -> clan+0x284 (`name_b` of the shared clan record). A non-empty value sets
      0x40 in the clan flag word at clan+0x094 [ELF 0xd4cf4c], which is the flag bit 1 of the
      clan record's `flags` byte — so bit 1 means "this string is set".
