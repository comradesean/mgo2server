meta:
  id: mgo2_cmd_4210_c2s
  title: "MGO2 0x4210 — own player card / overview request (client -> server) — DEAD CODE"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: sender function entry **`0xD3A76C`**; `li r4,16912` at `0xd3a7d4`, builder
  `bl 0xd5cf40` at `0xd3a7dc`, seal `bl 0xd5c828` at `0xd3a7e8`, flush `bl 0xd34cc0` at
  `0xd3a7f8`, then `0xd32e08(ctx, 32, 1)` at `0xd3a818` — wait slot `0x20` (32) is opened, so
  **if this command were ever sent the reply would be mandatory** and its absence would be a
  live `FFFFFF60`. [ELF]

  Address correction: PROTOCOL.md and the previous revision of this file called `0xD3A7D4`
  "the sender". `0xD3A7D4` is the `li r4,0x4210` inside it; the function entry
  (`stdu r1,-1360(r1)`) is `0xD3A76C`, and `0xd3a768` is the previous function's `blr`, so
  there is no fall-through entry either.

  ## DEAD CODE — this build cannot send 0x4210 [ELF 2026-08-01, batch 6]

  `0xD3A76C` is **never called**. The batch 4a/5 entry test, with the `b` and `bc` additions:

  1. **Zero `bl`, zero `b`, zero `bc` entries** over the whole executable range — the four
     `SHF_EXECINSTR` sections `0x10200(+0x2c)`, `0x10230(+0xdd90f8)`, `0xde9328(+0x24)`,
     `0xde934c(+0x2ba0)`, i.e. every executable byte in the image — decoding both AA=0 and
     AA=1 forms of primary opcodes 18 and 16.
  2. **OPD descriptor `0x10291E0` is referenced by no word anywhere in the file**, and no
     `addi`/`ori` in text materialises the constant `0x10291E0`. `ET_EXEC`, so no relocations
     can hide a reference.
  3. `0xd3a768` is a `blr` — no fall-through.
  4. `li r4,0x4210` at `0xd3a7d4` is the **only** `li r4,<imm>` carrying 16912 in the image;
     every other 16-bit `0x4210` immediate in text is a float-load displacement or an `lis`.

  **The scan is validated against controls, which is what makes the negative admissible.** The
  same sweep was run over the whole command-id sender bank at `0xd38000`-`0xd60000` — 116
  `li r4,<id>` sites walked back to their function entries — and **105 of them have callers**:
  `0x4220`'s `0xD3B950` has two (`0x90590C`, `0xA7E0B0`), `0x4132`'s `0xD3A844` has one
  (`0x929194`), i.e. the immediate neighbours on both sides of `0xD3A76C` are reached. A scan
  that finds 105 and misses this one is evidence, not a broken scan. The `bc` decoder was
  separately validated by resolving two known in-function branch targets (`0xd3b408` from
  `0xd3b2f4`/`0xd3b328`; `0xd3a824` from three sites).

  Batch 5 proved `0x4394`'s builder `0xD41C90` dead by the same test; re-run here it again
  shows zero, so the method reproduces its own prior result.

  ### The reply triple's storage has no reader either

  Independent of the sender, the list that `0x4211`/`0x4212`/`0x4213` fill —
  `*(ctx+0x10000+6404) + 13104`, i.e. `T+0x3330` — is **read by nothing**. Its three accessors
  are `0xD3A0CC` (head-if-open), `0xD3F514` (`GetRow(session, i)`, bounds-checked, `mulli 28`)
  and `0xD3F568` (`GetCount`), and **all three have zero `bl`/`b`/`bc` callers**. Control: the
  instruction-for-instruction identical accessor bank for the `0x4682` match-history list at
  `T+0x26d14` (`0xD3A100` / `0xD3F5A0` / `0xD3F5F8`) has **six** callers, all in the
  met-players row painters at `0x91E3AC`-`0x9205CC`.

  So there is no screen to find: the request is unreachable and the data it would fetch is
  unrendered. **A server handler for `0x4210` is unnecessary on this build** — it is not a
  stall candidate and never was. `COMMANDS.md`'s "reachable in ordinary flow (priority)" and
  `PACKETS_NOT_OBSERVED.md`'s "two reachable" are corrected by this.

  Recommended posture: the reply layout is fully derived in the three outbound schemas, so a
  handler is cheap insurance should a later version toggle wire the sender up. It is not a bug
  fix and should not be prioritised as one.
doc-ref: dev/docs/PROTOCOL.md "0x4220 — player details" (0x4210 sibling note)
seq: []
