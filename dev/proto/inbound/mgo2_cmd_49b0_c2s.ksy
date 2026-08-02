meta:
  id: mgo2_cmd_49b0_c2s
  title: "MGO2 0x49b0 — fetch a clan record by clan id, with a second selector (client -> server)"
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

  Sender `0xD4A458`, builder call `0xD4A4D0`, wait slot `74` (`li r4,74` at `0xD4A51C`,
  `0xD32E08(session, 74, 1)` at `0xD4A54C`). Arguments r4 (`stw 1416(r1)`) and r5
  (`stw 1424(r1)`), written in argument order. Total payload: 8 bytes.

  **Pairs with `0x49B1`, by wait slot.** `0x49B1`'s parser `0xD4B640` closes slot 74
  (`0xD32E08(...,74,2)` at `0xD4B678`); nothing else touches slot 74. The reply is
  **mandatory**. `0x49B1` is id 18865 in the shared clan-record parser `0xD4AF34`, which routes
  it — together with `0x4985` — to the **viewed-clan** buffer at `ctx + 0x1A598`
  (`ctx = *(session + 0x11904)`; `0xD4AFC8`/`0xD4AFDC`-`0xD4AFEC`), not to the my-clan cache.
  `0xD4AF34` also refuses the reply unless slot 74 reads state 1 at the time
  (`0xD32E3C` at `0xD4B04C`, `cmpwi r3,1` at `0xD4B054`) — unsolicited `0x49B1` is dropped.

  **Field 0 is echo-checked.** Exactly like `0x4984`, the sender stashes its *first* argument
  at `ctx + 0x26CFC` (`lwz r0,1416(r1)` / `stw r0,27900(r9)` at `0xD4A544`/`0xD4A548`), and
  `0xD4AF34` compares `0x49B1`'s leading record id against that same word, abandoning the reply
  on mismatch (`0xD4B0D8`-`0xD4B0E0`). The **second** argument is not stashed and not checked.

  This sender does **not** call `0xD4908C`, so it is legal whether or not you are in a clan —
  same as `0x4984`, and consistent with reading somebody else's clan.

  **Not reachable from any call site in this image.** Whole-image sweep of the 4.26M-line
  disassembly for `bl 0xd4a458` / `b 0xd4a458` (both branch forms, so tail calls count): zero
  hits. Control: the same sweep for `0xd4a578` (the `0x4984` sender) returns four call sites,
  so the sweep works. The function descriptor at `0x1029B18` has no data reference either, but
  that test proves nothing on its own — the control's descriptor at `0x1029B20` also has zero
  data references while its function is demonstrably called. A computed call through a table
  remains possible; what is established is that no *direct* branch reaches it. Consequence for
  us: the meaning of the second field cannot be recovered from a caller, because there is none.

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
      [ELF, high confidence] `0xD5C9BC` (u4) at `0xD4A4E0`, source = sender arg r4.
      The id of the **team** record being fetched, and the value the reply must echo: the sender
      writes it to `ctx+0x26CFC` (`0xD4A548`) and `0xD4AF34` rejects `0x49B1` unless the
      record's own `+0` matches (`0xD4B0D8`). Same slot, same test and therefore the same id
      space as `0x4984`/`0x4985`. No range check; any u32 is sent, including 0.
  - id: unknown_04
    type: u4
    doc: |
      [ELF for position and width, meaning UNRESOLVED] `0xD5C9BC` (u4) at `0xD4A4F0`, source =
      sender arg r5.
      Stated negative: swept the whole sender body `0xD4A458`-`0xD4A574` — this word is spilled
      at `0xD4A484` and read back exactly once, at `0xD4A4E8`, to be serialised. It is never
      compared, masked, bounded or stored into the session or the game context, so the sender
      constrains it in no way. Swept the whole image for callers (see above): there are none,
      so there is no argument site to read it from either. Both edges of that sweep are the
      ends of the function and the ends of the disassembly respectively; the control for the
      caller sweep is `0xd4a578`, which yields four hits.
      It is a second selector on a clan-record fetch — page, member index, section, revision are
      all consistent with an 8-byte "id + qualifier" request and nothing in the image
      distinguishes them. Open question, deliberately not guessed.
