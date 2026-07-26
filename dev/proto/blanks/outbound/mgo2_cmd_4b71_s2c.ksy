meta:
  id: mgo2_cmd_4b71_s2c
  title: "MGO2 0x4b71 — clan per-mode stat grid, 584 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: dispatcher 0xD38804 (the 0x41xx-0x4Exx literal compare chain) -> thunk -> parser
  **0xD5992C**, which re-checks the id (`cmpwi r0,19313`) before reading anything.

  **This is the clan twin of 0x4105.** The destination arithmetic at 0xD59A28-0xD59A44 is
  base + 2332 + page*864 + mode*72, and the mode loop runs index 0..11 skipping 6, 8, 9 and 10
  (0xD59A08-0xD59A24) — byte for byte the same geometry as the personal grid documented in
  dev/proto/mgo2_cmd_4105.ksy (mode*0x48 + page*0x360, 12-slot loop skipping 6/8/9/10, 18 u32
  columns, 8 records on the wire). The column layout there is [CONFIRMED] live; here it is only
  [INFERRED] by that structural identity, so the column names are deliberately NOT copied over.

  Difference from 0x4105: `page` must be **2 or 3**, not 0 or 1 (0xD599C8: `addi r0,r9,-2;
  cmplwi r0,1; bgt -> error -71`). Page 2 additionally zeroes 3456 bytes = 4 * 864, i.e. all
  four page slots, so the client keeps pages 0/1 (personal, from 0x4105) and 2/3 (this packet)
  in one array and page 2 wipes the lot.

  Sends no request-slot update. Wire size: 4 + 4 + 8*18*4 = **584 bytes** — the same total as
  0x4105.

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 s4, 0xD5CCD8 u4, 0xD5D018 fixed byte block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. In each
  signed/unsigned pair the LOWER address is the signed accessor (write-side proof: 0xD5C95C uses
  `sraw`, 0xD5C9BC uses `srw`). Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare): that rule holds on the WRITE side
  only. The READ pair 0xD5CC64 / 0xD5CCD8 is instruction-for-instruction identical — same
  `cmpwi 1020` bound check, same byte-assembly loop — so neither is a signed accessor. Where a
  field below is typed s4, the evidence is the CALLER reloading the value with `lwa` (or the
  field being a known-negative error code), never the primitive's address.

seq:
  - id: result
    type: s4
    doc: "[ELF] Non-zero jumps straight to end-read, so an error reply is 4 bytes. Observed convention: 0 = success."
  - id: page
    type: u4
    doc: |
      [ELF] MUST be 2 or 3; anything else fails the whole packet with -71 and discards the grid
      (0xD599C8). Receipt of page 2 zeroes all four 864-byte page slots. [UNKNOWN] what 2 and 3
      mean semantically — by analogy with 0x4105's cumulative/weekly they are plausibly the same
      pair for clan totals, but that is [INFERRED], not read.
  - id: modes
    type: mode_stats
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] Wire order = the client's mode-loop order, indices 0,1,2,3,4,5,7,11 (6/8/9/10 are
      skipped by explicit compares). Same skip set as 0x4105.
types:
  mode_stats:
    doc: |
      [ELF] 18 consecutive u4 columns, 72 bytes, stored at base+2332+page*864+mode*72.
      Column semantics [UNKNOWN] here. 0x4105's 18 columns are capture-proven and the geometry is
      identical, so they are the obvious hypothesis — but no capture has confirmed the clan grid
      uses the same column order, and this project's rule is not to promote a mirror to a
      duplicate without a divergence test. Left as numbered columns on purpose.
    seq:
      - id: columns
        type: u4
        repeat: expr
        repeat-expr: 18
        doc: "[UNKNOWN] col 0..17. See the type doc for why these are not named."
