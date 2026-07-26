meta:
  id: mgo2_cmd_4302_s2c
  title: "MGO2 0x4302 — server -> client: game-list entries (reply 2/3 to 0x4300)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x4302` at `0xD3881C` -> stub `0xD391B0` ->
  parser **`0xD43D48`**. Read primitives: `0xD5CCD8` u32, `0xD5CB8C` u8, `0xD5CC14` u16,
  `0xD5D018` raw block, `0xD5CEB0` remaining-bytes test.

  **The entry is 55 (`0x37`) bytes and the packet carries as many as fit.** The parser loops:
  zero a 60-byte scratch struct, ask `0xD5CEB0` whether the read cursor has reached the
  payload length (`-1` = done, exit clean), read one entry, append it, repeat. So the record
  count is **size-driven — there is no count field**, and the entry stride in the client's
  array is 60 bytes even though the wire record is 55.

  **Correction to PROTOCOL.md:** it says "up to 18 entries". That is a server-side policy
  number, not the client's limit — the parser's own cap is `count > 999 -> -71`, so the array
  holds **1000** entries. (The transport still caps a payload at `0x400` bytes, which is 18
  entries plus change, so 18 per packet is the real per-frame ceiling; the client will accept
  more packets into the same open transfer.)

  **Correction to PROTOCOL.md's tail:** it lists `0x34` as "2 bytes zero" and `0x36` as a u8
  "always `0x63`". The parser reads a **u8 at `0x34`** and then a **u16 at `0x35`** — so the
  famous `0x63` is the low byte of a halfword whose value is `0x0063` (99). Same 55 bytes,
  different field boundaries.

  Appended at `G+8 + count*60` (first 32 bytes) and `G+40 + count*60` (next 28), with
  `count` at `G+4`; `G` is the game-list object shared with `0x4301`/`0x4303`.
  `T+0x..` below is the offset inside that 60-byte client struct.

  Field *meanings* are PROTOCOL.md's, live-derived from the browser; the widths and order
  are the parser's.
doc-ref: dev/docs/PROTOCOL.md "0x4302 entry — 55 (0x37) bytes"
seq:
  - id: entries
    type: game_entry
    repeat: eos
    doc: |
      [ELF 0xD43D48] Size-driven, **no leading count**. This project has been bitten by
      count-vs-size before (`dev/proto/README.md`: sending a count in a list-start packet
      produced `1032:00000005`), so it is worth restating: the count here is maintained by
      the client, incremented per record, and capped at 999.
types:
  game_entry:
    doc: "55 bytes on the wire, 60 in the client's array."
    seq:
      - id: game_id
        type: u4
        doc: "[CONFIRMED] wire 0x00 -> T+0x00. Game id. [ELF 0xD43DFC]"
      - id: name
        size: 16
        doc: "[CONFIRMED] wire 0x04 -> T+0x04. Game name, ISO-8859-1, NUL-padded. Raw 16-byte read (0xD5D018), not length-prefixed."
      - id: host_options
        type: u1
        doc: |
          [CONFIRMED] wire 0x14. Read into a temporary and **expanded bit by bit** into three
          separate client bytes: bit 0 -> T+0x15, bit 1 -> T+0x16, bit 2 -> T+0x17. PROTOCOL.md
          names bit 0 = password set and bit 1 = dedicated; **bit 2 is also expanded and its
          meaning is [UNKNOWN]** — the parser stores it exactly like the other two, so it is a
          real flag the browser can read, not padding.
      - id: unknown_15
        type: u1
        doc: "[UNKNOWN] wire 0x15 -> T+0x18. PROTOCOL.md: \"always 0x08\". Stored in its own byte; nothing is known about what reads it."
      - id: rule
        type: u1
        doc: "[CONFIRMED] wire 0x16 -> T+0x19. Match rule."
      - id: map
        type: u1
        doc: "[CONFIRMED] wire 0x17 -> T+0x1a."
      - id: unknown_18
        type: u1
        doc: "[UNKNOWN] wire 0x18 -> T+0x1b. PROTOCOL.md: zero, purpose unknown."
      - id: max_players
        type: u1
        doc: "[CONFIRMED] wire 0x19 -> T+0x1c."
      - id: stance
        type: u1
        doc: |
          [CONFIRMED] wire 0x1a -> **T+0x24**. Note the out-of-order destination: the parser
          reads this byte here but stores it past the two toggle bytes and the player count.
          Wire order is what matters for a server; the struct offset is recorded because it is
          the only reason the read sequence looks shuffled.
      - id: common_toggles
        size: 2
        doc: |
          [CONFIRMED] wire 0x1b..0x1c -> T+0x1d..0x1e. **Read as one 2-byte raw block**
          (`0xD5D018` size 2), not as two u8s — commonA then commonB. Bit maps in PROTOCOL.md:
          commonA bit 0 idle kick, bit 2 always set (unknown), bit 3 friendly fire, bit 4
          ghosts, bit 5 auto-aim, bit 7 uniques; commonB bit 0 team switch, bit 1 auto-assign,
          bit 2 silent mode, bit 3 enemy nametags, bit 4 level limit, bit 6 voice chat,
          bit 7 team-kill kick. Capture-proven for the 0x4310 push (OBSERVED.md, "Where the
          Common Settings toggles live"); the same bitfields are replayed here.
      - id: player_count
        type: u1
        doc: "[CONFIRMED] wire 0x1d -> T+0x1f. Current player count."
      - id: ping
        type: u4
        doc: "[CONFIRMED] wire 0x1e -> T+0x20. Host ping, fed from the 0x4398 report."
      - id: friend_block_flags
        type: u1
        doc: "[ELF] wire 0x22 -> T+0x25. PROTOCOL.md: bit 0 contains a friend, bit 1 contains a blocked player — always 0 from this server, neither list is modelled, so the bit names are unverified against the browser."
      - id: level_limit_tolerance
        type: u1
        doc: "[CONFIRMED] wire 0x23 -> T+0x26."
      - id: level_limit_base
        type: u4
        doc: "[CONFIRMED] wire 0x24 -> T+0x28. Capture-proven as a u32 in the 0x4310 push (at push offset 0xF8); an earlier u16-at-0x142 reading was a bug (OBSERVED.md)."
      - id: average_experience
        type: u4
        doc: "[CONFIRMED] wire 0x28 -> T+0x2c. Average experience across current players."
      - id: host_score
        type: u4
        doc: "[CONFIRMED] wire 0x2c -> T+0x30."
      - id: host_votes
        type: u4
        doc: "[CONFIRMED] wire 0x30 -> T+0x34."
      - id: unknown_34
        type: u1
        doc: "[UNKNOWN] wire 0x34 -> T+0x38. PROTOCOL.md folds this into a 2-byte zero region; the parser reads it as its own u8."
      - id: unknown_35
        type: u2
        doc: |
          [UNKNOWN] wire 0x35 -> T+0x3a. **A u16, not the u8 PROTOCOL.md places at 0x36.**
          PROTOCOL.md reports the last byte as "always 0x63", which makes this halfword
          `0x0063` = 99. Whether the game reads it as a small number or as two flags is
          unestablished; the value is suspiciously equal to the `0x4902` entry size, which is
          probably coincidence.
