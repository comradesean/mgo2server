meta:
  id: mgo2_cmd_4212_s2c
  title: "MGO2 0x4212 — list records for the 0x4210 triple (server -> client)"
  endian: be
doc: |
  Parser **0xd3b2d0** (GAME dispatcher 0xd38804, trampoline 0xd39180). Middle packet of the
  `0x4211`/`0x4212`/`0x4213` triple; fires no notification of its own.

  **Record count is size-driven**, like `0x2003` and `0x200a`: the loop head at `0xd3b338`
  zeroes a 28-byte scratch at `r1+112` (`vxor`/`stvx` covering 112..127, `std r0,128(r1)`
  covering 128..135, `stw r0,136(r1)` covering 136..139) and calls `MORE_DATA?` (`0xd5ceb0` at
  `0xd3b358`); when the cursor reaches the payload length it exits to `READ_END`. Records are
  `memcpy`d (`lswi`/`stswi`, 28 bytes, `0xd3b3e0`-`0xd3b3e4`) into `list + 8 + n*28` and the
  persistent count at `4(r31)` is incremented, so records accumulate across packets.

  **Client capacity is 1000 records**: `lwz r4,4(r31); cmpwi r4,999; bgt -> bail(-71)` at
  `0xd3b3c0`-`0xd3b3cc`; the compare itself is at **`0xd3b3c4`**. That is a far larger cap than
  any other list in the protocol (`0x2003` allows 32, `0x200a` 10).

  Read primitives in order: u32 (`0xd5ccd8` at `0xd3b370`) -> `r1+112`; fixed[16] (`0xd5d018`,
  `r5=16`, at `0xd3b390`) -> `r1+116`; u32 (`0xd5ccd8` at `0xd3b3ac`) -> `r1+136`.
  **24 wire bytes, 28 bytes per record in the client struct**, with struct `+20..+23` a hole
  the parser never writes (re-zeroed every iteration, so `+20` doubles as the name's NUL).

  ## Unreachable on this build, and the negative is closed rather than swept

  [ELF 2026-08-01, batch 6] `0x4210`'s sender `0xD3A76C` has zero `bl`/`b`/`bc` entries over
  the whole executable image, so the triple is never requested — see
  `dev/proto/inbound/mgo2_cmd_4210_c2s.ksy` for that test and its 105-control validation.

  Independently, **the list this packet fills has no reader.** Provenance is closed by
  enumeration, not by a band sweep (batch 2a's mistake):

  * Every computation of the list head is an `addi rX, rY, 13104`. There are **exactly six in
    the image** — `0xd3a0e0`, `0xd3af74`, `0xd3b06c`, `0xd3b324`, `0xd3f52c`, `0xd3f580` —
    found by decoding every `addi` in `.text` and filtering on the immediate.
  * Three are the triple's own parsers (`0x4213` `0xd3af74`, `0x4211` `0xd3b06c`, `0x4212`
    `0xd3b324`). The other three are the accessor bank: `0xD3A0CC` (head, returns 0 unless the
    marker is 0), `0xD3F514` (`GetRow(session, i)`: bounds-checked against the count,
    `mulli r9,r4,28`, `+8`), `0xD3F568` (`GetCount`).
  * **All three accessors have zero `bl`/`b`/`bc` callers.** Control: the byte-for-byte
    identical accessor bank for the `0x4682` match-history list (`0xD3A100` / `0xD3F5A0` /
    `0xD3F5F8`, immediate 27924 with an extra `addis 2`) has **six** callers —
    `0x91E3AC`, `0x91EA8C`, `0x91F370`, `0x9200DC`, `0x9205CC`, `0x91F97C` — the met-players
    row painters. The scan that finds those six finds nothing here.

  So there is no renderer to name the fields from, and no second writer to the struct. The
  three fields below are terminal from static evidence.

  ## The 0x4682 lead is REFUTED — different storage, different record

  PROTOCOL.md's `0x4102` section and OBSERVED.md both say `T+0x26d14` and `T+0x3330` "turned
  out to be match-history list storage for `0x4682`/`0x4212` records", which reads as though
  the two commands share a store. **They do not, and the record does not transfer.**

  * `0x4212`'s head is `*(session+6404) + 13104` = `T+0x3330` (`0xd3b324`).
  * `0x4682`'s head is `*(session+6404) + 0x20000 + 27924` = `T+0x26d14` (parser `0xd3b5fc`:
    `addis r9,r9,2` at `0xd3b650`, `addi r29,r9,27924` at `0xd3b654`; the same pair recurs in
    the accessor at `0xd3f5b8`-`0xd3f5bc`).
  * Those differ by 145,892 bytes. **The bases provably do not coincide**, so nothing may be
    carried across — that was the precondition this batch was told to test before transferring
    any name, and it fails.
  * The records disagree anyway. `0x4682`: `{u32 timestamp; u32 chara_id; char name[16];
    hole at +24; u8 lobby_type at +25}` = **25 wire bytes**, four reads. `0x4212`:
    `{u32; char[16]; hole at +20..23; u32 at +24}` = **24 wire bytes**, three reads. Neither
    the field count, the widths, nor the destination offsets line up: `0x4682` puts a name at
    struct `+8`, `0x4212` puts one at `+4`.

  The two lists are *structurally* the same kind of object — same `{u32 marker; u32 count;
  record[N] at +8}` header, same 28-byte stride, parallel three-function accessor banks — which
  is presumably what the note meant. They are not the same list and not the same record.
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats" (the T+0x3330 note, corrected here)
seq:
  - id: records
    type: list_record
    repeat: eos
    doc: "[ELF] Size-driven repeat (MORE_DATA? at 0xd5ceb0). Max 1000 across all 0x4212 packets."
