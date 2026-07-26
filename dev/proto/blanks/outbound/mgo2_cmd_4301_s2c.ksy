meta:
  id: mgo2_cmd_4301_s2c
  title: "MGO2 0x4301 — server -> client: game-list START (reply 1/3 to 0x4300)"
  endian: be
doc: |
  Evidence: dispatcher `0xD38804` matches `cmpwi 0x4301` at `0xD38910` and branches to the
  stub `0xD39918`… (stub at `0xD391A0`), which tail-calls the parser at **`0xD40B10`**.

  The parser is the **start** half of a list triple (`0x4301` start / `0x4302` entries /
  `0x4303` end). It resolves a game-list object `G` — `G = *(ctx+0x11904) + 0x10000 - 24424`
  — and:

  1. verifies `hdr.command == 0x4301` (else `-70`);
  2. **requires `*(G+0) == 0`**, i.e. no list transfer already in progress; a second
     `0x4301` without an intervening `0x4303` returns **`-73`** and is dropped;
  3. reads exactly **one u32** (`0xD5CC64`) and nothing else;
  4. **if that u32 is zero** (success): calls `0xD32E70(ctx, 33, 0)` to park result 0 and
     writes `*(G+4) = 0` (entry count reset) and `*(G+0) = -1` (transfer open). It does
     **not** mark request-status slot 33 complete — the client keeps waiting for `0x4303`;
  5. **if nonzero**: `0xD32E08(ctx, 33, 2)` + `0xD32E70(ctx, 33, value)` — the transaction
     completes as failed immediately, and `0x4302`/`0x4303` are never expected.

  This is the binary proof of the rule already recorded in `dev/proto/README.md`: the leading
  u32 is a **result code, never a count**. A count in this slot opens no transfer (nonzero =
  failure) and produces the `1032:00000005` error recorded in OBSERVED.md.

  PROTOCOL.md agrees: "`0x4301` | 4 bytes result (`00000000`, or `C0FFEE02` with no session
  and nothing further)".
doc-ref: dev/docs/PROTOCOL.md "0x4300 — get game list"; dev/proto/README.md
seq:
  - id: result
    type: s4
    doc: |
      [CONFIRMED] 0 opens the list transfer; nonzero aborts it and surfaces on the waiting
      screen. Request-status slot **33** is shared by all three packets of the triple.
      [ELF 0xD40B10]
