meta:
  id: mgo2_cmd_4b80_c2s
  title: "MGO2 0x4b80 — clan info for a clan you are NOT in (client -> server)"
  endian: be
doc: |
  **Clan Info for a clan picked out of the list or the search results — including one the
  player does not belong to.** 4-byte payload: the clan id, unsigned big-endian. Reply is
  `0x4b81`, a 217-byte partial profile on success, occupying request slot 113.

  ## Why this exists alongside 0x4b20

  [CONFIRMED 2026-07-27] `0x4b20`'s reply **cannot** serve a non-member: the client
  cross-checks `0x4b21`'s id against the clan id it already holds and drops the packet on a
  mismatch. `0x4b81`'s `subject_id` is explicitly **not** cross-checked, and that asymmetry
  is the whole reason for the pair — this is the "look at someone else's clan" path and
  0x4b20 is the "look at my own" path.

  ## It also unblocks joining

  This reply is what populates the client's session clan record at `session_ctx+0x1AA0`, and
  `0x4b42` (apply to join) **refuses to transmit** unless that record holds a non-zero id —
  it returns -24 (0xFFFFFFE8) and sends nothing. So while `0x4b81` was 217 zero bytes,
  pressing Apply failed with -24 and no packet ever left the client; Apply looked
  unimplemented when it had simply never been sent. See mgo2_cmd_4b42_c2s.ksy.

  Fields established in the reply, recorded here because they are what the request is for:
  `T+0x00` id, `T+0x04` name[16], `T+0x18` founding date, `T+0x1c` leader name[16], `T+0x58`
  member count, `T+0x378` emblem-present flag (3), `T+0x67A` description[128]. `T+0x18` and
  `T+0x58` are the founding date and the member count **in that order**, not the reverse:
  swapped, the info screen showed 1785129141 members — the epoch seconds, verbatim.

  Evidence (ELF, retail BLUS30109): sender 0xD56268. Builder `bl 0xD5CF40` at 0xD562DC
  (`li r4,0x4b80` in the preceding instruction); the ONLY payload write between the builder
  and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer (4 bytes, MSB
  first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the sender's own r4
  parameter, spilled by `stw r4,1416(r1)` in the prologue and passed back by address; the
  function range-checks it not at all.

  Preconditions: session != NULL only — no clan-record gate, which is exactly right for a
  command that must work before the caller has any clan at all.

  On a successful flush the client advances its flow state with `0xD32E08(session, 113, 1)`.
  The sender does not name the reply id.
seq:
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The clan being looked at, chosen from the clan list or the
      search results — routinely a clan the caller has nothing to do with. Position and
      width exact (unsigned, 0xD5C9BC); the caller's u32 verbatim, unvalidated by the
      sender.

      An id the server cannot find must be answered with a 4-byte failure rather than a
      zero-filled block: the client does not validate this one against its own record, so a
      zeroed reply renders as a real nameless clan and, worse, leaves the session clan
      record holding an id of 0, which silently disables Apply.
