meta:
  id: mgo2_cmd_4440_c2s
  title: "MGO2 0x4440 — team / spectator change (client -> server)"
  endian: be
doc: |
  Builder function `0xD52A44` = `f(ctx, u8 arg)` (`stb r4,1416(r1)` at `0xD52A70`);
  `bl 0xD5CF40` at `0xD52AB8` (`li r4,0x4440` at `0xD52AB4`). One `0xD5C86C` (u8) write at
  `0xD52AC8`, seal `0xD5C828` at `0xD52AD4`, flush `0xD34CC0` at `0xD52AE4`. Not encrypted.
  **Total payload 1 byte.** The argument is not validated or range-checked.

  This settles one open question in `PROTOCOL.md` "`0x4440` — unknown", which reports the two
  reference servers disagreeing: Nomad parses nothing, mgo2-server registers it twice, once as
  an unknown ack and once as a "GetPlayerOptions" reading a u8. **The ELF says the request is
  exactly one u8** — so the shape mgo2-server's second registration assumes is the right one,
  independently of its name or its 5-byte reply. The *meaning* of the byte is still unestablished.

  Live context from `PROTOCOL.md`'s admin-action table: `0x4440` exchanges accompany an accepted
  team change, and the `0x4440`/`0x4344` pair fires on host Restart — consistent with a team or
  spectator-slot selector, not asserted.
doc-ref: dev/docs/PROTOCOL.md "0x4440 — unknown"
seq:
  - id: team
    type: u1
    doc: |
      [CONFIRMED, ELF 2026-08-01; renamed from `unknown_00`] 0x00 — the whole payload is this one
      byte, position and width exact from `0xD52AC8`. **The player's own team, 1-based**, and the
      only values the client can produce are **1 and 2**.

      The builder `0xD52A44` does not validate the byte, so the answer is at the call site.
      **`0xD52A44` has exactly one `bl` site in the image, `0xCA031C`**, and its OPD descriptor at
      `0x1029E30` is referenced by no data word (`ET_EXEC`, no relocations), so that call site is
      the whole story. It computes the argument from the local player's replicated character
      record:

          ca01a0  bl 0x26e9a0                   ; my own roster slot index (u8)
          ca01d4  rec = 0x27ef90(idx + 1)       ; -> my character record
          ca01ec  if (!0x27ee78(rec, 1, 1)) skip; field 1 must be present
          ca02e8  0x27f160(rec, 1, 1, &v)       ; v = record field 1
          ca0300  lbz  r4,112(r1)               ; v
          ca0304  xori r4,r4,1
          ca030c  neg  r4,r4
          ca0310  srwi r4,r4,31                 ; (v != 1) ? 1 : 0
          ca0314  subfic r4,r4,2                ; -> v == 1 ? 2 : 1
          ca031c  bl 0xd52a44

      `0x27F160(record, field, len, &out)` is the replicated-variable accessor — the same one
      `0x43A6` uses to fetch field 332. **Field 1 is the team/role slot**, established
      independently of this packet by its writers, all of which go through the single setter
      `0x275FE0(entry, u8)` (`0x27F258(rec, 1, 1, &v)` at `0x276050`, then `stb v,1(entry)` and
      `entry[8] |= 0x40`):

      * `0x6EB4F0` — the **auto-balance picker**: compares the two per-team counters
        `game[1360 + team*4 + 8]` and `game[1376 + team*4 + 8]` for `team = 0` and `team = 1`, with
        an LCG tiebreak (`x = x*0x5D588B65 + 1` at `0x6EB528`), and returns 0 or 1. Written into
        field 1 at `0x6E9A1C`, `0x6E9A84`, `0x6EA214`, `0x6EA27C`.
      * `li r4,2` at `0x6E99E4`, `0x6E9A4C`, `0x6EA1DC`, `0x6EA244` — a third role, taken for the
        entries named by two byte slots in the round state (`+272`, `+280`).
      * `li r4,254` at eleven sites (`0x6F6E28`, `0x6F6E58`, `0x6F77CC`, `0x6F81F8`, `0x6F822C`,
        `0x6F8B00`, `0x6FFB3C`, `0x701448`, `0x701498`, `0x714784`, `0x71489C`) — the "no team"
        sentinel.

      So field 1 is 0-based with `0xFE` for none, and `v == 1 ? 2 : 1` maps team 0 -> 1 and team
      1 -> 2, i.e. **the wire byte is the 1-based team index**, with everything else (the third
      role, and the `0xFE` sentinel) collapsing onto 1. The graduation eligibility scan's
      `entry[1] <= 2` occupancy test (`mgo2_cmd_43c8_c2s.ksy`) is the same field read directly.

      This settles the two candidates `PROTOCOL.md`'s live pairing left open: it is the **team
      index**, not a spectator flag — there is no encoding here for "spectator", and the `0xFE`
      sentinel never reaches the wire.

      **A width note for the server, not a change to this schema.** `0x4344` carries the *same*
      field at its own offset `0x04` and sends it **raw** — `lbz r5,1(entry)` at `0x277B88` — so
      that packet can legitimately carry 0, 2 or 254 where this one cannot. The two are not
      interchangeable; see `mgo2_cmd_4344_c2s.ksy`.
