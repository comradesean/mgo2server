meta:
  id: mgo2_cmd_4986_c2s
  title: "MGO2 0x4986 — act on a pending clan application/invitation (one u4 id) (client -> server)"
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

  Sender `0xD4A90C`, builder call `0xD4A994`, wait slot `72` (`li r4,72` at `0xD4A9C8`,
  `0xD32E08(session, 72, 1)` at `0xD4A9E0`). Total payload: 4 bytes.

  **Pairs with `0x4987`, by wait slot.** `0x4987`'s parser `0xD4D770` closes slot 72
  (`0xD32E08(...,72,2)` at `0xD4D834`, result setter at `0xD4D848`), and no other command in
  the image touches slot 72. The reply is therefore **mandatory**; without it slot 72 stays at
  state 1 and the screen stalls.

  The sender also **resets slot 86 to state 0** immediately after arming slot 72
  (`li r4,86` / `li r5,0` / `bl 0xD32E08` at `0xD4A9EC`-`0xD4A9F4`). Slot 86 is a follow-up
  slot: if the `0x4987` reply carries a non-zero word at clan-record offset `+664`,
  `0xD4D770` arms slot 86 (state 1) *instead of* completing slot 72
  (`lwz r29,664(r28)` / `0xD32E08(...,86,1)` at `0xD4D804`-`0xD4D81C`). A `0x4987` whose `+664`
  is non-zero therefore commits the client to a second exchange; serve `+664 == 0` unless that
  second exchange is implemented too.

  **Gate: you must not already be in a clan.** `bl 0xD4908C` at `0xD4A96C`; the sender returns
  -1004 when it yields -1. `0xD4908C` (`0xD4908C`-`0xD490B4`) returns -1 exactly when
  `*(session + 0xD928)` — field `+0`, the id, of the **my-clan** cache — is non-zero. The same
  gate guards `0x4910`, `0x49A0` and `0x49C2`.

  **Where the id comes from.** Sole caller `0x893738`; `lwz r4,-9068(r9)` at `0x893734` reads a
  UI global loaded once, at `0x893310`, from `record[0] + 40` of the four-record 72-byte table
  at `ctx + 0x1DAA8` (`ctx = *(session + 0x11904)`) — the table the **`0x4991`** parser
  `0xD48D40` fills and the **`0x4993`** parser `0xD48B98` deletes from. Struct `+40` is wire
  offset **30** of a `0x4991` record (`0xD48EF8`): the second u32, the one that follows the
  first 16-byte name. The caller refuses to send when `record[0] + 0` is zero
  (`0x8932F8`-`0x893300`).

  Note the split with `0x4992`: **both act on the same `0x4991` record but on different
  fields** — `0x4992` carries the record's own key (struct `+0`, wire 0), `0x4986` carries the
  second id at struct `+40` (wire 30). Given that `0x4987` populates the *my-clan* cache and
  that the command is only legal while you have no clan, the natural reading is that
  `0x4991`'s records are pending clan applications/invitations, `+0` identifying the
  application and `+40` the clan. That last sentence is inference; the field addressing above
  is not.

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
  - id: entry_ref_id
    type: u4
    doc: |
      [ELF for the source, INFERRED for the name] `0xD5C9BC` (u4) at `0xD4A9A4`, source =
      sender arg r4.
      Exactly the u32 at **struct offset `+40` / wire offset 30 of the first `0x4991` record**
      (loaded at `0x893310`, written by the `0x4991` parser at `0xD48EF8`).
      It is *not* echo-checked the way `0x4984`/`0x49B0` are: `0xD4AF34` routes `0x4987` down
      the `0xD4B108` branch, which clears the my-clan cache (`0xD49368`) and reads the record's
      `+0` straight from the wire with no comparison against the request. So the server may
      answer with any clan record, and nothing in the client proves the request id and the
      reply's `+0` are the same value.
      Reading it as the clan id of a pending application is inference from the surrounding flow
      (no-clan gate, my-clan reply, second id field in the record). What is proven is the
      source field only. No sender-side range check; any u32 is sent.
