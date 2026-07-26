meta:
  id: mgo2_cmd_0005
  title: "MGO2 0x0005 — ping (client -> server) and its reply (server -> client)"
  endian: be
doc: |
  **Bidirectional and identical: both directions are empty. Zero bytes each way, confirmed from
  the binary on both sides.** One id, one file at the root of `blanks/` rather than a copy in
  each direction folder, because a single `seq: []` describes both and two files would differ
  only in prose. `0x49c0` is the other both-directions id and does NOT live here — its two
  directions are unrelated layouts, so it is split across `inbound/` and `outbound/`.

  ### Client -> server (the request)

  Builder call site `bl 0xd5cf40` at `0xd35ae4` (`li r4,5` at `0xd35adc`). Between the builder and
  the seal (`bl 0xd5c828` at `0xd35af0`) there are no write-primitive calls, so the sealed payload
  length is 0. Flush `bl 0xd34cc0` at `0xd35b0c`. [ELF]

  A request-status slot IS registered afterwards — `addi r4,r29,7` at `0xd35b14` then
  `bl 0xd32e08` — i.e. the wait slot is computed from the sender's argument (`r29 + 7`, with
  `r29` range-checked <= 2 at `0xd35aa4`), so ping is per-target and the client does block on a
  reply. [ELF]

  ### Server -> client (the reply)

  Registered in all three lobby dispatchers, each a trampoline into the shared handler
  **0xd359c8**:

    * GATE    dispatcher 0xd361e8, arm 0xd367a0 -> `bl 0xd359c8`, `r4 = 0`
    * ACCOUNT dispatcher 0xd37074, arm 0xd37894 -> `bl 0xd359c8`, `r4 = 1`
    * GAME    dispatcher 0xd38804, arm 0xd39544 -> `bl 0xd359c8`, `r4 = 2`

  0xd359c8 calls `READ_BEGIN` (0xd5c844 at 0xd35a24) and `READ_END` (0xd5c858 at 0xd35a30) back to
  back with **nothing in between**, then `notify(r4 + 7, state 2)` at 0xd35a38. So:

    * the reply body is never read — an empty payload is not merely acceptable, it is
      indistinguishable from any other payload;
    * the `r4 + 7` slot on the reply side is the **same expression** the sender uses at 0xd35b14,
      and the reply arm's `r4` literal (0/1/2, one per dispatcher) supplies the lobby kind the
      sender range-checked. The two halves match exactly: ping slots are 7 (gate), 8 (account),
      9 (game). The halves were traced independently, so each confirms the other.

  This settles PROTOCOL.md's flagged item 25 ("`0x0005` ping replies with an empty payload rather
  than echoing the request", previously reference-derived and not observed): echoing would be
  harmless but pointless, since the client cannot read the echo.
doc-ref: dev/docs/PROTOCOL.md "0x0005 — ping"
seq: []
