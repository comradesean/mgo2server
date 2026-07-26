meta:
  id: mgo2_cmd_43e3_s2c
  title: "MGO2 0x43e3 — server -> client: automatch ack (reply to 0x43e2)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x43E3` at `0xD38A54` -> stub `0xD39D4C` ->
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

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/COMMANDS.md ("0x43e*/0x43f* — an in-match subsystem")
seq:
  - id: result
    type: s4
    doc: "[ELF 0xD5BB60] The only field. 0 = success; nonzero runs the automatch teardown helper `0xD5B41C` before completing slot 51."
