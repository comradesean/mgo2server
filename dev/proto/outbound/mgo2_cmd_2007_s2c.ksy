meta:
  id: mgo2_cmd_2007_s2c
  title: "MGO2 0x2007 — reply to 0x2006, single u32; the exchange is dead code on this build (server -> client)"
  endian: be
doc: |
  Parser arm 0xd36498, GATE dispatcher 0xd361a4 (compare tree at 0xd361e8). Reads **exactly one
  u32** (primitive 0xd5ccd8 at 0xd364c4) into a scratch, then `std`s it as a 64-bit value to
  `session+0xDD8` (3544) and sets **wait slot 11 to state 2** via 0xd32e08 at 0xd364ec.

  CORRECTION 2026-08-03 — "fires notify(event 11, state 2)" was misleading. 0xd32e08 is
  `SetWaitState(session, slot, state)`: a single guarded `stw` to `session+360+4*slot`
  (slot <= 116, state <= 2). Nothing is signalled, no callback runs, nothing queues. "Event 11"
  is **wait slot 11**, one of the three GATE-owned slots (10..12, partitioned per connection at
  0xd32f6c-0xd32f78; ACCOUNT owns 13..20, GAME 21..116). The full wait API is 0xd32e08
  set-state, 0xd32e3c get-state (default 4), 0xd32e70 set-result -> session+828+4*slot,
  0xd330c4 get-result (default -24).

  **"ctx" is the session singleton** — the 75,608-byte (0x12958, from the memset in the init
  0xd355b4) network-manager object all three dispatchers receive from the receive pump 0xd34ff0,
  reached via `*(*(*(r2-31404)-32768))`. Its first three 68-byte records are the GATE/ACCOUNT/
  GAME connections (fd at +0). So ctx+0xDD8 = session+0xDD8, a slot belonging to the manager
  itself, not to any lobby object.

  ## The whole 0x2006/0x2007 exchange is DEAD CODE on this build [ELF 2026-08-03]

  Three independent zeros, each control-validated:

  * **The 0x2006 builder 0xd36900 has zero callers** — see `../inbound/mgo2_cmd_2006_c2s.ksy`
    for the scan and its sibling controls (0x2005's and 0x2008's builders return exactly one
    caller each under the identical scan).
  * **The slot-11 waiter thunk 0xd360f4 has zero callers**, while its slot-10 and slot-12
    neighbours in the same bank have one each (0x9463e8, 0x9464e8). The generic get-state
    0xd32e3c has 8 callers, for slots 36, 57, 58, 63/74, 72, 87, 87, 99 — never 11. So nothing
    resumes when this parser completes the wait.
  * **The value's only typed reader is dead** — see the field doc.

  Consequence for the server: **0x2007 can never be solicited by a disc-build client, and an
  unsolicited one is absorbed silently** (any value accepted, a wait state nobody reads, a slot
  nobody loads). Not a stall candidate, not a serving gap. Caveat on all three negatives: they
  are entry-point scans plus whole-image word scans that found each address only at its own OPD
  descriptor; an indirect `bctrl` through an unfound pointer table is the one shape not
  excluded. Nothing here transfers to 1.36.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/proto/inbound/mgo2_cmd_2006_c2s.ksy
seq:
  - id: unknown_00
    type: u4
    doc: |
      [UNKNOWN — no reader; PRECISE NEGATIVE 2026-08-03] Wire 0x00. The only field. Stored to
      `session+0xDD8` widened to 64 bits (`lwz` then `std` at 0xd364d4/0xd364dc). No error
      branch: any value is accepted.

      The 64-bit slot is a **nullable value with -1 = unset**, and that is its only observable
      semantic: the session init 0xd355b4 writes 64-bit -1 here at 0xd356a0 (alongside the
      three socket fds, the only other -1 fields in that reset), and the accessor 0xd35fdc is
      `s64 f(session) { return session ? *(s64*)(session+3544) : -1; }` — built to return the
      unset distinction a zero-extended u32 can never forge. The -1 init and the absence of any
      compare argue against a result/status reading; nothing further is nameable.

      **No reader anywhere in the image.** The displacement-3544 enumeration is closed: 21
      lines image-wide, 11 in .text, no `addi rX,rY,3544` pointer-form and no -61992
      `addis+1` split form anywhere. Of the 11: four are stack (r1) spills at
      0x4bd690/0x4bd870/0xa47854 and FP spills 0xb898cc/0xb8e7e0; 0xe95bc, 0x41187c, 0x9de804,
      0x9df1d4 and 0xa101cc all sit on bases provably not the session singleton (each writes or
      reads neighbouring offsets as independent u32s, incompatible with this slot's 64-bit
      shape); the remaining three are the session init (0xd356a0), this parser's own store
      (0xd364dc), and the sole typed reader 0xd35fe8 inside accessor 0xd35fdc — **which has
      zero `bl` and zero `b` callers image-wide**. Nothing reads the value.
