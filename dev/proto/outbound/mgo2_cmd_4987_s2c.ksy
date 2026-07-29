meta:
  id: mgo2_cmd_4987_s2c
  title: "MGO2 0x4987 — server -> client: clan record + 204-byte block (shared 0xD4AF34 layout)"
  endian: be
  encoding: ISO-8859-1
doc: |
  Evidence: GAME reply dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4987` at `0xd38cfc` and branches to the
  thunk at `0xd396f0`, which tail-calls the parser at `0xd4d770`. Channel A (lobby TCP).

  Read primitives used throughout (identified from their own disassembly, not borrowed):
  `0xD5CB8C` u8, `0xD5CC14` u16, `0xD5CC64` / `0xD5CCD8` 4-byte (byte-identical twins),
  `0xD5D018` raw block of `r5` bytes, `0xD5C844` rewind-for-read, `0xD5C858` end-of-read.
  Every reader bound-checks against the **1023-byte receive buffer, not the payload length**,
  so a short payload does not fail — it silently reads whatever follows in the buffer.

  This id is one of **six** routed into the shared clan-record parser `0xD4AF34`
  (`0x4911`, `0x4913`, `0x4985`, `0x4987`, `0x49A1`, `0x49B1`; compare tree at
  `0xd4af98-0xd4afd8`). All six carry the **same 420-byte payload**, except `0x4987`, which
  inserts a 204-byte sub-block (see that file). The per-id wrapper only differs in the
  request-status slot it completes.

  Structure of the shared parser: verify the id, 4-byte result; **if the result is nonzero
  every field below is skipped** and only the request slot is completed [READ 0xd4b084].
  On success the 680-byte clan record is filled. For `0x4985`/`0x49B1` the record is first
  memset to 680 bytes and the leading id is cross-checked against a context value
  [READ 0xd4b0b8-0xd4b0e0]; for the other four the existing record is reset via `0xD49368` /
  `0xD4EC14` and reused. The wire layout is identical either way.

  The 8-entry member array is a **fixed loop of eight** (`cmpwi cr6,r26,7`), not
  count-driven [READ 0xd4b254-0xd4b2e4]: 25 wire bytes per member, 28-byte stride in the
  struct. Record the distinction — a leading count is not present.

  Wrapper `0xd4d770`: on a `-1` return from the shared parser it does nothing; otherwise it
  completes request-status slot **72** with the result via `0xD32E08`/`0xD32E70`.

  **`0x4987` is the only variant with an extra field.** After the flag byte the parser
  branches on the id and reads a 204-byte block via `0xD4364C` into clan+0x0B0
  [READ 0xd4b230-0xd4b244], making its payload **624 bytes** instead of 420. It is also
  the only one with post-processing: on success it copies clan+0x25C/0x260/0x261 into a
  roster object and, if a game entry matching clan+0x25C exists, copies 64 bytes of text
  into it [READ 0xd4b46c-0xd4b51c]. The 204-byte block is the same one 0x4909 and 0x4950
  read; see `mgo2_cmd_4909.ksy` for its field-by-field layout, which is not duplicated
  here.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xd4b074] 0 = success; nonzero ends the parse here (4-byte payload). s4 is on
      CALLER evidence — the thunk reloads the out-param with `lwa` before publishing it to
      0xD32E70 (e.g. 0xD4B5A8) — not on the read primitive, which is byte-identical to
      0xD5CCD8 and is not a signed accessor.
  - id: clan_id
    type: u4
    doc: |
      [ELF 0xd4b0a8 / 0xd4b128] Stored at clan+0x000. This is the value every clan-event
      notification's header word is compared against (helper `0xD49230`), so it is the client's
      identity for the clan. For 0x4985/0x49b1 it is additionally checked against a context
      value and a mismatch aborts the whole reply.
  - id: clan_serial
    type: u2
    doc: |
      [ELF 0xd4b148] Stored at clan+0x29C — read SECOND on the wire but living far down the
      struct. This is the u16 the clan-event headers are validated against, and the value
      `0x49a8` updates. [UNKNOWN] meaning; it behaves as a record version/serial.
  - id: unknown_0a
    type: u1
    doc: "[UNKNOWN] clan+0x004."
  - id: tag
    type: str
    size: 16
    doc: "[INFERRED] clan+0x005, 16-byte raw block; name-width by analogy. Width is [ELF 0xd4b184]."
  - id: comment
    type: str
    size: 128
    doc: |
      [INFERRED] clan+0x016, 128-byte raw block — the same width as the player comment in
      0x4221 and the mailbox comment field. Width is [ELF 0xd4b1a4].
  - id: flags
    type: u1
    doc: |
      [ELF 0xd4b1b4-0xd4b22c] Read as a 1-byte raw block; **only three bits are expanded**
      into the u32 at clan+0x094: wire bit 0 -> 0x80, bit 1 -> 0x40, bit 2 -> 0x10. Bits 3-7
      are read and discarded. A zero byte is also unconditionally stored at clan+0x097.
      Individual meanings [UNKNOWN].
  - id: block_204
    size: 204
    doc: |
      [ELF 0xd4b238] Present for 0x4987 only. Read by the shared reader 0xD4364C into
      clan+0x0B0. Its internal layout is modelled canonically in `mgo2_cmd_4313_s2c.ksy`,
      type `game_settings` — the copy whose names are capture-backed (OBSERVED.md);
      `mgo2_cmd_4909.ksy` type `block_204` is a second mirror. Kept opaque here so the copies
      cannot drift. 0xD4364C has nine call sites; the list is in `mgo2_cmd_4909.ksy`.
  - id: members
    type: member
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 0xd4b254-0xd4b2e4] Exactly eight member records; the loop bound is hardcoded.
      25 wire bytes each, 28-byte struct stride starting at clan+0x17C.
  - id: unknown_a
    type: u4
    doc: "[UNKNOWN] clan+0x25C. Also written by the 0x4922 notification."
  - id: unknown_b
    type: u1
    doc: "[UNKNOWN] clan+0x260. Also written by the 0x4922 notification."
  - id: unknown_c
    type: u1
    doc: "[UNKNOWN] clan+0x261."
  - id: unknown_d
    type: u2
    doc: "[UNKNOWN] clan+0x262."
  - id: unknown_e
    type: u2
    doc: "[UNKNOWN] clan+0x264."
  - id: unknown_f
    type: u4
    doc: "[UNKNOWN] clan+0x268."
  - id: name_a
    type: str
    size: 16
    doc: "[INFERRED] clan+0x26C, 16-byte raw block. Width is [ELF 0xd4b3a0]."
  - id: unknown_g
    type: u4
    doc: "[UNKNOWN] clan+0x280. Also written by the 0x4925 notification, immediately before its 16-byte string."
  - id: name_b
    type: str
    size: 16
    doc: |
      [INFERRED] clan+0x284, 16-byte raw block. The 0x4925 notification rewrites this pair
      (u32 + 16 bytes) on its own, so they travel together.
  - id: unknown_h
    type: u2
    doc: "[UNKNOWN] clan+0x296 — note the 2-byte gap after the string ends at 0x294."
  - id: unknown_i
    type: u4
    doc: "[UNKNOWN] clan+0x298."
  - id: unknown_j
    type: u4
    doc: |
      [UNKNOWN] clan+0x2A0, read at 0xD4B428 with the 0xD5CC64 twin. **Signedness [UNKNOWN]** —
      RESOLVED-AS-UNKNOWN 2026-07-26: this file typed it s4 and `mgo2_cmd_49b1_s2c.ksy`, on the
      same parser and the same read, typed it u4. Neither had evidence: 0xD5CC64 is
      byte-identical to 0xD5CCD8 and is not a signed accessor, nothing reloads clan+0x2A0 with
      `lwa`, and no consumer was traced. Unified on u4 as the corpus default for an unproven
      4-byte read; that is a default, not a claim.
  - id: unknown_k
    type: u4
    doc: |
      [UNKNOWN] clan+0x2A4, read at 0xD4B444; last field, the record is 680 bytes. Signedness
      [UNKNOWN] for the same reason as unknown_j.
types:
  member:
    doc: "25 wire bytes, 28-byte struct stride (clan+0x17C + 28*n)."
    seq:
      - id: character_id
        type: u4
        doc: |
          [INFERRED] member+0x00. Named from use, not from a label: the 0x4960/0x4964-0x4967
          notifications carry a single u32 and locate the member slot whose first word matches
          it, and 0x4950 does the same before overwriting a slot. Value semantics [UNKNOWN].
      - id: name
        type: str
        size: 16
        doc: "[INFERRED] member+0x04, 16-byte raw block. Width is [ELF 0xd4b290]."
      - id: unknown_15
        type: u1
        doc: |
          [UNKNOWN] member+**0x15** — DOC CORRECTION 2026-07-26; wire widths unchanged. Earlier
          revisions said member+0x11, which contradicted this type's own 16-byte name at +0x04
          (it occupies +0x04..+0x13, with 0xD5D018's NUL at +0x14). The ELF: the slot loop sets
          `addi r28,r31,384` (0xD4B258) and `addi r27,r31,368` (0xD4B25C), so the slot base is
          r27+12 = r31+380 and the name buffer r28 = r31+384 = slot+0x04. This read is
          `addi r4,r28,17` (0xD4B298) = r31+401 = **slot+0x15**. `mgo2_cmd_49b1_s2c.ksy` had it
          right all along. The notifications write literal values here (0x4960 stores 4, 0x4932
          and others store small constants), so it is a per-member state byte.
      - id: unknown_18
        type: u4
        doc: |
          [UNKNOWN] member+**0x18** — same DOC CORRECTION: `addi r4,r28,20` (0xD4B2B4) =
          r31+404 = slot+0x18, not +0x14. 4 + 16 + 1 + 4 = 25 wire bytes against a 28-byte
          struct stride; the seq above was and remains correct on the wire.
