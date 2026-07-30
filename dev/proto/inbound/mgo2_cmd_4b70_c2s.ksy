meta:
  id: mgo2_cmd_4b70_c2s
  title: "MGO2 0x4b70 — clan statistics request (client -> server)"
  endian: be
doc: |
  **The clan statistics request**, from Clan Affiliation. 4-byte payload: one unsigned u32.

  ## The reply is a pair, and sending the wrong number of packets stalls the screen

  [CONFIRMED 2026-07-27] Exactly **one** `0x4b71` (584 bytes) then **one** `0x4b72` (580
  bytes). `0x4b71` is `{s4 result, s4 page, 8*18*4 grid}`; `0x4b72` is
  `{s4 result, 2*72*4}`.

  Sending two `0x4b71`s — one per page, as `0x4105` legitimately does for its
  cumulative/weekly pair — **breaks it**: the first reply completes the request slot, so the
  second arrives unexpected and Clan Affiliation stalls with *"unable to acquire clan
  information (1931:FFFFFF60)"*. This is the one place in the family where an *extra*
  well-formed packet is the fault rather than a missing one.

  `0x4b71`'s page word must be **2 or 3**. Any other value fails the whole packet with -71
  and discards the grid (`0xD599C8`) — which is why a zero there rendered as "no records"
  rather than as zeroed statistics. Page 2 additionally zeroes all four page slots on
  receipt.

  ## The request's u32 IS the clan id — settled 2026-07-30, from the binary

  This file used to say the clan id was "a guess dressed as a finding" because no *observation*
  could distinguish it. It did not need an observation: the argument is traceable to its two
  sources.

  `0xD56440` is `f(session, u32)` and has two `bl` sites.

  * **0xA880F4**, inside `0xA87FF0(screen, value)` — `mr r28,r4` at 0xA88014, `clrldi r4,r28,32`
    at 0xA880E8, so the u32 is that function's second argument verbatim. `0xA87FF0` has five
    callers, in two shapes:
      * `0xABE748`, `0xAC1F00`, `0xAE225C` — walk to the selected node of a UI list, then
        `lwz r9,0(r3)` (the row pointer the clan-list builders parked there) and **`lwz r4,0(r9)`**.
        Offset 0 of a `0x4b12` row is `clan_id`. That is the whole derivation.
      * `0xAB59EC`, `0xAB9F1C` — `bl 0xD56EDC` then `lwz r4,0(r3)`. `0xD56EDC(session)` returns
        `profile+6816` (0xD56F04), the local clan record, whose first word is the id `0x4b47`
        writes.
  * **0xA7DFA8**, in the generic clan request dispatcher `0xA7DC48`, where the value is that
    function's fourth argument and reaches it from a request descriptor.

  Both concrete sources are a clan id: the one you picked out of the clan list, or your own.
  The server may still answer from the session — it does today, and the screen renders — but it
  is now free to honour the id and show another clan's statistics.

  Evidence (ELF, retail BLUS30109): sender 0xD56440. Builder `bl 0xD5CF40` at 0xD564B4
  (`li r4,0x4b70` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only.

  On a successful flush the client advances its flow state with `0xD32E08(session, 111, 1)`.
  The sender does not name the reply id.
seq:
  - id: clan_id
    type: u4
    doc: |
      [ELF — NAMED 2026-07-30] **The clan whose statistics are wanted.** Position and width exact
      (unsigned, 0xD5C9BC). The caller's u32 verbatim and unvalidated by the sender — but both of
      the values that reach it are clan ids, so the field is settled from the binary rather than
      from a capture:

      * from a clan-list row: `lwz r9,0(r3)` on the selected node then `lwz r4,0(r9)` at
        0xABE744, 0xAC1EFC, 0xAE2258 — offset 0 of a `0x4b12` record is `clan_id`;
      * from the local clan record: `bl 0xD56EDC` (returns `profile+6816`) then `lwz r4,0(r3)`
        at 0xAB59E0, 0xAB9F10 — the same id `0x4b47` writes there.

      See the top-level doc for the call chain through `0xA87FF0` and `0xA7DC48`. Our server still
      answers from the session and ignores this word; honouring it is what would let the screen
      show a clan other than your own.
