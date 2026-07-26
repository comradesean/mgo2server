meta:
  id: mgo2_cmd_4919_s2c
  title: "MGO2 0x4919 — server -> client: clan notification carrying one 4-byte word"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: reply dispatcher `0xD38804` matches `cmpwi 0x4919` at `0xd38bf8` and branches to the
  thunk at `0xd39710`, which tail-calls the parser at `0xd4d428`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This is an **unsolicited clan notification**, not a reply: there is no result code and no
  request-status slot. The parser ends by raising client event **2** via `0xD33CD8(ctx, 2)`.

  The payload opens with the 6-byte key read by the shared helper `0xD49230(ctx, clan, reader)`:
  a u32 compared against the client's cached clan id (`clan+0x000`) and a u16 compared against
  `clan+0x29C`. Either mismatch returns `-1018` (`0xFFFFFC06`) and the packet is **discarded
  silently** — no dialog, no state change. So both words gate delivery; they are not payload.
  (`0x4960` is the one exception: the helper skips both comparisons for that id.)

  Header, then a single 4-byte read. The value is bounds-tested against 7 (`cmplwi 7`,
  `ble`) before being used as an index into the 8-entry member array [READ 0xd4d4f4], and one
  28-byte member slot is zeroed at the end [READ 0xd4d534]. So the word is a **member slot
  index 0-7**, not a character id — a value above 7 makes the parser skip the mutation but it
  still raises event 2.

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
  - id: member_slot
    type: u4
    doc: |
      [ELF 0xd4d4c8] Member array index; values above 7 are ignored (`cmplwi 7` / `ble` at
      0xd4d4f4). The matching 28-byte slot is zeroed. [INFERRED] role from that use; the
      field has no label in the binary.
