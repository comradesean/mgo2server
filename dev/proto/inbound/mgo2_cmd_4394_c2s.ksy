meta:
  id: mgo2_cmd_4394_c2s
  title: "MGO2 0x4394 — in-match large record push (client -> server)"
  endian: be
doc: |
  Builder function `0xD41C90` = `f(ctx, void *record)`; a null record aborts before anything is
  written (`0xD41CD0`). `bl 0xD5CF40` at `0xD41D20` (`li r4,0x4394` at `0xD41D1C`), seal
  `0xD5C828` at `0xD42100`, flush `0xD34CC0` at `0xD42114`. **Not encrypted** (no `0xD5D124`
  call), which is consistent with `0x4394` being absent from `DECRYPT_COMMANDS`.

  **Total payload 203 bytes (0xCB)** — the largest client->server frame in the `0x43xx` family.
  Every field is copied out of the caller's `record` struct (`r28`) by an unbroken run of 45
  write-primitive calls at `0xD41D28`-`0xD420F8`; there is no branching, so the layout is fixed.
  Wire offsets below were accumulated from the primitive widths, and the source struct offset is
  given for each because **the two do not line up**: `record` has holes (e.g. `+0x43`, `+0x56`)
  that the wire does not, so every field after `0x42` is shifted.

  **Nothing here has a known meaning.** `COMMANDS.md` lists `0x4394` as a sendable gap in the
  in-match/host family; `PROTOCOL.md`'s gap list calls it only "`0x4394` (large struct)". No
  capture exists. So every field is `[UNKNOWN]` with an exact position, per
  `blanks/README.md` — and note that a 203-byte push is a *report*, not a request: whatever
  screen sends it will stall with `FFFFFF60` until `0x4395` is answered.

  The one structural observation worth having: the first 48 bytes are **three parallel 16-entry
  byte arrays interleaved on the wire** (source `record+0x00`, `record+0x10`, `record+0x20`,
  written as a 16-iteration loop emitting one byte from each per pass, `0xD41D28`-`0xD41D7C`).
  16 is the roster size elsewhere in this protocol, so this reads as per-player triples.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq:
  - id: slots
    type: slot_triple
    repeat: expr
    repeat-expr: 16
    doc: |
      [ELF] 0x00-0x2F. 16 x 3 bytes, interleaved from three 16-byte source arrays — NOT three
      contiguous arrays on the wire. Loop at `0xD41D28`; the loop bound is the literal 16 at
      `0xD41D78`, not a count field. Meaning [UNKNOWN]; 16 = the roster size.
  - id: unknown_30
    type: u1
    doc: "[UNKNOWN] 0x30, from `record+0x30` (`0xD5C8A0` at `0xD41D8C`)."
  - id: unknown_31
    type: u1
    doc: "[UNKNOWN] 0x31, from `record+0x31` (`0xD5C8A0` at `0xD41DA0`)."
  - id: unknown_32
    size: 16
    doc: "[UNKNOWN] 0x32-0x41. Raw 16-byte copy from `record+0x32` (`0xD5D0AC`, `r5=16`, at `0xD41DB8`). A 16-byte blob in this protocol is almost always an ISO-8859-1 NUL-padded name, but nothing here proves it."
  - id: unknown_42
    type: u1
    doc: "[UNKNOWN] 0x42, from `record+0x42` (`0xD5C8A0` at `0xD41DCC`). `record+0x43` is skipped — the wire has no hole."
  - id: unknown_43
    type: u4
    doc: "[UNKNOWN] 0x43, from `record+0x44` (`0xD5C9BC` at `0xD41DE0`). Note the misalignment: every u32 from here on sits at an odd wire offset."
  - id: unknown_47
    type: u4
    doc: "[UNKNOWN] 0x47, from `record+0x48`."
  - id: unknown_4b
    type: u4
    doc: "[UNKNOWN] 0x4B, from `record+0x4C`."
  - id: unknown_4f
    type: u2
    doc: "[UNKNOWN] 0x4F, from `record+0x50` (`0xD5C918` = u16 writer)."
  - id: unknown_51
    type: u2
    doc: "[UNKNOWN] 0x51, from `record+0x52`."
  - id: unknown_53
    type: u4
    doc: "[UNKNOWN] 0x53, from `record+0x54`."
  - id: unknown_57
    type: u4
    doc: "[UNKNOWN] 0x57, from `record+0x58`."
  - id: unknown_5b
    type: u2
    doc: "[UNKNOWN] 0x5B, from `record+0x5C`."
  - id: unknown_5d
    type: u1
    doc: "[UNKNOWN] 0x5D, from `record+0x5E`."
  - id: unknown_5e
    type: u1
    doc: "[UNKNOWN] 0x5E, from `record+0x5F`."
  - id: counters
    type: u4
    repeat: expr
    repeat-expr: 18
    doc: |
      [UNKNOWN] 0x5F-0xA6. Eighteen u32s written back to back from `record+0x60` through
      `record+0xA4` in strict 4-byte source order (`0xD41EA8`-`0xD41FFC`) — the only fully
      regular run in the frame, which is why it is modelled as an array rather than 18 named
      holes. A contiguous u32 counter block is what `0x4105`/`0x4390` look like too, so
      "per-something tallies" is the structural read; no label is established.
  - id: unknown_a7
    size: 2
    doc: "[UNKNOWN] 0xA7-0xA8. Raw 2-byte copy from `record+0xA8` (`0xD5D0AC`, `r5=2`, at `0xD42014`) — a byte pair, deliberately not a u16 (the u16 writer exists and was not used)."
  - id: unknown_a9
    type: u2
    doc: "[UNKNOWN] 0xA9, from `record+0xAA`."
  - id: unknown_ab
    type: u4
    doc: "[UNKNOWN] 0xAB, from `record+0xAC`."
  - id: unknown_af
    type: u1
    doc: "[UNKNOWN] 0xAF, from `record+0xB0`."
  - id: unknown_b0
    size: 2
    doc: "[UNKNOWN] 0xB0-0xB1. Raw 2-byte copy from `record+0xB1` (`0xD5D0AC`, `r5=2`, at `0xD42068`)."
  - id: unknown_b2
    type: u1
    doc: "[UNKNOWN] 0xB2, from `record+0xB3`."
  - id: unknown_b3
    type: u2
    doc: "[UNKNOWN] 0xB3, from `record+0xB4`."
  - id: unknown_b5
    type: u2
    doc: "[UNKNOWN] 0xB5, from `record+0xB6`."
  - id: unknown_b7
    type: u4
    doc: "[UNKNOWN] 0xB7, from `record+0xB8`."
  - id: unknown_bb
    type: u1
    doc: "[UNKNOWN] 0xBB, from `record+0xBC`."
  - id: unknown_bc
    type: u1
    doc: "[UNKNOWN] 0xBC, from `record+0xBD`."
  - id: unknown_bd
    size: 14
    doc: "[UNKNOWN] 0xBD-0xCA. Raw 14-byte copy from `record+0xBE` (`0xD5D0AC`, `r5=14`, at `0xD420F8`) — the last write before the seal, so the frame ends at 0xCB = 203 bytes."
types:
  slot_triple:
    doc: "One interleaved pass of the 16-iteration loop: byte i of each of the three source arrays."
    seq:
      - id: a
        type: u1
        doc: "[UNKNOWN] source `record+0x00+i`."
      - id: b
        type: u1
        doc: "[UNKNOWN] source `record+0x10+i`."
      - id: c
        type: u1
        doc: "[UNKNOWN] source `record+0x20+i`."
