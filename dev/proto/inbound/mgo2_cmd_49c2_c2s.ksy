meta:
  id: mgo2_cmd_49c2_c2s
  title: "MGO2 0x49c2 — answer one pending 0x49C1 invitation: entry id + state 1..4 (client -> server)"
  endian: be
doc: |
  5-byte payload: a u32 followed by a u8.

  Evidence (ELF, retail BLUS30109): sender 0xD4E008, signature (session, u32 a, u8 b).
  Prologue spills `stw r4,1416(r1)` and `stb r5,1424(r1)`. Builder `bl 0xD5CF40` at
  0xD4E0A8 (`li r4,0x49c2` at 0xD4E0A4), then
  `bl 0xD5C9BC` at 0xD4E0B8 (unsigned u32, 4 bytes MSB first, from 1416) and
  `bl 0xD5C8A0` at 0xD4E0C8 (u8, from 1424),
  then the seal `bl 0xD5C828` at 0xD4E0D4 and the flush `bl 0xD34CC0` at 0xD4E0E4.

  **0x49C2 and 0x49C3 ARE a pair, and now for a reason better than adjacency.** The sender arms
  wait slot **76** on a successful flush (`0xD32E08(session, 76, 1)` at 0xD4E104), and the
  0x49C3 parser 0xD4DE50 is the only other function in the image that touches slot 76 — it sets
  state 2 and writes the result (0xD4DFBC / 0xD4DFD0). `0xD32E08` is the request-state setter
  (`session[360 + 4*slot] = state`, slot <= 116, state <= 2, 0xD32E08-0xD32E38). So **the reply
  is mandatory**: without a 0x49C3 the slot stays at state 1 and the screen stalls with
  FFFFFF60. The previous note in this file called the pairing "inference from id adjacency";
  it is now read from the slot machinery.

  **What the pair operates on.** 0x49C3's parser walks a **three-entry, 44-byte table at
  `session + 0x117F8`** (loop 0xD4DF20-0xD4DF5C, stride 44, bound 88 = 2*44), matching entry
  `+0` against the u32 it just read and writing the u8 it just read into entry `+12`. That
  table is filled by the **0x49C1** parser 0xD4E138 (0xD4E2EC-0xD4E32C), which writes per
  record: `+0` u32 key, `+4` u32 (an ordering value — 0x49C1 evicts the entry with the largest
  `+4`, 0xD4E2B0-0xD4E2C0), `+8` u16, `+12` u32 state, `+16` u8, `+24` 17 raw bytes (a 16-byte
  name plus its NUL). 0x49C1 raises client event 51 or 52 through `0xD33CD8(ctx, ev, key)`
  depending on whether its own state byte is 1. A parallel three-entry table sits at
  `session + 0x1187C` and belongs to the outbound `0x49C0` path (0xD4E68C), which is also rate
  limited to one send per 10 seconds off the u32 at `session + 0x11900` (0xD4E670-0xD4E688,
  error -1043).

  So this command **answers one of up to three pending 0x49C1 notifications**, naming it by its
  key and supplying the new state.

  Validation, all returning -24 (0xFFFFFFE8) without sending: session != NULL;
  **a != 0** (`cmpdi cr6,r4,0` at 0xD4E028 — so the u32 is a real identifier, never a
  "none"); and **b in 1..4** (`cmpwi r5,0` rejects 0, `cmplwi r5,4` + `bgt` rejects >4, at
  0xD4E040..0xD4E050).

  **Gate: you must not already be in a clan.** `0xD4908C` must not return -1, else the sender
  bails with -1004 (0xFFFFFC14). Correcting the earlier note in this file: the word `0xD4908C`
  tests is at **`session + 0xD928`**, not `session + 0x6BA8` — `addis r9,r9,1` then
  `lwz r0,-9944(r9)` is `session + 0x10000 - 0x26D8`. That word is field `+0` (the id) of the
  **my-clan** cache, the 680-byte record `0xD49368` clears and `0x4911`/`0x4913`/`0x4987`/
  `0x49A1` fill. So the gate reads "only while you have no clan", and the same gate guards
  `0x4910`, `0x4986` and `0x49A0`.

  **Not reachable from any call site in this image.** Whole-image sweep of the 4.26M-line
  disassembly for `bl 0xd4e008` / `b 0xd4e008` (both branch forms, so tail calls count): zero
  hits. Control: the same sweep for `0xd4a578` (the 0x4984 sender) returns four call sites, so
  the sweep works. The function descriptor at `0x1029C50` has no data reference either, but
  that test is uninformative on its own — the control's descriptor at `0x1029B20` also has zero
  data references while its function is demonstrably called.

  Never observed live; not answered by this server.
seq:
  - id: entry_id
    type: u4
    doc: |
      [ELF, high confidence] Position and width exact (unsigned, 0xD5C9BC). Constrained
      non-zero by the sender (0xD4E028).
      It is the key of a record in the three-entry table at `session + 0x117F8`: the paired
      0x49C3 reply echoes a u32 and matches it against entry `+0` (0xD4DF28/0xD4DF38), and
      those entries are created by 0x49C1 with `+0` taken from its own leading u32
      (0xD4E27C, stored 0xD4E318). Non-zero is exactly right — 0x49C3 skips entries whose `+0`
      is zero, i.e. empty slots.
      What the record *is* remains [UNKNOWN] in the strict sense; the clanless gate plus the
      "three at a time, evict the oldest, raise an event" shape reads as a pending clan
      invitation, and that reading is inference.
  - id: answer
    type: u1
    doc: |
      [ELF for the range, INFERRED for the name] Position and width exact (0xD5C8A0).
      **Range-checked to 1..4** — the client never sends 0 or >4 (0xD4E040-0xD4E050).
      Bijection with the reply: 0x49C3's third field is a u8 written into the matched entry's
      `+12` (0xD4DF40/0xD4DF44), which is the same slot 0x49C1 initialises from its own state
      byte (0xD4E328) and the slot 0x49C1 tests against 1 to choose event 51 vs 52
      (0xD4E374-0xD4E38C). So this byte is a **state value for that entry**, in the same 1..4
      space, i.e. the player's answer to the notification.
      Which value means which answer is [UNKNOWN]. Two facts constrain a future reading and
      neither names a value: 1 is the state 0x49C1 uses for "freshly arrived" (0xD4E268), and
      **4 is what 0x49C3 forces onto every *other* entry in the table when one is answered
      successfully** (`li r8,4` at 0xD4DF1C, `stw r8,12(r9)` at 0xD4DF4C) — so 4 plausibly
      reads as "superseded / withdrawn". No enum is declared on that.
