meta:
  id: mgo2_cmd_43c9_s2c
  title: "MGO2 0x43c9 — server -> client: start-round reply (reply to 0x43c8)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43C9` at `0xD38A40` -> stub `0xD39300` ->
  parser **`0xD3FEAC`**. Request-status slot **49**.

  This is the reply of the pair PROTOCOL.md renumbered on 2026-07-23: the client's real
  start-round command is `0x43c8` (builder `0xD40CB4`, payload `{u32, u8}`), **not** `0x43ca`,
  which has no builder anywhere and is never sent; our handler and reply were bound to
  `0x43ca`/`0x43cb`, which the client has no parser for.

  Layout — and the ELF settles a claim PROTOCOL.md makes elsewhere:

  1. verify `hdr.command == 0x43C9` (else `-70`); zero a stack slot;
  2. `0xD5C844` open; `0xD5CC64` u32 -> `result`;
  3. **only if `result == 0`**, `0xD5CCD8` u32 -> `token`; and **only if `token != 0`**, call
     `0xD3A094(ctx)` and store the token at `+13048` of what it returns — i.e. `0x32F8` of the
     session sub-object, the exact location PROTOCOL.md's `0x4390` section names
     (`session+0x57d8+0x32f8`) as the one place the start-round token lives;
  4. `0xD5C858` close; `0xD32E08(ctx, 49, 2)`, `0xD32E70(ctx, 49, result)`.

  PROTOCOL.md's reporting-model argument — that round reports carry no game identifier because
  the token is *written once and read once*, into a UI record, never into a packet builder —
  depends on this being the only writer of `+0x32F8`. This parser is that writer, and it is
  conditional on both `result == 0` and `token != 0`, so a server that replies `{0, 0}` leaves
  the slot untouched. **8 bytes on success; 4 bytes on failure is well-formed** (the second
  read is skipped when `result != 0`, unlike `0x4317`).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "0x43ca — start round (never observed)"; "0x4390 — update stats"
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD3FF18] wire 0x00. 0 = round started. Nonzero ends the payload — nothing further is read."
  - id: token
    type: u4
    doc: |
      [ELF 0xD3FF40] wire 0x04, present only when `result == 0`. The round token. Stored at
      session sub-object `+0x32F8` **only if nonzero**; read exactly once elsewhere in the
      binary, into a local UI record via memory-copy helpers, never by a packet writer. It is
      therefore **not** a correlation id the server can expect back: `0x43c8`, `0x43a2` and
      `0x4390` all reference none of the token storage. [UNKNOWN: what the UI record does with it.]
