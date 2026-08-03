meta:
  id: mgo2_cmd_49c0_c2s
  title: "MGO2 0x49C0 — game-lobby request with a counted id list (client -> server)"
  endian: be
doc: |
  **Filename deviates from the `mgo2_cmd_<id>.ksy` rule on purpose: `0x49C0` is bidirectional.**
  The client both SENDS this id (packet builder `0xD5CF40` called with `li r4,18880` at
  `0xD4E6D8`) and PARSES it (dispatcher `0xD38804`: `cmpwi r3,18880` at `0xD38D50` →
  `b 0xD39820` → parser `0xD4E420`). Both facts are tier 1 and were checked directly.
  `mgo2_cmd_49c0.ksy` in this directory holds the **server -> client** (parsed) layout; this file
  holds the **client -> server** (sent) layout. They are different structures and cannot share one
  `.ksy`. The two need reconciling into a naming convention before either is promoted — flagged
  rather than silently resolved.

  Sender: entry `0xD4E5D0` (the function containing `0xD4E610`), builder call `0xD4E6D8`.
  [CORRECTED 2026-08-03] The `li r4,75` at `0xD4E7AC` is not a "subsystem index" — 75 is the
  **wait slot** armed via `0xD32E08(session, 75, 1)`, the same slot space as the 76 that
  `0x49C2` arms; `0x4B` was a coincidence of the decimal value. Slots 59-76 are one contiguous
  bank occupied exclusively by 0x49xx team commands, and 75/76 are its highest — the
  last-added commands of the family. Unhandled by our server (COMMANDS.md lists
  `0x4904`–`0x49C2` as the game-lobby/roster/GHQ gap).

  IDENTIFIED 2026-08-03: **this sends up to three team invitations** (or applications — see
  the open question in `../outbound/mgo2_cmd_49c1_s2c.ksy`). The ids come from 44-byte
  invitation records (the same record type the 0x49C1 inbox/outbox array at `session+0x117F8`
  holds), and the loop mirrors FIVE things into the outbox at `session+0x1187C` per entry —
  not just the 17 name bytes the note below records: `+0` the id, `+4` `time(NULL)`
  (`bl 0xDD21F8`, sc 145), `+8` the caller's u16, **`+12` literal 1**, `+24` the 17 bytes.
  The `+12 = 1` is the load-bearing one — it is what makes a later `0x49C1` with state != 1 a
  status update to a *pending* request. Two guards this file omitted: a 10-second rate limit
  on `session+0x11900` (error **-1043**, `0xD4E67C`-`0xD4E688`) and `0xD3844C(session)` ("GAME
  channel connected") -> **-36**. Notably there is NO team gate here — unlike `0x49C2`'s
  "must not already be in a team" — which is the strongest evidence for the "application"
  reading over "leader invites".

  REACHABILITY [ELF 2026-08-03]: the sender `0xD4E5D0` has **zero call sites** image-wide
  (control: the my-team accessor `0xD491F8` in the same bank has 83), as do the three
  invitation-table accessors and the slot-75/76 result getters. So no value for any argument
  is ever produced in this image, the exchange is unreachable in play, and — tier note —
  everything here is tier-1 only and cannot reach tier 2 on this build. Post-launch, not
  served in v1.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.

  **The only assigned client -> server id with a repeating record.** Arguments: r4 = u8
  (`stb 1464(r1)`), r5 = count (`stw 1472(r1)`), r6 = pointer to an array of **44-byte** records.
  Guards before building (`0xD4E61C`–`0xD4E634`): r5 must be `>= 1` **and `<= 3`**, and r6 must be
  non-NULL; otherwise -24 with nothing sent.

  The count is written **first**, with the signed primitive `0xD5C95C`, and the loop's bound is
  read back from that same stack slot (`lwz r0,1472(r1)`, `cmpw r25,r0`, `blt` at
  `0xD4E75C`–`0xD4E77C`). So the record count is **leading-field-driven, not size-driven** —
  worth stating explicitly because this project has previously mis-read count-vs-size.

  Each iteration writes one u32: the word at offset 0 of the current 44-byte record
  (`0xD5C9BC` at `0xD4E710`; stride `addi r27,r27,44` at `0xD4E744`). A record whose first word is
  **zero aborts the whole send** (`lwz r0,0(r29)`, `beq` to the -24 exit at `0xD4E70C`), so all
  ids are nonzero. The 17 bytes the loop also copies out of `record+24` (`lswi`/`stswi` at
  `0xD4E748`) go into a client-side 44-byte-stride table at `ctx+6292`, **not** onto the wire.

  Total payload: 5 + 4*num_ids bytes, i.e. 9, 13 or 17.
seq:
  - id: num_ids
    type: s4
    doc: |
      [ELF] `0xD5C95C` (**signed** 4-byte primitive) at `0xD4E6E8`, source = sender arg r5.
      Constrained by the sender to 1..3 inclusive. Drives `ids` below (named `num_ids` per the
      Kaitai style guide).
  - id: unknown_04
    type: u1
    doc: |
      [ELF] `0xD5C8A0` at `0xD4E6F8`, source = sender arg r4, spilled at `0xD4E610` and
      written straight to the wire. [UNKNOWN — and terminal on this build, 2026-08-03:] it is
      not validated (the guards check only session, count 1..3, array non-NULL), not mirrored
      into the outbox, and — decisively — **the sender is uncalled: no caller anywhere in the
      image, so no value for it is ever produced**. No evidence to name it from exists in this
      binary; none can.
  - id: ids
    type: u4
    repeat: expr
    repeat-expr: num_ids
    doc: |
      [ELF] One u32 per input record, from `record+0`. Count comes from the leading `num_ids`
      field, not from the payload length. Never zero (a zero aborts the send).
      [2026-08-03] The ids are **invitation entry ids** — `record+0` of the 44-byte invitation
      record type (see `../outbound/mgo2_cmd_49c1_s2c.ksy` for the full layout); the same key
      the `0x49C1` notification and `0x49C2`/`0x49C3` answer flow match on, and the key the
      `0x49C0` reply's per-invitee status pairs come back under.
