meta:
  id: mgo2_cmd_4349_s2c
  title: "MGO2 0x4349 — server -> client: reply to 0x4348 (subsystem unidentified)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4349` at
  `0xD3891C` -> stub `0xD395E8` -> parser **`0xD4E800`**. Request-status slot **59**.

  **Total: 171 bytes (`0xAB`).**

  ## Destination base, restated exactly

  `r28 = ctx + 0x10000` (`addis r28,r27,1` at `0xD4E854`), then the struct pointer
  **`S = r29 = r28 - 19228`** (`addi r29,r28,-19228` at `0xD4E868`). The memset at `0xD4E890`
  clears **680 bytes from `S`**. Every field's destination below is quoted both ways: as the
  parser's own `D-N` displacement off `ctx+0x10000` and as `S+k`.

  Sequence: `0xD5D124(ctx+6408, pkt, 1)` (a pre-read hook shared with `0x4305`); `0xD5C844`
  open; `memset(S, 0, 680)`; read `result` into `r1+116`; **if nonzero, jump to `0xD4E9F4` and
  skip every field**; else the reads below; `0xD5C858` close; `0xD32E08(ctx, 59, 2)`,
  `0xD32E70(ctx, 59, result)`.

  ## Nothing reads this struct, and nothing sends the request [ELF 2026-08-01, batch 6]

  * **`0x4348`'s sender `0xD4A834` is dead code** — zero `bl`/`b`/`bc` entries image-wide,
    unreferenced OPD `0x1029B38`, `blr` at `0xd4a830`, and the only `li r4,0x4348` in the
    image. Scan validated on 105 sibling senders. Full derivation in
    `dev/proto/inbound/mgo2_cmd_4348_c2s.ksy`.
  * **The destination struct has one accessor, `0xD490B8`** (`addis r3,r3,1;
    addi r0,r3,-19228`), and it has **zero `bl`/`b`/`bc` callers**.
  * **No other site addresses the window.** Every `addi`/load/store in `.text` with a
    displacement inside `[-19228, -18548]` was enumerated — 150 sites — and all belong to
    unrelated bases (`addis ..,3` engine data at `0x236000`-`0x23B000`; `addis ..,85` at
    `0x89C000`-`0x8A4000`) or are switch-index normalisations followed immediately by a
    `cmplwi`/`bgt` (`0xAA71F0`, `0xAA7468`, `0xD503F4`).

  So this reply is **not a stall candidate** and the field meanings cannot be recovered from
  consumers: there are none. mgo2-server's name for `0x4348` ("host pass") stays tier 4 and
  unadopted — and is independently contradicted by this parser, which reads a name and a
  128-byte comment, i.e. a descriptive card, not a host-transfer ack.

  ## A packing hazard, if this is ever served

  `comment` is 128 bytes at `S+22`, so it occupies `S+22 .. S+149`. The `flags` byte is
  expanded into a **u32 at `S+148`** — which overlaps `comment`'s last two bytes. The parser
  reads that word, ORs bits in and writes it back, *after* the comment read, so a comment
  longer than 126 bytes puts its own bytes into the flag mask. **Keep `comment` to 126 bytes
  plus NUL padding.** [ELF 0xD4E8EC / 0xD4E92C]

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md (0x4348 listed as a sendable gap — corrected to dead code, batch 6)
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xD4E8A0] wire 0x00. Read with `0xD5CC64` into `r1+116`; `cmpwi r0,0; bne 0xD4E9F4`
      at `0xD4E8B4`-`0xD4E8B8` skips every remaining field. Forwarded as
      `0xD32E70(ctx, 59, result)` at `0xD4EA04`+. Not stored in the struct.

      A result code, not a count — there is no list here and no loop for it to bound.
  - id: name
    size: 16
    doc: "[ELF 0xD4E8CC] wire 0x04. Raw 16-byte read -> `D-19223` = `S+5`; the client's slot is 17 bytes (16 + terminator at `S+21`), the same idiom every name field in this protocol uses. ISO-8859-1 assumed by analogy [INFERRED]."
  - id: comment
    size: 128
    doc: |
      [ELF 0xD4E8EC] wire 0x14. Raw 128-byte read (`0xD5D018`, `li r5,128`) -> `D-19206` =
      `S+22`, spanning `S+22 .. S+149`. Same width as the game comment in
      `0x4310`/`0x4313`/`0x4305`.

      **Overlaps `flags`' destination word at `S+148`** — see the packing hazard in the doc
      block. Bytes 126 and 127 of this field are read back into the flag mask.
  - id: flags
    type: u1
    doc: |
      [ELF 0xD4E910] wire 0x94. Read as a 1-byte raw block into `r1+112`, then **four of its
      eight bits are tested and OR-ed into a single u32 at `D-19080` = `S+148`**; the parser
      does `lwz` / `ori` / `stw` on that word four times over.

      **CORRECTED 2026-08-01 (batch 6): the bits are 0, 1, 4 and 5, not "bits 0..3", and the
      mapping is bit-reversed.** Decoded from the four rotate-and-test instructions, each
      isolating result bit 63 (`rldicl. rD, rS, SH, 63`, so the source bit is `(63+SH) mod 64`,
      i.e. LSB-numbered bit `SH == 0 ? 0 : 64-SH`):

      | site | instruction | wire bit | `ori` at | mask bit set |
      | --- | --- | --- | --- | --- |
      | `0xD4E924` | `clrldi. r9,r0,63` | 0 | `0xD4E930` | `0x80` |
      | `0xD4E93C` | `rldicl. r9,r0,63,63` | 1 | `0xD4E948` | `0x40` |
      | `0xD4E954` | `rldicl. r9,r0,60,63` | 4 | `0xD4E960` | `0x08` |
      | `0xD4E96C` | `rldicl. r9,r0,59,63` | 5 | `0xD4E978` | `0x04` |

      So each transferred wire bit `n` lands on mask bit `7-n`, and wire bits 2, 3, 6 and 7 are
      **discarded by the parser** — never tested, never stored, and the byte itself is not kept
      anywhere. Which four flags these are is [UNKNOWN] and cannot be settled statically: the
      word has no reader (see the closed provenance in the doc block).
  - id: unknown_95
    size: 16
    doc: |
      [UNKNOWN — PRECISE NEGATIVE] wire 0x95. Raw 16-byte read (`0xD5D018`, `li r5,16`, at
      `0xD4E990`) -> `D-19076` = `S+152`. Width and position exact.

      A second string-shaped field; the shape suggests a clan tag or owner name and **that is
      shape, not evidence**. No reader: the struct's sole accessor `0xD490B8` has zero callers
      and no other site in `.text` addresses the 680-byte window off a `ctx+0x10000` base.
      Deliberately not named.
  - id: unknown_a5
    type: u1
    doc: "[UNKNOWN — PRECISE NEGATIVE] wire 0xa5. Read at `0xD4E9AC` (`0xD5CB8C`, the u8 primitive) -> `D-19060` = `S+168`. No reader — same closed provenance as `unknown_95`."
  - id: unknown_a6
    type: u1
    doc: |
      [UNKNOWN — PRECISE NEGATIVE] wire 0xa6. Read at `0xD4E9C8` (`0xD5CB8C`) -> `D-19059` =
      `S+169`. Note the destination gap to the next field: `S+170`/`S+171` are never written,
      so this pair is **not** the top half of the following u32 — it is two separate bytes.
      No reader.
  - id: unknown_a7
    type: u4
    doc: "[UNKNOWN — PRECISE NEGATIVE] wire 0xa7. Read at `0xD4E9E4` (`0xD5CCD8`, the u32 primitive) -> `D-19056` = `S+172`. **Last read: the payload ends at 0xAB = 171 bytes.** No reader."
