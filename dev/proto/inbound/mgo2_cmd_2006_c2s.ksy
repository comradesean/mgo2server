meta:
  id: mgo2_cmd_2006_c2s
  title: "MGO2 0x2006 — unidentified gate/lobby-layer request (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd36968` (`li r4,8198` = `0x2006` at
  `0xd36960`), sender `0xd36900`. Seal `bl 0xd5c828` at `0xd36974` with no intervening write
  primitive; flush `0xd36984`; wait slot `0x0b` (`li r4,11` at `0xd3698c`). [ELF]

  COMMANDS.md lists `0x2006` under "misc — lobby-layer / isolated" gaps, with no shape.
  This settles the request side: it takes no payload, and the client **does** register a wait
  slot, so it blocks on a reply. The sender is a near-identical sibling of `0x2005`'s
  (`0xd369d0`) — same prologue, same guards (`bl 0xd3614c`, `bl 0xd367f0`), consecutive in the
  binary, differing only in the id and the slot. [ELF]

  ## CORRECTION 2026-08-03: the sender is DEAD CODE, and the reply is 0x2007 — tier-1

  * **Zero callers.** `0xd36900` has no `bl` and no `b` over the whole executable range.
    Control, per the ADDRESSES.md rule: its two byte-identical siblings in the same bank each
    return exactly one caller — `0xd369d0` (`0x2005`, slot 10) from `0x94633c`, and `0xd3681c`
    (`0x2008`, slot 12) from `0x90f044` — and the same scan reproduces ADDRESSES.md's known
    counts (`0xd40e2c` -> 3, `0xd53f10` -> 4). The zero is real. The wait-side thunk for slot
    11, `0xd360f4`, likewise has zero callers while its slot-10/slot-12 neighbours have one
    each. So **this build cannot send 0x2006** — it moves from "sendable, unanswered" to the
    parked set, and is not a serving gap. (Caveat: the negatives are entry-point scans plus a
    whole-image word scan that found each address only at its own OPD descriptor; an indirect
    `bctrl` through an unfound pointer table is the one shape not excluded. Nothing here
    transfers to 1.36.)
  * **The reply is `0x2007`**, no longer presumed: this sender opens wait slot 11
    (`li r4,11` at `0xd3698c`) and the `0x2007` parser arm is the unique closer of slot 11
    (`0xd364ec`). Slot 11 is one of the three GATE-owned wait slots (10..12, partitioned at
    `0xd32f6c`-`0xd32f78`). See `../outbound/mgo2_cmd_2007_s2c.ksy`.

  **[UNKNOWN]** what it asks for — and with sender, waiter and the reply value's reader all
  dead, nothing on this build can say.
doc-ref: dev/docs/COMMANDS.md "Unmodelled subsystems" (misc block)
seq: []
