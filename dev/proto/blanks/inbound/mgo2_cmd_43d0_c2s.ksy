meta:
  id: mgo2_cmd_43d0_c2s
  title: "MGO2 0x43d0 — training parameter fetch (client -> server)"
  endian: be
doc: |
  Builder function `0xD3A680` = `f(ctx, u8 arg)` (`stb r4,1416(r1)` at `0xD3A6AC`);
  `bl 0xD5CF40` at `0xD3A6F4` (`li r4,0x43D0` at `0xD3A6F0`). One `0xD5C8A0` (u8) write at
  `0xD3A704`, seal `0xD5C828` at `0xD3A710`, flush `0xD34CC0` at `0xD3A720`. Not encrypted.
  **Total payload 1 byte.** The ELF agrees with `PROTOCOL.md`, which records the same builder
  address and "a single u8 argument, value 8" observed live.
  ## When it is sent

  Traced 2026-07-26. The lobby-entry state machine reaches the sending state (state 1, `0x89774C`)
  only when, in a training lobby, **skill 17's record is present and its flag byte is zero**
  (`0x897314` / `0x897320`). A nonzero flag routes to state 3 instead and this command is never
  sent. Since that flag arrives only from our `0x4125`/`0x4129` and nothing in the client writes
  it, we decide whether the client asks us this question at all.
doc-ref: dev/docs/PROTOCOL.md "0x43d0 — training parameter fetch"
seq:
  - id: request_kind
    type: u1
    doc: |
      [CONFIRMED] 0x00. Observed live as **8**. Sent from one state of the lobby-entry state
      machine (`0x897758`); the state blocks on `0x43D1` and takes an error exit if it fails.
      Whether other values are ever sent is [UNKNOWN] — the sender does not validate it, so the
      8 is the caller's, not a constraint.
