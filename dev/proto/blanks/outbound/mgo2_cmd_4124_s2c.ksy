meta:
  id: mgo2_cmd_4124_s2c
  title: "MGO2 0x4124 — gear catalogue, packet 6/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Parser **0xd3ce30** (GAME dispatcher 0xd38804, trampoline 0xd39060). Byte-for-byte the same
  parser shape as `0x4133` (0xd3c77c) writing into the same table, so the two specs should be read
  together.

  Layout: `u32 count`, then `count x {u8 item_id, u32 colour_mask}`, then a **fixed 16** pairs of
  `{u8 item_id, u8 bit_index}`.

      0xd3ceb8  u32 count -> scratch
      0xd3cecc  loop: u8 id, u32 mask     entry at the *bottom* (0xd3cec4 beq -> 0xd3cf28),
                                          so count == 0 reads zero records.
                                          exits when `i >= count` OR `i == 129`
      0xd3cf64  loop x16: u8 id, u8 bit   (bound `cmpwi cr6,r31,15`, pre-increment compare)

  Records land in the gear table at `charTable + 9888 + id*12`, 12 bytes written at +8; ids > 128
  are **skipped, not an error**. The second loop reads a colour-unlock bit: for each pair it
  checks bit `bit_index` of the mask at record +12 and, if set, ORs it into record +16; both
  `id > 128` and `bit > 31` skip silently.

  ### Correction to PROTOCOL.md: the trailing 32 bytes are not a terminator

  PROTOCOL.md documents `0x26b: 32 bytes of 0xff` as a "terminator" and flags "whether the 32
  `0xff` bytes are a terminator or a fixed-size trailing field is also a guess". Neither: they are
  **16 `{u8 item_id, u8 bit_index}` pairs**, read by a fixed 16-iteration loop. `0xff` works as a
  no-op only because item id 255 > 128 makes every pair skip. The size we send (651 =
  4 + 123*5 + 32) is correct.
doc-ref: dev/docs/PROTOCOL.md "0x4124 — gear catalogue, 651 bytes"
seq:
  - id: count
    type: u4
    doc: |
      [ELF] Wire 0x00. Number of item records that follow. Loop-exit is `i >= count` **or**
      `i == 129`, so at most 129 records are ever read however large the count; a count larger
      than the payload would read stale buffer, since the primitives never check payload length.
      We send 123.
  - id: items
    type: item_record
    repeat: expr
    repeat-expr: count
    doc: "[ELF] 5 wire bytes each. The 123 item ids are a data table (`LoadoutWriter.GEAR_ITEMS`), not a derivable sequence; PROTOCOL.md flags that `0x86` appears twice in our copy and that this is unchecked."
  - id: unlock_bits
    type: unlock_pair
    repeat: expr
    repeat-expr: 16
    doc: "[ELF] **Exactly 16**, always read, regardless of `count`. We send 32 bytes of 0xff, which every pair then skips."
types:
  item_record:
    seq:
      - id: item_id
        type: u1
        doc: "[ELF] Table index. Must be <= 128 or the record is silently dropped (0xd3cf00)."
      - id: colour_mask
        type: u4
        doc: "[ELF] Written to gear-table record +12; the unlock_bits loop tests bits of it. We send 0xffffffff (every colour owned) for every item."
  unlock_pair:
    doc: "Grants one colour bit: if bit `bit_index` is set in the item's `colour_mask`, it is ORed into the item's record at +16."
    seq:
      - id: item_id
        type: u1
        doc: "[ELF] Must be <= 128 or the pair is skipped."
      - id: bit_index
        type: u1
        doc: "[ELF] Must be <= 31 or the pair is skipped."
