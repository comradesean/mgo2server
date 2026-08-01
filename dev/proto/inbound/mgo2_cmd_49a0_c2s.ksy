meta:
  id: mgo2_cmd_49a0_c2s
  title: "MGO2 0x49a0 — one clan-record setting byte (field 0x260), sent while clanless (client -> server)"
  endian: be
doc: |
  **CORRECTED 2026-08-01 — this file says "clan" where the evidence says "team".** An
  adjudication pass settled that `session + 0xD928` is the **team record**, not a my-clan cache,
  and that the 680-byte object here is a team. Read every "clan" below as "team", except where it
  names the *clan affiliation* bit (`team+0x94` bit `0x40`), which genuinely is a reference to a
  separate clan object.

  The mechanics recorded below are correct and were not changed; only the noun was wrong. The
  cause was that one struct type has **two instances** — `session+0xD928` is my team, and
  `[session+0x11904]+0x1A598` is the team being viewed or joined — both filled by the same
  id-dispatched parser `0xD4AF34`. Two instances of one type look exactly like two types.

  The noun is settled by three tier-1 lines: that shared parser; the gate `0xD4908C` failing with
  **-1007**, which the UI maps to dialog 5170 *"You have already left the team."*; and the error
  bands, which are **-10xx** for this object and a disjoint **-12xx** for real clan operations.

  **Scope: this makes the family Ver. 1.10 / 1.20 team-tournament-survival content, out of scope
  for v1.** In particular `0x49C2`/`0x49C3` are **join team**, and are NOT implementable now --
  reversing the earlier note that they were the batch's one ready-to-ship pair.

  Full write-up: `dev/docs/FIELD_MAPPING.md`, "Settled 2026-08-01".

  Sender `0xD4A1F8`, builder call `0xD4A298`, wait slot `73` (`li r4,73` at `0xD4A2D0`,
  `0xD32E08(session, 73, 1)` at `0xD4A2E8`). Total payload: 1 byte.

  **Pairs with `0x49A1`, by wait slot.** `0x49A1`'s parser `0xD4B560` closes slot 73
  (`0xD32E08(...,73,2)` at `0xD4B598`); nothing else touches slot 73. The reply is
  **mandatory**. `0x49A1` runs through the shared clan-record parser `0xD4AF34` and, being id
  18849, is routed to the **my-clan** cache at `session + 0xD928` (`0xD4AFC0`-`0xD4AFFC`), not
  to the viewed-clan buffer `0x4985`/`0x49B1` use.

  **Gate: you must not already be in a clan.** `bl 0xD4908C` at `0xD4A264`, error -1004 when it
  returns -1; `0xD4908C` returns -1 exactly when `*(session + 0xD928)` (the my-clan record's id
  field) is non-zero. Same gate as `0x4910`, `0x4986` and `0x49C2`.

  **The argument is a clan record.** r4 is a pointer to a 680-byte struct laid out exactly like
  the record the shared parser `0xD4AF34` builds. The sole caller `0x8C5408` allocates it on the
  stack at `r1+112` inside an 848-byte frame (entry `0x8C5098`, `stdu r1,-848(r1)`) — 112+680 =
  792, so the whole record fits — and fills three fields from a UI object returned by
  `0x883F20`: `obj+656 -> S+604`, `obj+660 -> S+608`, `obj+661 -> S+609`
  (`0x8C53E4`-`0x8C5400`). The sender then **clears** `S+609` and `S+604`
  (`0xD4A280`/`0xD4A284`) and sends only `S+608`, so the other two copies have no wire effect.

  **Wire position of `S+608` in the clan record.** Walking `0xD4AF34` field by field, the
  420-byte clan-record payload is: `+0` result s4, `+4` id u4, `+8` u2 (struct `+668`), `+10`
  u1 (struct `+4`), `+11` name[16], `+27` text[128], `+155` flags u1, then eight 25-byte slots
  (200 bytes), then struct `+604` at wire `+356`... precisely: struct `+604` u4 is at wire 356,
  and **struct `+608` u1 is at wire 360**, which is `unknown_0x260` in
  `../outbound/mgo2_cmd_49b1_s2c.ksy`. `0x4910` (create clan) sends the same struct byte as its
  `unknown_a1` (`0xD4AE44`). So this byte is one clan-record setting, writable at creation time
  via `0x4910` and separately via this command.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-08-01.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
seq:
  - id: clan_field_0x260
    type: u1
    doc: |
      [ELF for the identity, UNKNOWN for the semantics] `0xD5C8A0` (u1) at `0xD4A2AC`, from
      `S+608` (`0x260`).
      Bijection, proven: this is the same struct byte that the shared clan-record parser
      `0xD4AF34` fills at `0xD4B304`-`0xD4B310` (wire offset 360 of the 420-byte record,
      `unknown_0x260` in `mgo2_cmd_49b1_s2c.ksy`) and the same byte `0x4910` sends as
      `unknown_a1` (`0xD4AE44`). Three commands therefore address one field.
      **What the field means is [UNKNOWN].** Swept the entire sender `0xD4A1F8`-`0xD4A320` and
      the caller `0x8C5098`-`0x8C5440`: no comparison, no mask, no range check is applied to it
      anywhere on the send path — it is copied from the UI object and written straight out. Its
      only neighbours in the record (`+604` u4, `+609` u1, `+610` u2, `+612` u2) are equally
      unnamed. Do not guess an enum; the client will send whatever the UI put there.
