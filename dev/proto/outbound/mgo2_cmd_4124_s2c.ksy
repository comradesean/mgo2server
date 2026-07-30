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
doc-ref: dev/docs/GEAR.md
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
        doc: |
          [ELF] Table index into `charTable + 9888 + id*12`. Must be `<= 128` or the record is
          silently dropped (`0xD3CF00`).

          **This byte IS the item-ownership gate, confirmed live 2026-07-30.** The record's `+8` is
          read at `0x927350`, and an item whose byte is zero — i.e. one we never sent a record for —
          is **never appended to the wardrobe list**. Verified by stripping a character to a single
          item and reconnecting: every other item vanished from the wardrobe.

          **Beware the empty-category fallback.** A category left with nothing owned does not render
          empty — `0x92751C`-`0x927568` force-equips the category's BASE id (`stb r23,20416`) and
          shows one colourless row. Observed live: emptying upper body and feet produced ids 11 and
          57. The force-equip writes the equipped byte, so a subsequent outfit commit persists it. There is no predicate function, which is why searching for one turned up
          nothing and why "gear has no server-side gate" was wrongly recorded for a day. Five ids
          are exempt at `0x92735C`-`0x927384` (28, 46, 68, 86, 102 — the "None" entries).

          **Only 67 ids exist on this build.** The wardrobe's 9-arm category table at `0x9270AC`
          enumerates fixed `{base, count}` windows: head 28-38, upper body 11-13, lower body 22,
          chest 68-80, waist 86-97, hands 46-51, feet 57-62, accessories 102-116. We send **122**,
          so 55 are phantom — 29 above the 128 bound and 26 in gaps no window covers, every gap
          being the trailing headroom of a category. Inert here; see `dev/docs/POST_LAUNCH.md`.
      - id: colour_mask
        type: u4
        doc: |
          [ELF] Written to gear-table record +12; the unlock_bits loop tests bits of it. Sourced
          from `chara_gear.colours`, which still **defaults to `0xffffffff`** — every colour of
          every item, a blanket unlock inherited from getting the screen working.

          **Only bits 0..23 can ever mean anything, and most items use far fewer.** [ELF] the
          client resolves a swatch through the colour catalogue at VA `0x10506BC` (36-byte records
          `{u32 item_id, u32 colour_index, u32 colour_name_id, ...}`, 1044 rows, 71 item ids,
          terminated by a negative first word at `0x105998C`), scanned by `0x7E2D98`. A miss there
          **skips the swatch before this mask is consulted** (`0x9276F0`, `0x9254FC`), so a set bit
          with no catalogue record does nothing.

          The highest colour index in the whole catalogue is **23**, used by item 110 alone; the
          next is 20, shared by 39 items. **So the top 8 bits of this u32 are dead** in every case.
          The client does not reject them — the trailer parser accepts `bit_index` up to 31
          (`cmplwi cr7,r0,31` at `0xD3CFB0` and `0xD3C8FC`) and the swatch loop runs 0..31
          (`0x927A08`) — they are inert purely because the catalogue never matches.

          **A BIT IS A PER-ITEM SLOT, NOT A GLOBAL COLOUR.** The catalogue record is
          `{item_id, colour_slot, colour_name_ordinal}`: the mask indexes `colour_slot`, and the
          *name* is a separate field reaching 35 — which the trailer's `bit <= 31` bound could not
          even express. So bit 0 is Auscam Desert on item 29, **Black** on item 33, and **Orange**
          on item 103. There is no global colour bitmask and there could not be one; happily
          `chara_gear` already stores one mask per item row, which is the right shape.

          Item 105 shows why this matters: it has slots 0-7 (`0x000000FF`) but name ordinals
          `{15,16,17,19,20,21,23,24}` — it skips two. Reading its mask against a global colour list
          would name the wrong colours.

          **Every item's slot set is a contiguous `0..n-1` run**, so `mask == (1 << n) - 1`
          exactly and there are only seven distinct legal masks across the 67 reachable items:
          `0x001FFFFF` x39, `0x00000001` x10, `0x000003FF` x6, `0x000000FF` x3, `0x0000001F` x3,
          `0x0000003F` x1, `0x00FFFFFF` x1. A per-item colour COUNT is therefore lossless; a
          bitmask is only needed if policy wants to punch holes in a run.

          **Items 28, 68, 86 and 102 have no catalogue records at all** and are the "None" entries
          of their categories — already unconditionally owned by a hardcoded id comparison at
          `0x92735C`-`0x927384`. Sending records for them is a no-op in both directions.
  unlock_pair:
    doc: |
      **Grants nothing.** [ELF `0xD3CFBC`-`0xD3CFE4`] the parser ORs a pair into record `+16` **only
      if that bit is already set** in the colour mask at record `+12`, so a pair can only ever
      produce a subset of what the record already carried; one naming an unowned colour does
      nothing at all.

      `+16` is read at `0x92740C` and `0x927744` on a secondary path — a wardrobe highlight or
      "new" marker, **not availability**. Availability is record `+8` (item ownership, tested at
      `0x927350`) and record `+12` (per colour, `0x925538` / `0x92772C`).

      We send `0xff` filler in unused slots, which the parser skips because item 255 exceeds its
      128-entry bound. Populated from `gear_colour_highlight`, which is empty by default — so the
      tail is normally 32 bytes of filler, exactly as before the table existed.
    seq:
      - id: item_id
        type: u1
        doc: "[ELF] Must be <= 128 or the pair is skipped."
      - id: bit_index
        type: u1
        doc: "[ELF] Must be <= 31 or the pair is skipped."
