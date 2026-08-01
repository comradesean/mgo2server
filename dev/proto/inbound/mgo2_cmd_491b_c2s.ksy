meta:
  id: mgo2_cmd_491b_c2s
  title: "MGO2 0x491b — enter play with the current team (fresh entry or reconnect) (client -> server)"
  endian: be
doc: |
  **TEAM / OFFICIAL-TOURNAMENT block** — for why this family is teams and tournaments rather than
  clans, see the shared note in `mgo2_cmd_4904_c2s.ksy`.

  Sender `0xD4D9E4`, builder call `0xD4DAA8`, request-status slot `0x45` (69) completed with
  state 1 at `0xD4DB4C`.

  **Paired reply: `0x491C`** — slot bijection: the only `slot 69 = 1` site is this sender and the
  only `slot 69 = 2` site is `0xD4D9A0`, inside the parser at `0xD4D8D4` whose id check is
  `cmpwi r0,0x491C` at `0xD4D918`. `mgo2_cmd_491c_s2c.ksy` records that reply as
  result + two u32s on success (12 bytes), 4 bytes on failure.

  **THE THREE STRUCT-SOURCED FIELDS ARE TEAM-RECORD FIELDS.** The sender's `base` is
  `session + 0x10000`; the team record is at `session+0xD928` (the object returned by `0xD491F8`,
  which the team screens call). So:
    * `base-9276` = `session+0xDBC4` = **teamRecord+0x29C**
    * `base-9328` = `session+0xDB90` = **teamRecord+0x268**
  Both offsets are named in `mgo2_cmd_4913_s2c.ksy` — `+0x29C` is its `clan_serial`, `+0x268` its
  `unknown_f`. This is offset bijection on the same object, not name similarity.

  **Preconditions**, in order:
    * session validity (`0xD38504` / `0xD3844C`) → -24 / -36;
    * `0xD4908C(session)` non-zero → else **-1007**. That helper returns -1 exactly when
      `*(session+0xD928)` (the team id) is non-zero, so this is "you must be in a team";
    * `teamRecord.team_id == arg r4`, and non-zero → else **-1018** (`0xD4DA70`–`0xD4DA8C`).
      The u32 argument is therefore constrained to be the client's own team id.

  **After a successful send** the client fetches `session+0x11558` (`0xD3F7B0`) and, if non-NULL,
  zeroes its fields `+136` and `+140` (`0xD4DB38`/`0xD4DB3C`) — it is clearing a slot the reply
  is expected to refill. The two u32s `0x491C` carries are read into stack slots and not stored
  by that parser, so where they land is [UNKNOWN] from the reply side.

  **What triggers the send — two callers, and they differ only in the u8:**
    * `0x89386C`, in the screen that renders disc string 269 *"Participate in Official
      Tournament \"%s\"?"* — passes **0**;
    * `0x8F9E4C`, in the screen that renders disc string 80 *"Try to reconnect to team?"* —
      passes **1**, and takes the team id straight from `*(0xD491F8(session)+0x00)`.
  So the byte discriminates first entry from reconnect. That is the whole observed domain.

  Total payload: 11 bytes.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26, extended
  2026-08-01. Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a
  1024-byte payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at
  `pkt+0x00`; the enclosing function then appends fields with the serialisation primitives;
  `0xD5C828` finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends.
  Everything between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
doc-ref: dev/docs/PACKETS_NOT_OBSERVED.md
seq:
  - id: team_id
    type: u4
    doc: |
      [ELF — CERTAIN] `0xD5C9BC` at `0xD4DAB8`, source = sender arg r4 (spilled `1432(r1)`).
      The sender refuses to send unless it equals `teamRecord+0x00` and that value is non-zero
      (`0xD4DA80`–`0xD4DA8C`, failure -1018), and one of the two callers loads it from exactly
      that word. `teamRecord+0x00` is `mgo2_cmd_4913_s2c.ksy`'s `clan_id`, i.e. the record's own
      identity. So this is the client's own team id, echoed back to the server.
  - id: team_record_serial
    type: u2
    doc: |
      [ELF — SOURCE CERTAIN; SEMANTICS AS RECORDED FOR THAT STRUCT FIELD] `0xD5C918` (unsigned)
      at `0xD4DACC`, from `session+0xDBC4` = **teamRecord+0x29C**.

      That is the field `mgo2_cmd_4913_s2c.ksy` names `clan_serial` and describes as "the u16 the
      clan-event headers are validated against, and the value 0x49A8 updates… it behaves as a
      record version/serial". Reading it back out here — the client sending the server its own
      copy of the record's serial — is consistent with a **staleness / optimistic-concurrency
      token**, but that reading is [INFERRED]; the ELF proves only the offset.
  - id: entry_mode
    type: u1
    doc: |
      [ELF — SOURCE CERTAIN; DOMAIN OBSERVED AT BOTH CALL SITES] `0xD5C8A0` at `0xD4DADC`,
      source = sender arg r5 (spilled `1440(r1)`). The sender range-checks nothing.

      Both callers in the image are constant:
        * `0` from `0x89386C` — the Official Tournament entry confirmation (disc string 269);
        * `1` from `0x8F9E4C` — the reconnect confirmation (disc string 80, "Try to reconnect to
          team?").
      Named for that split. **Values other than 0 and 1 have no producer**, and what the server
      is supposed to do differently for each is [UNKNOWN] — the client's own handling of `0x491C`
      is identical either way.
  - id: team_field_0x268
    type: u4
    doc: |
      [ELF — SOURCE CERTAIN; MEANING UNKNOWN] `0xD5C9BC` at `0xD4DAF0`, from `session+0xDB90` =
      **teamRecord+0x268**, the field `mgo2_cmd_4913_s2c.ksy` carries as `unknown_f`.

      Named by its offset deliberately: the only thing established is that it is a verbatim
      read-back of a word the *server* put into the team record. No consumer, no domain, no unit.

      Provenance is closed for the `session+0x10000` addressing form: every `-9328` displacement
      in the whole disassembly is **two sites in this subsystem** — `0xD4DAE4` (this field) and
      `0xD4C788`, which is inside the parser for the unsolicited notification **`0x4961`**
      (`cmpwi r0,0x4961` at `0xD4C73C`) and *writes* the word from the wire with `0xD5CCD8`.
      (The two other `-9328` hits in the image, `0xE66A48` and `0xEACBB4`, are `tdlgti` and
      `addic` in unrelated code, not this base.) So the word is written by `0x4913` and by
      `0x4961`, and read back only here.
