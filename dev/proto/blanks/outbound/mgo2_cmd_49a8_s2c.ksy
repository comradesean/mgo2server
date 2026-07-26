meta:
  id: mgo2_cmd_49a8_s2c
  title: "MGO2 0x49a8 — server -> client: clan notification — serial bump (u16 payload)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: reply dispatcher `0xD38804` matches `cmpwi 0x49a8` at `0xd38d28` and branches to the
  thunk at `0xd39810`, which tail-calls the parser at `0xd4be3c`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **18** via `0xD33CD8(ctx, 18)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a single u16 written to **clan+0x29C** [READ 0xd4bf10] — the very field the
  header's own second word is validated against. So `0x49a8` is how the server advances the
  clan record's serial: the packet must arrive carrying the *current* serial in its header and
  the *new* one in its body. Payload 8 bytes; event 18.

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
  - id: new_clan_serial
    type: u2
    doc: |
      [ELF 0xd4bf10] Written to clan+0x29C, replacing the value that `clan_serial` above had
      to match. [INFERRED] role as a serial/version bump from that use; the field is unlabelled
      in the binary.
