meta:
  id: mgo2_cmd_43e3_s2c
  title: "MGO2 0x43e3 — server -> client: automatch ack (reply to 0x43e2)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x43E3` at `0xD38A54` -> stub `0xD39D4C` ->
  parser **`0xD5BB04`**. Request-status slot **51** — the slot the `0x43E2` builder
  (`0xD5BC14`..`0xD5BC88`: begin packet id `0x43E2`, send, then `0xD32E08(ctx, 51, 1)`) marks
  pending, which is how the pairing is established from the binary rather than by numbering.

  A bare result ack: one `0xD5CC64` u32, then — **if nonzero** — `0xD5B41C` (the shared
  error/teardown helper), then `0xD32E08(ctx, 51, 2)` and `0xD32E70(ctx, 51, result)`
  unconditionally. **4 bytes.**

  Neither PROTOCOL.md nor either reference server documents `0x43E2`/`0x43E3`; COMMANDS.md
  files them under "an in-match subsystem the client sends `0x43e0`/`0x43e2` into". Visible in
  the same builder region: `0x43E0` (the status fetch) appends one u8 via `0xD5C8A0` and marks
  slot **50**, `0x43E2` appends **nothing** and marks slot **51**. So `0x43E2` is an
  argument-less automatch action — plausibly the cancel or the enter/leave-queue toggle —
  and this is its acknowledgement. **[UNKNOWN: which action.]** No screen has been observed
  sending it.
doc-ref: dev/docs/COMMANDS.md ("0x43e*/0x43f* — an in-match subsystem")
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD5BB60] The only field. 0 = success; nonzero runs the automatch teardown helper `0xD5B41C` before completing slot 51."
