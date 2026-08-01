meta:
  id: mgo2_cmd_2004_s2c
  title: "MGO2 0x2004 — lobby-list end (server -> client)"
  endian: be
doc: |
  Closes the gate lobby list (reply 3/3 to `0x2005`). Parser arm 0xd36438, GATE dispatcher
  0xd361e8.

  **The parser reads no bytes**: `READ_BEGIN` (0xd5c844) immediately followed by `READ_END`
  (0xd5c858), then `notify(event 10, state 2)` at 0xd32e08 — the completion that releases the
  lobby-list wait — and `marker = 0` (stw at `0(r31)`), closing the list.

  Guard: `lwzu r0,1872(r31); cmpwi r0,0; beq -> bail(-73)` — the marker must be non-zero, i.e.
  `0x2002` must have run first. Sending `0x2004` without `0x2002` is silently dropped and the
  wait never completes.

  Same contradiction with PROTOCOL.md as `0x2002`: documented as "4 bytes: 00000000", actually
  unread.
doc-ref: dev/docs/PROTOCOL.md "0x2005 — get lobby list"; dev/docs/LOBBIES.md
seq:
  - id: dead_body
    size-eos: true
    doc: |
      [ELF — PRECISE NEGATIVE, re-run 2026-08-01] **Neither a result code nor a count, and not read
      at all.** The arm at `0xd36438` calls `READ_BEGIN` (`0xd36460`) and `READ_END` (`0xd3646c`)
      with **no `bl` to any read primitive in between**, then `0xd32e08(session, event 10, state 2)`
      and `stw r0,0(r31)` with `r0 = 0` — the list marker close. Nothing consumes a payload byte.

      Contrast the packets that DO carry a u32 here, which settles which of the two shapes the
      family uses: `0x4903` (`0xD47758`) reads a u32 at `0xD47794` and publishes it into request
      slot 56 with **`lwa`** (`0xD477D4`) — sign-extended, i.e. a negative error code — and
      `0x4901` (`0xD47850`) additionally *branches* on it, refusing to open the list when it is
      nonzero (`0xD478B4`). That is a result code; an entry count could not drive that branch.

      We send `00 00 00 00`. If it is ever made meaningful, it must be a **zero result code**, not
      a count — see `mgo2_cmd_2002_s2c.ksy` for the same argument at greater length and for the
      `1032:00000005` incident that is the reason this distinction is written down.
