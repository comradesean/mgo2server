meta:
  id: mgo2_cmd_3040_c2s
  title: "MGO2 0x3040 — activate character by slot; DEAD CODE on this build (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd37b70`
  (`li r4,12352` = `0x3040` at `0xd37b6c`), sender **entry `0xd37b00`** (prologue
  `stdu r1,-1360(r1); mflr r0`; OPD descriptor 0x1029008). One write primitive before the
  seal: `bl 0xd5c8a0` (write-u8) at `0xd37b80`, from stack `1416(r1)` — the sender's `r4`
  argument, spilled at `0xd37b24`. Seal `0xd37b8c`, flush `0xd37b9c`, wait slot `0x0d`
  (`li r4,13` at `0xd37ba4`). [ELF]

  ## CORRECTION 2026-08-03: the builder exists but is DEAD CODE — this build cannot send it

  PROTOCOL.md's earlier note ("has a live builder — it *can* be sent") conflated *builder
  exists* with *builder is called*. The entry 0xD37B00 has zero `bl`/`b`/`bc` callers over
  the whole executable range 0x10230..0xDE9328, its OPD descriptor 0x1029008 is referenced by
  no word in the file, and no `lis/addis`+`addi/ori` pair forms either address anywhere in
  .text. Scan validated on eight known-live controls in the same OPD bank (0xD37918 -> 1,
  0xD37A0C -> 1, 0xD37BF0 -> 3, 0xD37CC0 -> 1, 0xD37DE4 -> 1, 0xD36FF8 -> 8, 0xD37024 -> 1,
  0xD378EC -> 7); only 0xD37B00 returns zero. Independently, wait slot 13 is armed at exactly
  one site in the image — 0xD37BBC, inside this dead builder — so nothing else can even be
  waiting on the reply. (All 251 call sites of the wait-state setter 0xD32E08 were enumerated
  to establish that.)

  **Consequence: 0x3040 is not a stall candidate and not a serving gap on this build.** It
  moves from "sendable, unanswered" to the parked set. As always, nothing here transfers to
  1.36, where the exchange may be live.

  ## The operation is now identified (from the reply side, 2026-08-03)

  What was [INFERRED] from the shared 0..7 bound is settled by 0x3041's destinations: the
  reply installs a u32 into profile+0 (chara_id) and a 16-byte name into profile+4 — the live
  profile slots 0x4101 fills and the UI reads. So 0x3040 = **"activate/fetch character by slot
  index"**, a per-slot alternative to the 0x3048/0x3049 + 0x3103 flow the shipped client
  actually uses. Full evidence chain in `../outbound/mgo2_cmd_3041_s2c.ksy`.
doc-ref: dev/proto/outbound/mgo2_cmd_3041_s2c.ksy
seq:
  - id: index
    type: u1
    doc: |
      [ELF] Character-slot index, range-limited by the sender: `cmplwi cr6,r4,7` at `0xd37b20`
      and `bgt` to the error exit at `0xd37bcc` (returns -24), so the client would never send
      a value above 7. The same 0..7 bound `0x3103` (select character) and `0x3105` (delete
      character) enforce on their one-byte index, and the same 8-slot space as `0x3049`'s
      character grid. The slot reading is confirmed by the reply's destinations (see the doc
      block); note no call site exists to trace an actual argument value from — the builder is
      dead code, so the value below the bound is unknowable on this build.
