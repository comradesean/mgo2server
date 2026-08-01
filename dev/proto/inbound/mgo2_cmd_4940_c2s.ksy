meta:
  id: mgo2_cmd_4940_c2s
  title: "MGO2 0x4940 — kick a team member by roster slot (leader only) (client -> server)"
  endian: be
doc: |
  **TEAM / OFFICIAL-TOURNAMENT block** — for why this family is teams and tournaments rather than
  clans, see the shared note in `mgo2_cmd_4904_c2s.ksy`.

  Sender `0xD4DB84`, builder call `0xD4DC70`, request-status slot `0x44` (68) completed with
  state 1 at `0xD4DCBC`.

  **Paired reply: `0x4941`** — slot bijection: the only `slot 68 = 1` site is this sender and the
  only `slot 68 = 2` site is `0xD49BD0`, inside the parser at `0xD49B48` whose id check is
  `cmpwi r0,0x4941` at `0xD49B8C`. `mgo2_cmd_4941_s2c.ksy` records it as a bare result ack.

  **WHAT IT DOES — read from the client's own dialog text.** The only caller is `0x8C22AC`, and
  the confirmation that precedes it in the same module is disc string **698**: *"You are about to
  kick\n%s off the team.\nAre you sure?"* (`0x8C1F08`); the menu row is disc string **691,
  "Kick"** (`0x8C0294`). The caller resolves the selected player to a slot number before
  sending (`0x8C2234`–`0x8C2278`):

      teamRec = *(screen+0x6C)          ; the team record
      target  = *(screen+0x70)          ; the selected player's character id
      idx = 0xFF
      for n in 0..7:                    ; mtctr 8, stride 28
          if *(teamRec + 380 + 28*n) == target: idx = n
      if idx == 0xFF: show error dialog 5143 and DO NOT SEND
      0xD4DB84(session, idx)

  `teamRec+380` is `teamRecord+0x17C`, the 8-entry member array modelled in
  `mgo2_cmd_4913_s2c.ksy`, and `+0` of a member is its `character_id`. So the wire byte is a
  **roster slot index, not a player id** — the same struct bytes, established by offset, not by
  name resemblance. `0xFF` is filtered out client-side and never reaches the wire.

  **Preconditions**, in order:
    * session validity (`0xD38504` / `0xD3844C`) → -24 / -36;
    * `0xD4908C(session)` non-zero → else **-1007** ("you must be in a team");
    * `*(teamRecord+0x17C) == *(0xD3A094(session))` → else **-1014** — members[0].character_id
      against the local player's, i.e. **leader only** (same guard as `0x4920` and `0x4923`);
    * `idx <= 7` → else **-24** (`cmplwi cr7,r9,7` / `bgt` at `0xD4DC2C`). This corrects the old
      note in this file that said "no value guard": there is one, it is just further down;
    * `members[idx]` state byte at **slot+0x15** must be **1 or 2** → else **-1012**
      (`lbz r9,17(r9)` off `teamRec+384+28*idx`, then `addi -1` / `cmplwi 1` / `bgt` at
      `0xD4DC4C`–`0xD4DC5C`). That byte is `unknown_15` in `mgo2_cmd_4913_s2c.ksy`, described
      there as "a per-member state byte". What 1 and 2 mean is [UNKNOWN]; what is established is
      that only members in those two states are kickable, so an empty or pending slot is refused
      locally.

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
  - id: member_slot
    type: u1
    doc: |
      [ELF — CERTAIN, including the domain] `0xD5C8A0` at `0xD4DC80`, source = sender arg r4
      (`stb 1432(r1)` at `0xD4DBB8`).

      **0..7**, an index into the team record's 8-entry member array at `teamRecord+0x17C`
      (`mgo2_cmd_4913_s2c.ksy`, type `member`, 28-byte struct stride). The sender rejects > 7
      with -24 and rejects a slot whose per-member state byte at `member+0x15` is not 1 or 2 with
      -1012.

      A server implementing this must resolve the slot against **its own** copy of the roster in
      the same order it sent in `0x4913`, because the client sends a position, not an identity.
      The reply `0x4941` is a bare result; the roster change reaches other clients through the
      `0x496x` member notifications, not through this ack.
