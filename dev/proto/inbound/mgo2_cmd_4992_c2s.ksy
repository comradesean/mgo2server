meta:
  id: mgo2_cmd_4992_c2s
  title: "MGO2 0x4992 — withdraw/cancel one 0x4991 entry by its key (client -> server)"
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

  Sender `0xD47938`, builder call `0xD479AC`, wait slot `71` (`li r4,71` at `0xD479E0`,
  `0xD32E08(session, 71, 1)` at `0xD479F8`). Total payload: 4 bytes.

  **Pairs with `0x4993`, by wait slot.** `0x4993`'s parser `0xD48B98` closes slot 71
  (`0xD32E08(...,71,2)` at `0xD48CC4`, result setter at `0xD48CD8`); nothing else in the image
  touches slot 71. The reply is **mandatory**.

  **What the reply does with this field — the bijection.** `0xD48B98` reads a result u32, and
  when the result is 0 reads a **second u32** (`0xD48C3C`). It then walks the four-record,
  72-byte table at `ctx + 0x1DAA8` (`ctx = *(session + 0x11904)`; loop `0xD48C70`-`0xD48CB0`,
  bound 216 = 3*72) and **`memset`s to zero the record whose field `+0` equals that u32**
  (`0xD48C98`, `0xDD36F8`). That table is the one the **`0x4991`** parser `0xD48D40` fills, and
  record field `+0` is `0x4991`'s leading u32 (wire offset 0, `0xD48E54`). So `0x4992` is a
  *remove this entry* request keyed on `0x4991`'s record key, and `0x4993` must echo the key
  back or the client removes nothing.

  Contrast `0x4986`, which acts on the **same records but a different field** (struct `+40`,
  wire offset 30).

  This sender does **not** call `0xD4908C`, so unlike `0x4986`/`0x49A0`/`0x49C2` it is legal
  whether or not you are in a clan.

  Note this one is **not** in the Blowfish set even though its sibling `0x4990` is
  (PROTOCOL.md DECRYPT_COMMANDS lists `0x3003`, `0x4310`, `0x4320`, `0x43C0`, `0x4700`, `0x4990`).

  **Not reachable from any call site in this image.** Whole-image sweep of the 4.26M-line
  disassembly for `bl 0xd47938` / `b 0xd47938` (both branch forms, so tail calls count):
  zero hits. Control: the same sweep for `0xd4a578` (the `0x4984` sender) returns four call
  sites, so the sweep works. The function descriptor at `0x1029900` also has no data
  reference — but that test is **uninformative on its own**, because the control's descriptor
  at `0x1029B20` has zero data references too while its function is demonstrably called. A
  computed call through a table this sweep cannot see remains possible; what is established is
  that no *direct* branch reaches it.

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
  - id: entry_key
    type: u4
    doc: |
      [ELF, high confidence] `0xD5C9BC` (u4) at `0xD479BC`, source = sender arg r4.
      The key of the `0x4991` record to withdraw: the same value as that record's field `+0`
      (struct and wire offset 0). Proven by what the paired reply does — `0x4993`'s parser
      matches its own echoed u32 against record `+0` and zeroes the record (`0xD48C88`,
      `0xD48C98`). The request field itself is unconstrained by the sender (no zero check, no
      range check), so the identification rests on the pairing, which the wait slot makes
      exact.
      What the key *denotes* is [UNKNOWN] beyond "a `0x4991` record"; see `0x4986` for the
      reading of that table as pending clan applications, which is inference.
