meta:
  id: mgo2_cmd_43d1_s2c
  title: "MGO2 0x43d1 — server -> client: training parameters (reply to 0x43d0)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43D1` at `0xD38A48` -> stub `0xD39310` ->
  parser **`0xD3A564`** (PROTOCOL.md cites `0xD3A560`, four bytes into the same prologue).
  Request-status slot **31**.

  **There is no result field.** The parser is a loop of **five `0xD5CC14` u16 reads** into a
  10-byte stack block, copied wholesale (`lswi`/`stswi` 10) to `ctx+0x117EC`, then
  `0xD32E08(ctx, 31, 2)` and `0xD32E70(ctx, 31, **0**)` — the result is the *literal zero*,
  not anything from the wire. So this command cannot report failure, and all 10 bytes are
  payload. Confirms PROTOCOL.md exactly.

  The request is a single u8 with value 8 (builder `0xD3A680`), sent from one state of the
  lobby-entry state machine (`0x897758`); the state blocks on this reply and takes an error
  exit if it fails. The reset path at `0xD35780` zeroes all five halfwords, which is what an
  unanswered `0x43d0` leaves behind.

  **Values are tier 4.** The shape is the binary's; the numbers we send
  (`00 0A 00 15 00 3A 00 08 00 61` = 10, 21, 58, 8, 97) are mgo2-server's constants. They are
  kept only because **the first halfword is rendered**: `0x8978C8` loads `param_0` and passes
  it to the string formatter with message id 847, so a zero would put a zero on screen.
  Nothing is known about the other four. Answering this did **not** make the training Graduate
  action work — that is gated elsewhere on player state.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x43d1 — 10 bytes"
seq:
  - id: params
    type: u2
    repeat: expr
    repeat-expr: 5
    doc: |
      [ELF 0xD3A5EC] Five u16s, 10 bytes, the whole payload. Read by an unrolled/looped
      `0xD5CC14` sequence and block-copied to `ctx+0x117EC`.

      - `params[0]` — [CONFIRMED rendered] formatted into message id 847 at `0x8978C8`.
        Value 10 is a reference constant, not a derived one.
      - `params[1..4]` — [UNKNOWN]. Position exact, meaning unestablished; no borrowed values
        to lean on beyond 21, 58, 8, 97, whose provenance is one reference server's source.
