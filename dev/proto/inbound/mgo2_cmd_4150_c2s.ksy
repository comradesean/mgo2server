meta:
  id: mgo2_cmd_4150_c2s
  title: "MGO2 0x4150 — lobby disconnect (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd3859c`
  (`li r4,16720` = `0x4150` at `0xd38598`), sender `0xd38530`-ish. Exactly one write primitive:
  `bl 0xd5c8a0` (write-u8) at `0xd385ac`, from stack `1416(r1)` where the sender's `r4`
  argument was spilled at `0xd3855c`. Seal `bl 0xd5c828` at `0xd385b8`, flush `bl 0xd34cc0`
  at `0xd385c8`, wait slot `0x74` (`li r4,116` at `0xd385d0` -> `bl 0xd32e08`). [ELF]

  **This contradicts PROTOCOL.md**, which states "Empty request, empty `0x4151` reply". The
  request is not empty — one byte precedes nothing. The empty *reply* claim is untouched and
  still stands on its own evidence. Our handler ignores the body, so no live behaviour changes;
  but the byte is being discarded unread, and lobby membership is not tracked, so if this byte
  says *which* lobby is being left, that information is currently thrown away.
doc-ref: dev/docs/PROTOCOL.md "0x4150 — lobby disconnect"
seq:
  - id: always_zero
    type: u1
    doc: |
      [CONFIRMED constant, ELF 2026-08-01; renamed from `unknown_00`] Position and width exact.
      **The client can only ever send `0x00`.** Meaning still unestablished — a zero is a zero —
      but the value is now closed, so the server has nothing to learn from this byte and nothing
      to lose by ignoring it.

      The sender `0xd38530` takes the byte as a plain `r4` argument with no range check
      (spilled to `1416(r1)` at `0xd3855c`, written by `bl 0xd5c8a0` at `0xd385ac`), so the
      answer had to come from the callers rather than from the sender. **All four `bl` sites
      execute `li r4,0` immediately before the call:**

      | call site | the `li r4,0` |
      | --- | --- |
      | `0x891890` | `0x891870` |
      | `0x891920` | `0x891900` |
      | `0x8981D0` | `0x8981C8` |
      | `0x8BCF4C` | `0x8BCF44` |

      No branch reaches any of the four with a different `r4`: in each case the immediate is in
      the same basic block as the `bl`, three instructions or fewer above it, with no
      intervening label.

      **The four are the complete set of entries.** `0xd38530`'s OPD descriptor at `0x10290B0`
      is referenced by no data word anywhere in the file, there is no `b 0xd38530` tail call, and
      the image is `ET_EXEC` with no relocations — so it cannot be reached through a function
      pointer either. That is the three-part test `FIELD_MAPPING.md`'s batch-3b section requires
      before a "nothing else calls this" claim counts.

      **This retires the [INFERRED] candidate this field used to carry** — "the lobby type or
      subtype being disconnected from", by analogy with `0x3003`'s trailing byte. A subtype byte
      that is 0 at every call site is not a subtype byte. The proposed experiment (back out of a
      GAME lobby versus an ACCOUNT lobby and watch the byte) would have shown no change, and per
      CLAUDE.md's elimination rule it could not have distinguished the two readings anyway.
