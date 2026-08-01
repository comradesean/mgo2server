meta:
  id: mgo2_cmd_49c3_s2c
  title: "MGO2 0x49C3 — reply to 0x49C2: result + entry id + new state (server -> client)"
  endian: be
doc: |
  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39840,
  parser 0xD4DE50. Nothing in dev/docs/PROTOCOL.md or dev/docs/OBSERVED.md describes 0x49C3 and
  it has never been observed live; everything below is read out of the client parser.

  **This is the reply to 0x49C2, established by the wait slot rather than by id adjacency.**
  `0xD32E08` is the request-state setter (`session[360 + 4*slot] = state`, slot <= 116,
  state <= 2, 0xD32E08-0xD32E38) and `0xD32E70` the matching result setter
  (`session[824 + 4*slot] = result`). The 0x49C2 sender arms slot **76** (0xD4E104); this
  parser sets slot 76 to state 2 and stores the result (0xD4DFBC, 0xD4DFD0). No third function
  in the image touches slot 76. So 0x49C2 without a 0x49C3 is a guaranteed stall.

  **The table it updates.** Three entries of 44 bytes at `session + 0x117F8`, filled by the
  **0x49C1** parser 0xD4E138 (record writes at 0xD4E2EC-0xD4E32C): `+0` u32 key, `+4` u32
  ordering value (0x49C1 evicts the entry with the largest `+4`, 0xD4E2B0-0xD4E2C0), `+8` u16,
  `+12` u32 state, `+16` u8, `+24` 17 raw bytes (16-byte name plus NUL). 0x49C1 raises client
  event 51 or 52 via `0xD33CD8(ctx, ev, key)` according to its own state byte (0xD4E374).
  A second, parallel three-entry table at `session + 0x1187C` belongs to the outbound 0x49C0
  path (0xD4E68C).

  **Two behaviours, chosen by the result.** All three fields are read *before* the result is
  tested (0xD4DEB0, 0xD4DEC8, 0xD4DEE0), so **every field is always present on the wire, even
  on failure** — do not truncate an error reply.
  - `result == 0` (0xD4DF14 falls through): loop 0xD4DF20-0xD4DF5C over the three entries. Any
    entry with `+0 == 0` is skipped as empty; the entry whose `+0` equals `entry_id` gets
    `+12 = new_state`; **every other non-empty entry gets `+12 = 4`** (`li r8,4` at 0xD4DF1C,
    `stw r8,12(r9)` at 0xD4DF4C). Answering one notification therefore rewrites the other two.
  - `result != 0` (branch to 0xD4DF60): loop 0xD4DF60-0xD4DFA8 **`memset`s the matching 44-byte
    entry to zero** (0xD4DF94, `0xDD36F8`), i.e. removes it. `new_state` is ignored on this
    path.
  Both loops compare the pre-increment counter against 88 (= 2*44) and then step, so exactly
  three entries are visited.

  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE34 delimiter-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  ADDRESS AND SEMANTICS CORRECTION (2026-07-26, read out of the primitive itself): the string
  reader's entry point is **0xD5CE34**, not 0xD5CE3C — the previous function's `blr` is at
  0xD5CE30 and 0xD5CE3C is two instructions into the body. It is **not** a NUL-terminated
  string reader: the loop compares each byte against **r5, a caller-supplied delimiter**
  (`cmpw cr7,r0,r5` at 0xD5CE78); NUL is only a secondary stop (`cmpwi cr6,r0,0` at 0xD5CE7C).
  Callers that pass r5 = 0 get NUL termination as a special case. Either way the cursor is
  advanced **past** the terminator (`addi r9,r9,1` at 0xD5CEA4 after `stw r11` at 0xD5CE94), so
  the field consumes **len + 1** wire bytes, and the client writes its own NUL at dest+len
  (0xD5CE9C).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: result
    type: u4
    doc: |
      [ELF, conclusive] Read at 0xD4DEB0 into r1+120.
      **This is a RESULT CODE, not a count.** Two independent proofs, per the rule that cost
      this project the 1032:00000005 bug:
      (a) it is loaded **sign-extended** and passed straight to the result setter —
      `lwa r5,120(r1)` at 0xD4DFCC feeding `0xD32E70(session, 76, r5)` at 0xD4DFD0, the same
      function every other reply in this family uses for its error code;
      (b) it is branched on as a two-way success/failure discriminator at 0xD4DF10-0xD4DF14,
      selecting "set state" versus "delete the entry" — a count would not be tested `!= 0` and
      then discarded.
      The previous revision of this file described this field as the match key against slot+0;
      that was wrong — the key is the *next* field. Correcting the doc only: the declared width
      stays u4 because that is what 0xD5CC64 reads, but the client's own use of it is signed,
      so negative error codes are transported correctly. (The sibling files on the shared clan
      parser declare their equivalent field `s4`; the divergence is noted, not silently
      resolved here.)
  - id: entry_id
    type: u4
    doc: |
      [ELF, conclusive] Read at 0xD4DEC8 into r1+116. The **match key**: compared against `+0`
      of each of the three 44-byte entries at `session + 0x117F8` (0xD4DF34/0xD4DF38 on the
      success path, 0xD4DF74/0xD4DF80 on the failure path).
      Must echo the `entry_id` the client sent in 0x49C2 — a value that does not match any live
      entry makes the success path set every entry's state to 4 and the failure path do nothing
      at all, in both cases silently.
  - id: new_state
    type: u1
    doc: |
      [ELF for the effect, INFERRED for the name] Read at 0xD4DEE0 into r1+112. Last byte of
      the payload.
      On success it is written as a full word into the matched entry's `+12`
      (0xD4DF40/0xD4DF44) — the same field 0x49C1 initialises (0xD4E328) and tests against 1 to
      choose event 51 vs 52 (0xD4E374). On the failure path it is read but unused.
      It shares the 1..4 space of 0x49C2's `answer` byte; the natural service is to echo what
      the client asked for. Which value means what is [UNKNOWN]: 1 is 0x49C1's "freshly
      arrived" state, and 4 is what this parser forces onto the *other* entries, so 4 reads as
      "superseded". No enum is declared on that.
