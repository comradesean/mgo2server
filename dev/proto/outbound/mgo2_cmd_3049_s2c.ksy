meta:
  id: mgo2_cmd_3049_s2c
  title: "MGO2 0x3049 — character list (server -> client)"
  endian: be
doc: |
  Reply to `0x3048`. Parser arm **0xd3732c** (ACCOUNT dispatcher 0xd37024 (compare tree at 0xd37074)), wait slot 14 (0xe).
  Total **0x1d7 = 471 bytes**, and the grid is **fixed regardless of how many characters exist**:
  the entry loop is `li r24,0 ... cmpwi r24,420; addi r24,r24,60; bne` at 0xd37740 — exactly
  **8 iterations**, count-independent, with no `MORE_DATA?` check anywhere.

  Structure, fully traced:
    * u32 result. **Non-zero skips the entire rest of the packet** (0xd3739c `cmpwi r0,0; bne ->
      0xd3776c`), so an error reply is legitimately four bytes (`C0FFEE02`).
    * a **23-byte header** — `u32 result, u8 slots, u8 count, u8 selected_slot,
      char selected_name[16]` — then 8 **uniform** entries of 52 wire bytes, then a 32-byte tail.
    * 23 + 8*52 + 32 = 471. Confirms PROTOCOL.md's size and shape exactly.

  FALSIFIED READING OF THE ENTRY SHAPE (live 2026-07-27, commits 8617e21 / 0b0f93e). Our writer
  had introduced the FIRST entry with its name and every LATER entry with a 4-byte index, i.e. it
  treated the entries as varying by position; and it wrote 28 bytes of appearance where the
  layout has 31. **The entries are uniform. There is no per-entry variation.** The two errors
  cancelled to exactly 52 bytes for a single-character account, so the packet looked correct for
  as long as only one character existed, and the second entry ran three bytes long the moment a
  second did. Both halves are corrected: real 23-byte header, uniform 52-byte entries, with the
  three recovered bytes belonging to `delete_cooldown_seconds` below.

  This is the shape of bug this packet keeps producing: every field in a single-entry list looks
  right whether or not it means what we think it means.

  Client struct destinations: header at `ctx+21968` (0x55D0), the 16-byte name into `ctx+22492`
  — **the same slot `0x4101` writes its character name into** (`0x4101`'s base is `ctx+22488`,
  name at +4) — entries at `ctx+21972 + n*60`, tail at `ctx+22452`. The entry region is memset to
  480 (= 8*60) bytes before parsing (0xd3737c).

  After `READ_END` the parser scans the 8 entries for the one whose slot byte equals the
  `selected_slot` header field (0xd37778: `lbz r4,2(r27); cmplwi r4,7; bgt -> skip`), so
  `selected_slot` is an index into the *slot numbers*, bounded at 7.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x3048 — get character list"; dev/docs/OBSERVED.md
