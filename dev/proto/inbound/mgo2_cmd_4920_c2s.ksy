meta:
  id: mgo2_cmd_4920_c2s
  title: "MGO2 0x4920 — leader-only team request, u32 + u8, no caller in this build (client -> server)"
  endian: be
doc: |
  **TEAM / OFFICIAL-TOURNAMENT block** — for why this family is teams and tournaments rather than
  clans, see the shared note in `mgo2_cmd_4904_c2s.ksy`.

  Sender `0xD4BA94`, builder call `0xD4BB44`, request-status slot `0x42` (66) completed with
  state 1 at `0xD4BBA0`.

  **Paired reply: `0x4921`** — slot bijection: the only `slot 66 = 1` site is this sender and the
  only `slot 66 = 2` site is `0xD49D58`, inside the parser at `0xD49CD0` whose id check is
  `cmpwi r0,0x4921` at `0xD49D14`. `mgo2_cmd_4921_s2c.ksy` records that parser as a **bare
  result ack** — one s4, nothing stored, nothing rendered. So `0x4920` is a *command*, not a
  query: the reply carries no data back.

  **THE GUARD IS "I AM THE TEAM LEADER".** [ELF — corrects the earlier "still in the same
  context" reading in this file.] In order:
    * session validity (`0xD38504` / `0xD3844C`) → -24 / -36;
    * `0xD4908C(session)` non-zero → else **-1007**; that helper returns -1 exactly when
      `*(session+0xD928)` (the team id) is non-zero, i.e. "you must be in a team";
    * `*(session+0xDAA4) == *(0xD3A094(session))` → else **-1014** (`cmpw` at `0xD4BB2C`).
      `session+0x10000-9564 = session+0xDAA4`, and the team record starts at `session+0xD928`,
      so the left side is **teamRecord+0x17C = members[0].character_id** — the first slot of the
      8-entry member array `mgo2_cmd_4913_s2c.ksy` models. `0xD3A094` returns `session+0x57D8`,
      whose first word the same comparison treats as the local player's character id. Member
      slot 0 is therefore the **team leader**, and this is a leader-only command.
    The identical guard appears in `0x4923` (`0xD4DD80`) and `0x4940` (`0xD4DC18`), the two
    leader-only actions with real callers, which is the cross-check.

  **DEAD SENDER — no caller in the image.** [ELF — VALIDATED SWEEP, 2026-08-01]
  Same method and same pass as `mgo2_cmd_4908_c2s.ksy`: every instruction in `0x10230`–`0xDE9328`
  decoded, every `bl` / `b` / `bc` / `bcl` (opcodes 18 and 16, `AA=0` and `AA=1`) to `0xD4BA94`
  collected — zero. The same pass found the callers of the five live senders in this batch, so it
  is validated against controls. The whole file was also searched for the OPD descriptor address
  `0x1029B90` as u32 and u64 — zero — but that check proves nothing on its own here, since all
  seven descriptors in this batch have zero data references including the five that are called.

  **Argument order is not wire order.** The sender takes r4 = u8 (`stb 1416(r1)`) and r5 = u32
  (`stw 1424(r1)`) and emits the **u32 first**. Kept flagged because this project has been bitten
  by exactly that mismatch before.

  Total payload: 5 bytes.

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
  - id: unknown_00
    type: u4
    doc: |
      [ELF — POSITION CERTAIN; MEANING UNKNOWN] `0xD5C9BC` at `0xD4BB54`, source = sender arg
      **r5** (spilled `1424(r1)`).

      Deliberately left unnamed. Every other id in this batch was named from its call site, and
      **this sender has none** (see the sweep above), so there is no producer to read a domain
      from. The sender range-checks nothing and copies nothing out of the team record, so the
      value is wholly the caller's — and the caller does not exist in this image.
      Open question: whether `0x4920` is one of the team actions whose UI was cut before release
      (Disband Team and Accept Entry both have disc strings — 692, 693 — and neither has been
      matched to a request id in this batch).
  - id: unknown_04
    type: u1
    doc: |
      [ELF — POSITION CERTAIN; MEANING UNKNOWN] `0xD5C8A0` at `0xD4BB64`, source = sender arg
      **r4** (spilled `1416(r1)`, byte-sized at the API boundary). No range check, no caller,
      therefore no observed domain. See the field above.
