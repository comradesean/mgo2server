meta:
  id: mgo2_cmd_43f0_s2c
  title: "MGO2 0x43f0 — server -> client: in-match subsystem push (UNSOLICITED, no result field)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43F0` at `0xD38A28` -> stub `0xD39D5C` ->
  parser **`0xD5B868`**.

  **Not a reply.** Like `0x43E4`, this parser has **no result field** — its first read is a
  plain u32 that goes straight into a record — and it completes no request slot: it ends with
  `0xD33CD8(ctx, 43, 0)`, the event/notification helper, with a literal zero value. So the
  server may push it unprompted. Note also the id parity: `0x43F0` is *even*, and every
  even id in this range is a client→server command elsewhere in the protocol; here the even
  number is on the server→client side, which is itself a signal that the `0x43Fx` block is a
  push channel rather than a request/reply family.

  Sequence: verify `hdr.command == 0x43F0` (else `-70`); `0xD3F7B0(ctx)` obtains a record `R`
  (same accessor `0x43F1` uses); `0xD5C844` open; the reads below; `0xD418C0(ctx)` (an
  unidentified side effect, called *before* the fields are committed); the five scalars are
  stored to `R+4`, `R+8`, `R+9`, `R+12`, `R+16`; then two eight-element u32 loops read directly
  into `R+44+4i` and `R+100+4i`; `0xD5C858` close; `0xD33CD8(ctx, 43, 0)`.

  **78 bytes (`0x4E`).** COMMANDS.md files this in "`0x43e*`/`0x43f*` — an in-match subsystem
  the client sends `0x43e0`/`0x43e2` into", and there is no `0x43F0`-shaped request in the
  send-side scan, consistent with it being a push. Every meaning below is [UNKNOWN]; the two
  8-wide u32 arrays are the only structural hint (eight of something — teams? rounds?
  scoreboard slots?). We never send it, so nothing is at risk; this file records the shape.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

doc-ref: dev/docs/COMMANDS.md ("0x43e*/0x43f* — an in-match subsystem")
seq:
  - id: unknown_00
    type: u4
    doc: "[UNKNOWN] wire 0x00 -> `R+4`. Read first, stored first. In the sibling `0x43F1` the *first* u32 is a room/game key checked against the client's current game and passed as the event value; here the first u32 is stored as a field instead, so the two are not the same word."
  - id: unknown_04
    type: u1
    doc: "[UNKNOWN] wire 0x04 -> `R+8`."
  - id: unknown_05
    type: u1
    doc: "[UNKNOWN] wire 0x05 -> `R+9`."
  - id: unknown_06
    type: u4
    doc: "[UNKNOWN] wire 0x06 -> `R+12`. Unaligned on the wire; the primitives read bytewise so alignment is irrelevant."
  - id: unknown_0a
    type: u4
    doc: "[UNKNOWN] wire 0x0a -> `R+16`."
  - id: unknown_array_a
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: "[UNKNOWN] wire 0x0e..0x2d -> `R+44+4i`. Eight u32s, read in an `i < 8` loop straight into the record."
  - id: unknown_array_b
    type: u4
    repeat: expr
    repeat-expr: 8
    doc: "[UNKNOWN] wire 0x2e..0x4d -> `R+100+4i`. Eight more. **Last read: 78 bytes total.** The 28-byte gap between the two arrays in the record (`R+76`..`R+99`) is not filled from this packet."
