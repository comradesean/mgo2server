meta:
  id: mgo2_cmd_4311_s2c
  title: "MGO2 0x4311 — server -> client: host-settings push ack (reply to 0x4310)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x4311` at `0xD38934` -> stub `0xD391E0` ->
  parser **`0xD43550`**. Request-status slot **35**.

  **This settles PROTOCOL.md's open question.** PROTOCOL.md says the reply is empty, that both
  references send empty, that this client accepts it, and — correctly cautious — that "whether
  it reads any field beyond the header is undetermined". It reads exactly one field: a u32.
  The parser does nothing else. There is no second field, no blob, no echo of the pushed
  settings. So the reply's full and complete form is **4 bytes**.

  Sequence at `0xD43550`: verify `hdr.command == 0x4311` (else `-70`); `0xD5C844` open;
  one `0xD5CC64` u32 read (failure -> `-71`); `0xD5C858` close; **if the value is nonzero**,
  call `0xD5BDA0` and, on a nonzero return from that, `0xD5B41C` — an error/teardown path
  shared with the automatch replies (`0x43E1`/`0x43E3` call the same `0xD5B41C`); then
  `0xD32E08(ctx, 35, 2)` and `0xD32E70(ctx, 35, result)` **unconditionally**, so even a
  failing push completes the request rather than hanging.

  Why the empty reply works anyway: the read primitives bound-check the **1023-byte receive
  buffer**, not the payload length, so the u32 read on an empty payload succeeds and returns
  whatever the buffer held. If that were ever nonzero the client would take the error path.
  Sending an explicit 4-byte zero removes the dependence on buffer state; an empty payload is
  live-verified but not sound.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4311 — empty"
seq:
  - id: result
    type: s4
    doc: |
      [ELF 0xD43550] The whole payload. 0 = success. Nonzero triggers `0xD5BDA0`/`0xD5B41C`
      before the request slot is completed. Never observed nonzero — the server has always
      answered success (or, until now, empty).
