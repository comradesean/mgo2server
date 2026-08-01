meta:
  id: mgo2_cmd_4912_c2s
  title: "MGO2 0x4912 — join a team, with the team's password if it is locked (client -> server)"
  endian: be
doc: |
  **TEAM / OFFICIAL-TOURNAMENT block** — for why this family is teams and tournaments rather than
  clans, see the shared note in `mgo2_cmd_4904_c2s.ksy`.

  Sender entry `0xD4AA44` (the function opens `mfcr r12`; earlier revisions of this file gave
  `0xD4AA48`, the `stdu`, which is one instruction late). Builder call `0xD4AB4C`,
  request-status slot `0x40` (64) completed with state 1 at `0xD4ABC8`.

  **Paired reply: `0x4913`** — slot bijection: the only `slot 64 = 1` site is this sender and
  the only `slot 64 = 2` site is `0xD4B608`, inside the wrapper `0xD4B5D0`, which passes the
  expected id `0x4913` (`li r4,18707` at `0xD4B5D8`) to the shared 680-byte team-record parser
  `0xD4AF34`. So a successful `0x4912` is answered with **the full team record** — result,
  team id, tag, comment, flags and the eight member slots.

  **This is "join a team you are not already in".** The sender's only state gate is
  `0xD4908C(session) == -1` → return **-1004** (`0xD4AAF8`–`0xD4AB04`). `0xD4908C` returns -1
  exactly when `*(session+0xD928)` — the team record's leading team id — is non-zero, i.e. when
  you are already in a team. Every other sender in this batch gates the opposite way.

  **What triggers the send.** One caller: `0x8C9A54`, in the TEAM SELECT screen module (disc
  string 640 "TEAM SELECT", 665 "Password Lock"). It works from the *browsed* team object
  returned by `0xD491C8` (`*(session+0x11904) + 0x20000 - 23144`), not from your own team
  record, and branches on **bit 7 of that record's flags word at `+0x94`**
  (`rldicl. r11,r0,57,63` at `0x8C9A00`):
    * bit set → pass the 16-byte buffer the on-screen keyboard filled (`0x87EB50` at `0x8C9988`,
      min length 3 in `128(r1)`, max length 16 in r6);
    * bit clear → pass NULL, which the sender turns into 16 zero bytes.
  Either way `r4 = *(browsedTeam+0x00)` — the team id.

  **Cross-packet, by struct-offset bijection.** `mgo2_cmd_4913_s2c.ksy` reads a one-byte `flags`
  field and expands wire bit 0 → `0x80`, bit 1 → `0x40`, bit 2 → `0x10` of the u32 at
  `record+0x94`. Bit 7 of that word is therefore **`0x4913` flags wire bit 0**, and this caller
  proves it is the **password-lock** bit. (Its sibling, `0x40` = wire bit 1, is the clan
  affiliation bit — see `mgo2_cmd_4923_c2s.ksy`.) These are the same struct bytes, not similar
  names.

  Argument validation, when a password is supplied: `strlen` (`0xDCC7F8`) must be **3..16**
  (`ble` at `0xD4AAA8` rejects ≤ 2, `bgt` at `0xD4AAB0` rejects > 16), and `0xD32DD0` must
  return non-zero. `0xD32DD0` walks the string and returns 0 the moment it meets a byte in
  **1..31** (`addi r0,r9,-1` then `cmplwi cr6,r0,30`), -1 at the NUL — i.e. it is a
  **control-character rejection**, not a charset whitelist. All three failures return -24 without
  sending.

  The sender zeroes a 17-byte stack buffer (`vxor`/`stvx` + `stb 0,16` at `0xD4AB0C`–`0xD4AB1C`),
  `strcpy`s the argument into it when non-NULL, then writes the first 16 bytes: a NULL argument
  sends 16 zero bytes rather than omitting the field. Post-finalise `0xD5D124` retain call, no
  wire effect. Total payload: 20 bytes.

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
      [ELF — CERTAIN] `0xD5C9BC` at `0xD4AB5C`, source = sender arg r4 (spilled `1480(r1)`).
      The caller loads it from `*(browsedTeam+0x00)` at `0x8C9A20` / `0x8C9A4C`, and
      `browsedTeam+0x00` is the same field `mgo2_cmd_4913_s2c.ksy` calls `clan_id` — the record's
      own identity, which every team-event notification's header word is compared against
      (helper `0xD49230`). Same struct byte, so this is the **team id to join**.
  - id: password
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [ELF — CERTAIN that it is the password; the encoding tag is inherited, not re-derived]
      Raw 16-byte block (`0xD5D0AC` r5=16 at `0xD4AB70`) copied from a zero-filled 17-byte stack
      buffer.

      The caller only supplies it when the target team's flags bit `0x80` at `record+0x94` is
      set — the bit the TEAM SELECT screen labels with disc string 665, **"Password Lock"** — and
      fills it from the on-screen keyboard at `0x87EB50` with min length 3, max length 16.
      **All 16 bytes are zero when the team is not locked**; the field is never omitted, so the
      payload is always 20 bytes.

      Server-side rule readable from the client: it accepts 3..16 bytes containing no byte in
      1..31 (`0xD32DD0`). Whether the wire value is the literal password or a transform of it is
      [UNKNOWN] — the sender applies none, so on this side it is literal.
