meta:
  id: mgo2_cmd_43e3_s2c
  title: "MGO2 0x43e3 — cancel automatching result (server -> client)"
  endian: be
doc: |
  Reply to `0x43e2`. **Four bytes: a bare result.**

  Send an explicit four-byte zero, never an empty payload — an empty one leaves the client reading
  four bytes of stale receive buffer as its result. That is the trap `0x4399` fell into.

  ## The one code worth knowing

  If the searcher has already been matched when the cancel arrives, answer **`-953`**
  (`AUTOMATCH_CANCEL_TOO_LATE`). It is the only code in this family that **parks the client silently**
  rather than raising a dialog — the right outcome for "your cancel lost a race you cannot see".

  `-952` is the ordinary failure and prints *"Unable to cancel automatching."*

  ## Evidence

  GAME dispatcher `0xD387C8` (compare tree `0xD38804`) matches `cmpwi 0x43E3` at `0xD38A54` -> stub
  `0xD39D4C` -> parser **`0xD5BB04`**. Request-status slot **51** — the slot the `0x43E2` builder
  marks pending (`0xD5BC14`..`0xD5BC88`), which is how the pairing is established from the binary
  rather than by assuming adjacent ids go together.

  One `0xD5CC64` u32 read; then, **if nonzero**, `0xD5B41C` (the shared automatch teardown helper);
  then `0xD32E08(ctx, 51, 2)` and `0xD32E70(ctx, 51, result)` unconditionally.
seq:
  - id: result
    type: s4
    doc: |
      [ELF `0xD5BB60`] The only field. 0 = cancelled; nonzero runs the teardown helper `0xD5B41C`
      before completing slot 51.

      **`-953` parks the client silently** and is what a too-late cancel should answer; `-952`
      prints "Unable to cancel automatching."
