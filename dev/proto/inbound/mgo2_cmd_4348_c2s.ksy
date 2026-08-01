meta:
  id: mgo2_cmd_4348_c2s
  title: "MGO2 0x4348 — unidentified command (client -> server) — DEAD CODE"
  endian: be
doc: |
  **Empty payload — confirmed from the ELF.** Sender function `0xD4A834`; `li r4,0x4348` at
  `0xD4A89C`, builder `bl 0xD5CF40` at `0xD4A8A4`, seal `0xD5C828` at `0xD4A8B0`, flush
  `0xD34CC0` at `0xD4A8C0`. No write primitive between builder and seal, and the sender takes
  no payload argument (only the context in `r3`, null-checked at `0xD4A83C`). Not encrypted.

  Wait slot **59** (`0x3B`) is opened at `0xD4A8C8`-`0xD4A8E0`: `li r4,59; li r5,1;
  bl 0xd32e08`. That matches `0x4349`'s parser (`0xD4E800`, which closes slot 59 at
  `0xD4EA04`), so **were this command ever sent, the reply would be mandatory**.

  ## DEAD CODE — this build cannot send 0x4348 [ELF 2026-08-01, batch 6]

  `0xD4A834` is **never called**, by the batch 4a/5 entry test extended with `b` and `bc`:

  1. **Zero `bl`, zero `b`, zero `bc` entries** over every executable byte in the image — the
     four `SHF_EXECINSTR` sections `0x10200(+0x2c)`, `0x10230(+0xdd90f8)`, `0xde9328(+0x24)`,
     `0xde934c(+0x2ba0)` — decoding both AA=0 and AA=1 forms of primary opcodes 18 and 16.
  2. **OPD descriptor `0x1029B38` is referenced by no word anywhere in the file**, and no
     `addi`/`ori` in text materialises the constant `0x1029B38` (the single `0x9b38` immediate
     in text, at `0xd79188`, is `lwz r9,-25800(r2)`). `ET_EXEC`, so no relocations.
  3. `0xd4a830` is a `blr` — no fall-through entry.
  4. `li r4,0x4348` at `0xd4a89c` is the **only** `li r4,<imm>` carrying 17224 in the image;
     every other 16-bit `0x4348` immediate in text is an `lis`/`addis` half-constant.

  **Validated against controls.** The same sweep over the whole command-id sender bank
  (`0xd38000`-`0xd60000`, 116 `li r4,<id>` sites resolved back to their function entries)
  finds callers for 105 of them, including both immediate neighbours of `0xD4A834`:
  `0x4914`'s `0xD4A75C` has four and `0x4986`'s `0xD4A90C` has one. A scan that resolves 105
  and misses this one is evidence, not a broken scan.

  ### The reply's destination struct has no reader either

  `0x4349` writes into `ctx+0x10000-19228` (680 bytes, memset at `0xD4E890`). The only
  function that computes that address is the accessor **`0xD490B8`** (`addis r3,r3,1;
  addi r0,r3,-19228`, returns 0 for a null ctx) — and it has **zero `bl`/`b`/`bc` callers**.
  No other site in `.text` addresses the 680-byte window `[-19228, -18548]` off a
  `ctx+0x10000` base: every `addi`/load/store in the image with a displacement in that range
  was enumerated (150 sites) and all of them belong to unrelated bases (`addis ..,3` engine
  data around `0x236000`-`0x23B000`, `addis ..,85` around `0x89C000`-`0x8A4000`) or are jump
  table index normalisations (`0xAA71F0`, `0xAA7468`, `0xD503F4`, each immediately followed by
  a `cmplwi`/`bgt` range check).

  So the meaning cannot be recovered from callers, because there are none. **The "host pass"
  name mgo2-server gives this id remains tier 4 and is not adopted** — and it is independently
  contradicted by the reply, which carries a name and a 128-byte comment, not a host-transfer
  ack.

  **A server handler for `0x4348` is unnecessary on this build.** `COMMANDS.md`'s "reachable
  in ordinary flow (priority)" and `PACKETS_NOT_OBSERVED.md`'s "two reachable" are corrected
  by this: with `0x4394` and `0x43B0` already removed in batch 5, that list is now empty.
doc-ref: dev/docs/COMMANDS.md "Reachable in ordinary flow (priority)"
seq: []
