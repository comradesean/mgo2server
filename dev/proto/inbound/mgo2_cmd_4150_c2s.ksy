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
  - id: unknown_00
    type: u1
    doc: |
      [UNKNOWN] Position exact, meaning unestablished — the sender takes it as a plain
      argument with no range check, so nothing at the call site narrows it.
      **[INFERRED] candidate:** the lobby type or subtype being disconnected from. `0x4150`'s
      sender sits in the same cluster as the game-lobby `0x3003` sender (`0xd39f18`), whose
      own trailing byte is likewise an unexplained caller-supplied `u8` — see
      `mgo2_cmd_3003.ksy`. Cheap experiment: log the byte on back-out from a GAME lobby versus
      an ACCOUNT lobby and see whether it changes.
