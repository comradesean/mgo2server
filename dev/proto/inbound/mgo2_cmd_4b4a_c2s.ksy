meta:
  id: mgo2_cmd_4b4a_c2s
  title: "MGO2 0x4b4a — fetch a clan's emblem for display (client -> server)"
  endian: be
doc: |
  **The emblem display fetch.** 4-byte payload: the clan id whose emblem is wanted, unsigned
  big-endian. Reply is `0x4b4b`, `{s4 result, byte[768]}` — the same shape as `0x4b49` and
  `0x4b4d`.

  [CONFIRMED 2026-07-27] The 768-byte block is the **clan emblem**, not an opaque or unknown
  blob and not a name table — see mgo2_cmd_4b48_c2s.ksy for the correction and the parser
  addresses. Unlike 0x4b48, which can only ask for the caller's own clan (the id comes out
  of the client's cached record), this one carries an id the *screen* chose, so it is the
  path by which any clan's emblem gets drawn.

  Serving it matters beyond the emblem screen: a clan viewed from search or from the clan
  list renders its emblem only if the emblem-present flag reached the client
  (`0x4b21`/`0x4b81` at `T+0x378`, 3 when a published emblem exists). With that flag zero
  the client never fetches at all, so an emblem that exists looks like one that does not.

  Evidence (ELF, retail BLUS30109): sender 0xD56704. Builder `bl 0xD5CF40` at 0xD56778
  (`li r4,0x4b4a` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only — no clan-record gate, consistent with a fetch that
  may name a clan the caller has nothing to do with.

  On a successful flush the client advances its flow state with `0xD32E08(session, 102, 1)`.
  The sender does not name the reply id.
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The clan whose emblem is being fetched — chosen by the screen,
      so not necessarily the caller's own. Position and width exact (unsigned, 0xD5C9BC);
      the caller's u32 verbatim, unvalidated by the sender. A clan with no stored emblem is
      answered with result 0 and 768 zeros, which the parser accepts — its only requirement
      is the length.
