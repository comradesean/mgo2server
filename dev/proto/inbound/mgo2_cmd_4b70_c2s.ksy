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

  ## The request's u32 is not established

  [UNKNOWN]. The clan id is the obvious reading and the only candidate anyone has proposed,
  but nothing has tested it: the server answers from the caller's session and ignores the
  payload entirely, and the screen renders correctly, so no observation to date could
  distinguish "clan id" from anything else. Naming it would be a guess dressed as a finding,
  so it keeps its `unknown_` name and this file stays a draft. The experiment that would
  settle it is to view the statistics of a clan other than one's own, if the screen offers
  that at all, and see whether the word changes.

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
  - id: unknown_0000
    type: u4
    doc: |
      [UNKNOWN] Position and width exact (unsigned, 0xD5C9BC). The caller's u32 verbatim,
      unvalidated; nothing in the sender narrows it and the server has never had to read it.
      A clan id is the structural expectation given every neighbouring command in the family,
      but that is an expectation, not evidence.