types:
  list_record:
    doc: "24 wire bytes -> 28-byte client struct record at `T+0x3330 + 8 + n*28`."
    seq:
      - id: unknown_00
        type: u4
        doc: |
          [UNKNOWN — PRECISE NEGATIVE] Wire +0 -> record +0. Read at `0xd3b370` (`0xd5ccd8`,
          the u32 primitive) into scratch `r1+112`, copied to the record by the 28-byte
          `stswi` at `0xd3b3e4`. Position and width exact.

          **No reader anywhere in the image.** The only routes to this byte are the accessor
          bank `0xD3A0CC`/`0xD3F514`/`0xD3F568`, all three with zero callers, and the six
          `addi ...,13104` sites are fully enumerated in the doc block. By shape (a leading u32
          before a 16-byte name) this is an id in every other list in the protocol, but
          **nothing here confirms it and the `0x4682` analogy is refuted above** — that record
          carries two u32s before its name, not one.

          What would settle it: nothing static. It needs the sender to be reachable, which on
          this build it is not.
      - id: unknown_04
        size: 16
        doc: |
          [UNKNOWN — PRECISE NEGATIVE] Wire +4 -> record +4, fixed 16 bytes. Read at `0xd3b390`
          (`0xd5d018` with `li r5,16`) into scratch `r1+116`. Struct `+20` is never written by
          the parser and is re-zeroed each iteration by `std r0,128(r1)`, so it serves as the
          NUL terminator — the 16+1 idiom every name field in this protocol uses.

          A 16-byte field is a character or lobby name everywhere else in the protocol; that is
          shape, not evidence, and there is no renderer to check it against — no reader anywhere
          in the image, the same closed provenance as `unknown_00` (see the doc block).
      - id: unknown_14
        type: u4
        doc: |
          [UNKNOWN — PRECISE NEGATIVE] Wire +0x14 -> record **+24**, not +20. Read at
          `0xd3b3ac` (`0xd5ccd8`) into scratch `r1+136`, which is scratch base `r1+112` plus
          24. The wire is strictly sequential 4+16+4 = 24 bytes; only the struct has the
          `+20..+23` gap.

          No reader — same closed provenance. Note this is where `0x4682` puts its 1-byte
          `lobby_type`-at-`+25`; the offsets are one apart and the widths differ by four, so
          even the "same neighbourhood" reading does not survive.
