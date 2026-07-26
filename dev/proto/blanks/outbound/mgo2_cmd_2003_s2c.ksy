meta:
  id: mgo2_cmd_2003_s2c
  title: "MGO2 0x2003 — gate lobby-list entries (server -> client)"
  endian: be
doc: |
  Reply 2/3 to `0x2005`: the gate's list of lobbies and their addresses. Parser arm 0xd362b0
  (GATE dispatcher 0xd361a4 (compare tree at 0xd361e8)), records appended to `ctx+0x750`.

  **Record count is size-driven, not led by a count field.** The arm loops on `MORE_DATA?`
  (0xd5ceb0, "cursor < payload length"): each pass reads one 46-byte entry and `memcpy`s it into
  `ctx+0x75C + n*0x34`, then increments the persistent count at `4(r28)`. Records accumulate
  across multiple `0x2003` packets.

  **Client capacity is 32 entries total**, not per packet: `lwz r4,4(r28); cmpwi r4,31; bgt ->
  bail(-71)` at 0xd363fc. Overflowing it aborts the whole parse, losing the list. PROTOCOL.md's
  22-per-packet batching is our own policy and is comfortably inside the cap; the cap is on the
  *total*, so more than 32 lobbies would break the client regardless of batching.

  Note the two different strides that both appear in the docs and are both right: **46 bytes on
  the wire**, **52 (0x34) bytes in the client struct** (per-field read destinations below).

  Read primitives in order (0xd36328 .. 0xd363e4): u32, u32, fixed[16], fixed[15], u16, u16,
  u16, u8 = 46 bytes. `fixed[n]` is 0xd5d018, which copies exactly n wire bytes and then writes
  a NUL at dest[n] — hence the +1 in the struct offsets.

  Everything here is [CONFIRMED] end to end: OBSERVED.md records this list read back out of the
  client's own memory at `ctx+0x75C` in 0x34-byte strides with every field correct.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x2003 entry — 46 (0x2e) bytes"; dev/docs/LOBBIES.md
seq:
  - id: entries
    type: lobby_entry
    repeat: eos
    doc: |
      [ELF] Repeat to end of payload — the client's own loop condition is `MORE_DATA?`. Ordering rule
      (learned the hard way, LOBBIES.md): order by **lobby id**, not name, so that list index
      and lobby type coincide.
types:
  lobby_entry:
    doc: "46 wire bytes; 52 bytes in the client's struct at ctx+0x75C + n*0x34."
    seq:
      - id: list_index
        type: u4
        doc: "[CONFIRMED] Wire 0x00 -> struct +0x00. List index, counting from 0 across all packets."
      - id: lobby_type
        type: u4
        enum: lobby_kind
        doc: "[CONFIRMED] Wire 0x04 -> struct +0x04. See LOBBIES.md: three values, not a taxonomy."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        doc: "[CONFIRMED] Wire 0x08 -> struct +0x08 (17 bytes: reader NUL-terminates at dest[16]). NUL-padded."
      - id: ip
        size: 15
        type: str
        encoding: ISO-8859-1
        doc: "[CONFIRMED] Wire 0x18 -> struct +0x19. Dotted-quad string, NUL-padded. Every connect resolves through this."
      - id: port
        type: u2
        doc: "[CONFIRMED] Wire 0x27 -> struct +0x2a. Read by 0xd5cc14 (2-byte primitive)."
      - id: player_count
        type: u2
        doc: |
          [CONFIRMED] Wire 0x29 -> struct +0x2c. Read by 0xd5cbc4. Players currently **in games**
          in that lobby — operator policy, see LOBBIES.md; idle members are not counted.
      - id: lobby_id
        type: u2
        doc: "[CONFIRMED] Wire 0x2b -> struct +0x2e. Read by 0xd5cc14."
      - id: restrictions
        type: u1
        doc: |
          [ELF] Wire 0x2d -> struct +0x30. Bits per PROTOCOL.md: 0b1 beginners only,
          0b1000 expansion required, 0b10000 no headshots. **Never exercised** — we always send
          0 (LOBBIES.md), so the bit meanings are tier-4 transcription, not confirmed here.
enums:
  lobby_kind:
    0: gate
    1: account
    2: game
