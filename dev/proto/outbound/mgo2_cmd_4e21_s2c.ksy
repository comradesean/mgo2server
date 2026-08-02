meta:
  id: mgo2_cmd_4e21_s2c
  title: "MGO2 0x4e21 — Survival: per-slot status column for the team record's 8 match slots (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **CREATED 2026-08-02 to close a structural gap.** This id had **no `.ksy` file at all**, which
  `CLAUDE.md` treats as an error rather than an omission: every id has exactly one file, so that a
  missing layout is always an explicit blank and never an oversight. `0x4E21` was found while
  mapping the rest of the block and had been absent the whole time.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  is in `mgo2_cmd_4e00_c2s.ksy`. `0x4E21` is a **server push** (no request slot) that rewrites the
  status column of the **team record's 8-slot match table** at `team+0x17C`, stride 28.

  TIER. Post-launch content; no available client build exercises this command, so **everything here
  is tier 1 and cannot be raised to tier 2.** Not served in v1.

  Routing: GAME dispatcher `0xD387C8`, compare tree at `0xD38804` -> stub `0xD39D10` -> parser
  **`0xD5A600`**, which re-checks the id (`cmpwi r0,20001`) before reading anything.

  Opens with the shared header validator **`0xD49230`** (u4 + u2, checked against `team+0x00` and
  `team+0x29C` on `team = 0xD491F8(session) = session+0xD928`; mismatch = -1018 and the packet is
  dropped).

  ## Wire size: 15 bytes (ADJUDICATED 2026-08-02 — the file was created declaring 8)

  The parser reads, in order:

  ```
  0xD5A6A0  std r0,112(r1)                  ; pre-zero r1+112..r1+119. Encoding F8010070 —
                                            ; DS-form low bits 00, plain std, NOT stdu
  0xD5A6B8  bl 0xd49230                     ; u4 + u2  = 6 bytes  (header validator)
  0xD5A6D8  bl 0xd5cb8c   -> team+0x04      ; u1       = 1 byte
  0xD5A6E8  addi r29,r1,112                 ; loop cursor, r1-relative, never rewritten
  0xD5A6EC  clrldi r31,r25,32               ; loop top
  0xD5A6FC  bl 0xd5cb8c   -> r29            ; u1  <-- ONE bl SITE, EIGHT EXECUTIONS
  0xD5A6F8  addi r29,r29,1
  0xD5A704  addi r0,r1,120
  0xD5A710  cmpw cr6,r29,r0
  0xD5A718  bne cr6,0xd5a6ec                ; 8 iterations, r1+112 .. r1+119
  ```

  `4 + 2 + 1 + 8*1 =` **15 bytes**. The arbiter is the wire cursor, not the destination: 0xD5CB8C
  reloads `[r3+1108]`, adds 1 and stores it back (0xD5CBB0-0xD5CBB8) on every successful call, and
  r3 is the same read context on all eight iterations — so eight payload bytes are consumed.

  Deliberately checked against the `0x4A02`/`0x4A22`/`0x4A29`/`0x4A00` failure, which ran the
  opposite way: there a `stdu` (DS low bits `01`) rewrote its base register, turning
  `addi r0,r1,128` into an end address that was read as a 128-byte count. Here the store is a plain
  `std`, the cursor is an explicit `addi r29,r1,112`, and `addi r0,r1,120` is an end address whose
  distance from the start is 8 — the same 8 either way.

  **What the earlier reading mistook for the length:** one `bl 0xd5cb8c` in the instruction text was
  counted as one byte. That counts call *sites* rather than *executions*; the backward `bne cr6` at
  0xD5A718 makes the single site read eight. Where the `stdu` class over-counted a loop, this class
  under-counts one.

  `0x4E22` (`0xD5A4DC`-`0xD5A508`) and `0x4E23` (`0xD5A2BC`-`0xD5A2E8`) contain the byte-identical
  loop, so all three are 15 bytes and all three now declare `slot_status` as `repeat-expr: 8`.

  ## What the eight bytes are

  Identical to `0x4E22` — see `mgo2_cmd_4e22_s2c.ksy` for the traced walk. In summary: after
  RD_END the parser walks the 8-entry, 28-byte-stride table at `team+0x17C`, one entry per wire
  byte, and

  * `entry+0x00 == 0` -> slot empty, byte skipped;
  * wire byte **non-zero** -> `stb` to `entry+0x15`;
  * wire byte **zero** -> `memset(entry, 0, 28)` — **a zero byte DELETES the slot** rather than
    storing a zero status. That asymmetry is the thing a server implementation would get wrong.

  **The one difference from its siblings is the UI event.** The three parsers `0xD5A600` (this),
  `0xD5A3F0` (`0x4E22`) and `0xD5A1D0` (`0x4E23`) differ only in the id compared, the event fired —
  **40** here, 39 for `0x4E22`, 41 for `0x4E23` — and one extra call in `0x4E23`. What distinguishes
  the three events is [UNKNOWN]; nothing in this parser says why the same table rewrite would be
  announced three different ways.

  Read primitives: `0xD5CB8C` u1, `0xD5CC14` u2, `0xD5CC64`/`0xD5CCD8` u4. Note that **no read
  primitive is a signed accessor at any width** — the pairs are instruction-for-instruction
  identical, and signedness comes from the caller. See `mgo2_cmd_4e22_s2c.ksy`'s CORRECTION block
  for the whole-function comparison that established this.
seq:
  - id: team_id
    type: u4
    doc: |
      [ELF 2026-08-02] Validated by `0xD49230` against **`team+0x00`**
      (`team = 0xD491F8(session) = session+0xD928`); mismatch = -1018 and the packet is dropped.
      `mgo2_cmd_491b_c2s.ksy` names that slot the **team id**. Same field as `0x4E20.team_id` and
      `0x4E22.team_id`.
  - id: team_seq
    type: u2
    doc: |
      [ELF 2026-08-02] Validated by `0xD49230` against the u16 at **`team+0x29C`**; mismatch =
      -1018. [UNKNOWN] what increments it. Same field as `0x4E20.team_seq` and `0x4E22.team_seq`.
  - id: unknown_0x04
    type: u1
    doc: |
      [ELF 2026-08-02] Read at `0xD5A6D8` -> **`team+0x04`**. Struct-offset bijection with
      `0x4E20`, `0x4E22` (`0xD5A4C8`) and `0x4E23` (`0xD5A2A8`) — one field shared by all four.

      **[UNKNOWN], and no negative is claimed.** A reader would appear as a load at displacement 4
      off whatever register holds the team record, and displacement 4 is far too common for a
      displacement sweep to discriminate — a sweep that cannot be validated against a known-good
      hit is worthless, so none is reported. The same refusal is recorded in
      `mgo2_cmd_4a00_s2c.ksy` for the identical slot.
  - id: slot_status
    type: u1
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF 2026-08-02] **Eight** per-slot status bytes, one per entry of the 8-entry /
      28-byte-stride match table at `team+0x17C`. Non-zero is stored to `entry+0x15`; **zero
      deletes the entry** (`memset(entry, 0, 28)`).

      **ADJUDICATED 2026-08-02 (third reading).** The file was created declaring a single `u1`
      named `slot_status_0`; it is a fixed 8-element array and the packet is 15 bytes, not 8. The
      `_0` is gone because there are eight, not one. Modelled as `repeat: expr` with a literal
      count — the house style for a compiled-in count, as in `mgo2_cmd_4a24_s2c.ksy`'s
      `trailing_words` — because nothing on the wire carries the length.

      [UNKNOWN] what the status codes mean.
