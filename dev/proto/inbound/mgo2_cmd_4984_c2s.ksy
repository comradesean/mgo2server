meta:
  id: mgo2_cmd_4984_c2s
  title: "MGO2 0x4984 — fetch one clan's record by clan id (client -> server)"
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

  Sender `0xD4A578`, builder call `0xD4A5EC`, wait slot `63` (`li r4,63` at `0xD4A628`,
  `0xD32E08(session, 63, 1)` at `0xD4A658`). Total payload: 4 bytes.

  **Request/reply pair, proven by the wait slot, not by id adjacency.** `0xD32E08` is the
  request-state setter: `session[360 + 4*slot] = state`, `slot <= 116`, `state <= 2`
  (`0xD32E08`-`0xD32E38`); `0xD32E70` is the matching result setter
  (`session[824 + 4*slot] = result`). This sender sets slot 63 to state 1 (outstanding);
  the parser for **`0x4985`** (`0xD4B6B0`) sets slot 63 to state 2 and writes the result
  (`0xD4B6E8` / `0xD4B6FC`). So `0x4984` -> `0x4985`, and **the reply is mandatory** — an
  unanswered `0x4984` leaves slot 63 at state 1, which is the FFFFFF60 stall CLAUDE.md
  describes.

  **The clan-id echo is enforced.** Before returning, the sender stashes the u32 it just sent
  at `ctx + 0x26CFC`, where `ctx = *(session + 0x11904)`
  (`lwz r0,6404(r11)` / `stw r0,27900(r9)` at `0xD4A63C`-`0xD4A654`). The shared clan-record
  parser `0xD4AF34` reads the reply's first u32 and **compares it against that same word**
  (`lwz r9,27900(r9)` / `cmpw` / `bne` at `0xD4B0D8`-`0xD4B0E0`), abandoning the whole reply on
  mismatch. That is a struct-offset bijection: this request's field 0 and `0x4985`'s field 0
  are the same value. `0x49B0` writes the identical slot (`0xD4A548`) and `0x49B1` is checked
  the same way, so `0x4984`, `0x49B0`, `0x4985` and `0x49B1` share one id space.

  `0xD4AF34` additionally refuses `0x4985` unless slot 63 currently reads state 1
  (`0xD32E3C` getter at `0xD4B04C`, `cmpwi r3,1` at `0xD4B054`) — unsolicited `0x4985` is
  dropped.

  **Where the client gets the id.** Three independent callers, each passing the first u32 of a
  list record:
  - `0x8C964C` and `0x8C974C` — index accessor `0xD4915C` over the 56-byte-record list at
    `ctx + 0x1C4C0` (header `+0` open marker, `+4` count; records at `+8 + 56*n`). That list is
    filled by the **`0x4982`** parser `0xD4B790` and opened/closed by `0x4981`/`0x4983`
    (wait slot 62). `lwz r4,0(r9)` at `0x8C9648` / `0x8C9748` takes record field 0.
  - `0x8FE3A0` — a 52-byte-record UI table, element `+12`, first u32.
  - `0x931690` — accessor `0xD5A8B4`, another 52-byte-record list, first u32.

  Unlike `0x4986`, `0x49A0` and `0x49C2`, this sender does **not** gate on `0xD4908C`, so it is
  legal whether or not you are in a clan — consistent with "look at somebody else's clan":
  `0xD4AF34` routes `0x4985` to the *viewed-clan* buffer at `ctx + 0x1A598`, not to the my-clan
  cache at `session + 0xD928`.

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
  - id: team_id
    type: u4
    doc: |
      [ELF, high confidence] `0xD5C9BC` (u4) at `0xD4A5FC`, source = sender arg r4.
      The id of the **team** record being fetched. Proof chain, all tier 1:
      (a) the sender stashes this exact word at `ctx+0x26CFC` (`0xD4A654`) and the reply parser
      rejects `0x4985` unless its own leading u32 equals it (`0xD4B0D8`), so the request field
      and the record's identity field are the same value;
      (b) the reply is written into the 680-byte clan-record layout at `ctx+0x1A598` by the
      shared parser `0xD4AF34`, whose field `+0` is that record id;
      (c) all three call sites pass field 0 of a clan-list record — the `0x4982` list at
      `ctx+0x1C4C0` plus two 52-byte UI lists.
      The word "clan" comes from the family reading (`0x4910`..`0x49B1` all drive the same
      680-byte record and `0x4B49` calls that object's picture a clan emblem); the *identity*
      claim — that this field keys that record — is proven independently of the naming.
      No sender-side range check: any u32 is sent, including 0.
