meta:
  id: mgo2_cmd_2002_s2c
  title: "MGO2 0x2002 — lobby-list start (server -> client)"
  endian: be
doc: |
  Opens the gate lobby list (reply 1/3 to `0x2005`). Parser arm 0xd36260, GATE dispatcher
  0xd361e8.

  **The parser reads no bytes.** The arm calls `READ_BEGIN` (0xd5c844) and then `READ_END`
  (0xd5c858) back to back with nothing in between; its whole effect is to reset the list at
  `ctx+0x750`: `count = 0` (stw at `4(r28)`) and `marker = -1` (stw at `0(r28)`). The `-1`
  marker is what `0x2003` and `0x2004` require in order to run at all.

  Guard: `lwzu r31,1872(r28)` then `cmpwi r31,0; bne -> bail(-73)` — the list marker must
  already be **0** (i.e. no list in progress) or the packet is rejected.

  Contradiction with PROTOCOL.md (recorded, not resolved): PROTOCOL.md's `0x2005` table gives
  `0x2002` as "4 bytes: 00000000 (result, GameError.NONE)". The four bytes are harmless but
  they are **not read** — unlike `0x2009` and `0x4211`, the sibling start packets in other
  triples, which do read one u32. See also dev/proto/README.md's note that the list start/end
  packets are "a single u32 result code": true for the `0x46xx` triples, false for `0x2002`.
doc-ref: dev/docs/PROTOCOL.md "0x2005 — get lobby list"; dev/docs/LOBBIES.md
seq:
  - id: dead_body
    size-eos: true
    doc: |
      [ELF — PRECISE NEGATIVE, re-run 2026-08-01] **Neither a result code nor a count. It is not
      read at all**, and the parser is short enough to quote in full:

          d36260  bl 0xd36178          ; get read context
          d36270  cmpwi cr7,r0,8194    ; re-check the id (0x2002)
          d36278  lwzu r31,1872(r28)   ; guard: marker must be 0
          d36288  bl 0xd5c844          ; READ_BEGIN
          d36294  bl 0xd5c858          ; READ_END      <- nothing in between
          d3629c  li r0,-1
          d362a4  stw r31,4(r28)       ; count = 0 (r31 is the guard value, proven 0 above)
          d362a8  stw r0,0(r28)        ; marker = -1

      There is no `bl` to any read primitive between `READ_BEGIN` and `READ_END`, so no byte of the
      payload is consumed. `count` is not read off the wire either — it is stored from the register
      the zero-guard just tested.

      **Why "result code or count" is a real question and how it is settled here.** The sibling
      start/end packets of the other list triples DO read one u32, and it is unambiguously a
      **signed result code**, not a count: `0x4901`'s parser (`0xD47850`) reads a u32 at `0xD4778C`
      and then, at `0xD478B4`, branches on it — **nonzero** publishes it into request slot 56 with
      `lwa` (`0xD478D8`, sign-extending, i.e. negative error codes) and leaves the list marker
      **0** so the list never opens; **zero** sets slot 56 to 0 and opens the list. `0x4903`
      (`0xD47758`) does the same at `0xD477D4`. A count could not drive that branch — a legitimate
      list of zero entries would read as an error.

      We send `00 00 00 00` and it is inert here. If it is ever changed, change it to a **zero
      result code**, never to an entry count: `0x2002` is the only start packet in the family whose
      parser would not notice, and the one time this project shipped a count where a result code
      was expected the client printed `1032:00000005` (live 2026-07-23).
