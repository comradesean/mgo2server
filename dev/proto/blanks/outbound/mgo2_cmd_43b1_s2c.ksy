meta:
  id: mgo2_cmd_43b1_s2c
  title: "MGO2 0x43B1 — server -> client: bare result ack for 0x43b0 (never observed; COMMANDS.md reachable-in-ordinary-flow gap)"
  endian: be
doc: |
  Evidence: reply dispatcher `0xD38804` (the `0x41xx`-`0x4Exx` compare chain) matches
  `cmpwi 0x43B1` and branches to the stub at `0xd39588`, which tail-calls the parser at
  `0xd40220`.

  The parser is one of a family of twelve **byte-identical 196-byte functions** laid out
  back to back from `0xD3FFD4` to `0xD40904`, one per id, differing only in the id they
  verify and the request-status slot they signal. Each one:

  1. fetches the inbound packet (`0xD3879C`) and checks `hdr.command == 0x43B1`
     (mismatch -> `-70`, the no-handler code);
  2. `0xD5C844` open-payload, **one** `0xD5CC64` u32 read into a stack slot, `0xD5C858`
     close-payload (a failed read -> `-71` and the request is never completed);
  3. `0xD32E08(ctx, 55, 2)` — mark request-status slot **55** complete
     (slot table at `ctx+360+4*id`, ids capped at 116);
  4. `0xD32E70(ctx, 55, result)` — store the u32 as that slot's result
     (result table at `ctx+828+4*id`).

  So the whole payload is four bytes. Nothing else is read, nothing is stored in any
  game/roster structure, and no field is rendered: the value only reaches the waiting
  request slot, where a nonzero code surfaces as the screen's error dialog.

  COMMANDS.md files 0x43b1 under "result singles" — parsed but never sent.
doc-ref: dev/docs/COMMANDS.md, dev/docs/PROTOCOL.md
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xd40220] The only field. 0 = success. Signed: the client stores it with `lwa`
      and the protocol's error codes (`C0FFEE01`, `C0FFEE02`, `0xFFFFFF60`) are negative
      when read as s32. The parser does **not** branch on the value — it hands it to the
      request slot verbatim — so an error code is surfaced by the screen that was waiting,
      not by this parser.