seq:
  - id: result
    type: u4
    doc: "[CONFIRMED] Wire 0x00. Zero gates everything below; `C0FFEE02` if the connection has not checked in."
  - id: slots
    type: u1
    doc: |
      [ELF] Wire 0x04 -> ctx+21968. PROTOCOL.md names it `slots`: how many character slots this
      account may fill.

      **OPERATOR POLICY, not protocol** (per CLAUDE.md's spec/policy/presentation split). The
      packet has room for 8 entries and the client would carry more without complaint; the retail
      service SOLD the extra slots. Our default is 1, bounded 1..4 by a database constraint, and
      granted per account with an UPDATE — a policy choice, and a deliberately different one from
      the 3 we had inherited. Nothing in the binary fixes this number.
  - id: count
    type: u1
    doc: "[ELF] Wire 0x05 -> ctx+21969. Character count. **Not** a repeat count — the 8 entries are read unconditionally."
  - id: selected_slot
    type: u1
    doc: |
      [CONFIRMED live 2026-07-27] Wire 0x06 -> ctx+21970. The slot of the character this account
      currently has selected. Bounded at 7 by the post-parse scan at 0xd3777c.

      **Load-bearing — this field IS the selection, as far as the client is concerned.** After the
      player picks a character with `0x3103` the client RE-FETCHES this list and takes its
      selection back out of this header. Reporting a hardcoded 0 (with the first character's name
      beside it) made the client forget the choice every time: picking the second character and
      entering the lobby logged the player in as the first. It must carry the slot of the
      account's current character, and `selected_name` must match it.
  - id: selected_name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: |
      [ELF] Wire 0x07 -> ctx+22492, i.e. the same destination as 0x4101's character name. Must be
      the name of the character in `selected_slot`; see that field.
  - id: entries
    type: character_entry
    repeat: expr
    repeat-expr: 8
    doc: "[CONFIRMED] Always 8, always read. 52 wire bytes each; 60 bytes per entry in the client struct."
  - id: item_unlock_trailer
    size: 32
    doc: |
      [CONFIRMED 2026-07-29] **32 bytes, and index 3 bit 0 is load-bearing: it unlocks 32 of the 91
      CODEC / preset messages.** Do not zero this unless you mean to.

      **Corrected 2026-07-29, live.** This said "32 of the 91 selectable loadout items", from a
      trace of the availability predicate. Clearing the bit on one account removed the CODEC
      message list and left gear and outfits completely unchanged, so the 85-entry table at
      `0xE1812C` is a preset-message table, not a loadout one. The 32 are almost certainly the
      day-one paid "MGO Codec Pack" (32 additional voice tracks, bound to the Konami ID — which
      matches this being per-account). Tier 2 beats a derived label.

      Two readers, both of `ctx+22455` (index 3): `0x9B9E30` computes `(byte & 1) << 4` — 0 or 16 —
      and `0x9BADA4` tests `byte & 1` to choose between two list-builders. The 16 is a threshold: the
      availability predicate `0x9B9DF0` walks an 85-entry table at `0xE1812C` and refuses any item
      whose gate exceeds it. **32 entries gate on exactly 16**, 23 gate on 0 and are always
      available, and 27 defer to a separate ownership/expansion check (`0x9C0600`/`0x9C2C90`).

      We send `0x03`. **Only bit 0 is read** — bit 1 has no reader, nor do indices 0, 2 and 4..31, so
      the `0x07` we send at index 1 is inert.

      **32 bytes, not 35** — the parser `0xD3732C` copies exactly 32 (`li r5,32` at `0xD3774C`).
      `PROTOCOL.md` once described a 35-byte trailer with `07` at +4 and `03` at +6; subtracting the
      phantom three lands those on indices 1 and 3, exactly where they are.
types:
  character_entry:
    doc: |
      52 wire bytes -> 60-byte struct entry. Field-by-field read destinations are given as struct
      offsets within the entry; the gaps (struct +1..3, +24, +34/35, +54..55) are never written by
      the parser.
    seq:
      - id: slot
        type: u1
        doc: "[ELF] Wire +0 -> entry +0. Matched against `selected_slot` after the parse."
      - id: chara_id
        type: u4
        doc: "[ELF] Wire +1 -> entry +4."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        doc: "[ELF] Wire +5 -> entry +8 (NUL at +24)."
      - id: appearance_a
        size: 9
        doc: |
          [CONFIRMED] (order per PROTOCOL.md) Wire +21 -> entry +25..+33, nine separate u8 reads
          (0xd37438 .. 0xd37538). Appearance bytes 0-8: gender … pitch, same order as `0x4130`.
      - id: unknown_1e
        type: u4
        doc: |
          [UNKNOWN] Wire +30 -> entry +36. PROTOCOL.md: "The four bytes at +9 remain skipped,
          purpose unknown. They sit where the write path emits four zero bytes, so nothing is
          known to be lost, but nothing confirms that either." Still true.
      - id: appearance_b
        size: 14
        doc: "[CONFIRMED] (order per PROTOCOL.md) Wire +34 -> entry +40..+53, fourteen separate u8 reads. Appearance head … accessory-2 colour."
      - id: delete_cooldown_seconds
        type: u4
        doc: |
          [CONFIRMED 2026-07-27, ELF-traced] Wire +48 -> entry +56 (parser `0xD372F8`, stored to
          `sess+0x55D4 + 60*slot + 56`). The **per-character delete cooldown, in seconds** — how
          long until this character may be deleted.

          The client formats it ITSELF, at `0x9510B4`: a non-zero value rounds up to whole minutes
          and produces "Characters cannot be deleted for a fixed amount of time after being
          registered. You must wait %d hours %d minutes" (lobby strings 11848 / 11854). Zero lets
          the deletion proceed. So the countdown shows real numbers instead of the server's rule
          surfacing only as a refusal — this is the ONE cooldown of the three we enforce
          (character delete / clan disband / emblem re-display) that this client build can
          actually display; the other two have no reachable formatter.

          Corrects the previous entry here, "[UNKNOWN] ... Read but never identified; we send
          zero", and corrects a second reading: **PROTOCOL.md files this trailing u32 under the
          appearance block.** It is not part of the appearance. Writing appearance as 28 bytes
          plus a one-byte pad rather than 24 + this u32 is exactly the three-byte shortfall
          described in the top-level doc.
