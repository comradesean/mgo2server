meta:
  id: mgo2_cmd_4923_c2s
  title: "MGO2 0x4923 — set or clear the team's clan affiliation (leader only) (client -> server)"
  endian: be
doc: |
  **TEAM / OFFICIAL-TOURNAMENT block** — for why this family is teams and tournaments rather than
  clans, see the shared note in `mgo2_cmd_4904_c2s.ksy`.

  Sender `0xD4DCF4`, builder call `0xD4DDCC`, request-status slot `0x43` (67) completed with
  state 1 at `0xD4DE18`.

  **Paired reply: `0x4924`** — slot bijection: the only `slot 67 = 1` site is this sender and the
  only `slot 67 = 2` site is `0xD49C94`, inside the parser at `0xD49C0C` whose id check is
  `cmpwi r0,0x4924` at `0xD49C50`. `mgo2_cmd_4924_s2c.ksy` records it as a bare result ack.

  **WHAT IT DOES — read from the client's own dialog text.** The only caller is `0x8C20D4`, in
  the team screen. Immediately before it, the confirmation dialog at `0x8C1F88` picks between two
  disc strings on **bit 6 of the team record's flags word at `+0x94`**:
    * bit clear → string **701**: *"This will affiliate the team with the team leader's clan.
      Match results will be reflected in the clan's stats. Do you wish to proceed?"*
    * bit set  → string **702**: *"Are you sure you want to cancel the team's clan affiliation?"*
  The menu row that opens it is disc string **689, "Set Clan Affiliation"** (`0x8BFF48`).
  The caller then computes the byte as `((flags94 ^ 0x40) >> 6) & 1` at `0x8C20C4`–`0x8C20D0`,
  i.e. **the inverse of the current bit** — it is a toggle, sent as an absolute value.

  **Cross-packet, by struct-offset bijection.** `mgo2_cmd_4913_s2c.ksy` reads a one-byte `flags`
  field and expands wire bit 0 → `0x80`, bit 1 → `0x40`, bit 2 → `0x10` of the u32 at
  `record+0x94`. Bit 6 of that word is therefore **`0x4913` flags wire bit 1 = the clan
  affiliation bit**, and the sibling bit 7 (wire bit 0) is the password lock — see
  `mgo2_cmd_4912_c2s.ksy`. Same struct bytes, not similar names. Wire bit 2 (`0x10`) is still
  [UNKNOWN].

  **Preconditions**, in order:
    * session validity (`0xD38504` / `0xD3844C`) → -24 / -36;
    * `0xD4908C(session)` non-zero → else **-1007** ("you must be in a team": that helper returns
      -1 exactly when `*(session+0xD928)`, the team id, is non-zero);
    * `*(session+0xDAA4) == *(0xD3A094(session))` → else **-1014**. `session+0xDAA4` is
      `teamRecord+0x17C` = **members[0].character_id**, so this is the leader-only gate (same
      guard as `0x4920` and `0x4940`);
    * `value <= 1` → else **-24** (`cmplwi cr7,r0,1` / `bgt` at `0xD4DD94`). The field is a
      strict boolean;
    * **only when setting to 1**: `*(0xD3A094(session) + 0x1AA0)` must be non-zero → else
      **-1035** (`0xD4DDA4`–`0xD4DDB0`). Reading that as "you must belong to a clan yourself" is
      [INFERRED] from the dialog wording; the ELF proves only that a word in the local player
      object must be non-zero.

  Total payload: 1 byte.

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
  - id: clan_affiliation
    type: u1
    doc: |
      [ELF — CERTAIN, including the domain] `0xD5C8A0` at `0xD4DDDC`, source = sender arg r4
      (`stb 1432(r1)` at `0xD4DD20`).

      **0 or 1 only** — the sender returns -24 for anything larger (`0xD4DD94`). 1 = affiliate
      the team with the team leader's clan; 0 = cancel that affiliation. The value is the
      requested new state of the bit `mgo2_cmd_4913_s2c.ksy` carries as `flags` wire bit 1
      (`record+0x94` bit `0x40`), and the caller derives it by inverting the current bit
      (`0x8C20C4`–`0x8C20D0`).

      A server implementing this must set that flag bit in the team record and reflect it in the
      next `0x4913`; the reply `0x4924` carries only a result code, so the flag never travels
      back on the ack.
