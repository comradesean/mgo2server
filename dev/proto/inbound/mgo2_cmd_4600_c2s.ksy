meta:
  id: mgo2_cmd_4600_c2s
  title: "MGO2 0x4600 — player search (client -> server)"
  endian: be
doc: |
  Builder function `0xD46128` = `f(ctx, u8 criteria, u8 ignore_case, char *name)`
  (`stb r4,1432(r1)` at `0xD46160`, `stb r5,1440(r1)` at `0xD4615C`); a null `name` aborts
  (`0xD46168`) and `strlen(name) > 16` aborts (`cmplwi cr7,r3,16` at `0xD46184`).
  `bl 0xD5CF40` at `0xD461E4` (`li r4,0x4600` at `0xD461E0`). Writes `0xD5C86C` (u8) at
  `0xD461F4`, `0xD5C86C` (u8) at `0xD46204`, then `0xD5D0AC` with `r5=16` at `0xD46218`;
  seal `0xD5C828` at `0xD46224`, flush `0xD34CC0` at `0xD46234`. Not encrypted.
  **Total payload 18 bytes (0x12)** — agrees with `PROTOCOL.md` exactly.

  The sender also guards the first argument at `0xD46140` (`cmplwi cr6,r0,1`), matching
  `PROTOCOL.md`'s "0 = partial, 1 = full — the builder rejects other values".

  **POLARITY CORRECTION, live 2026-07-27.** The second byte means **IGNORE CASE (1 = ignore)**.
  It was documented here and named in our code as "case sensitive", which is the opposite, and
  the ELF gives no polarity — the builder stores the argument and never tests it, so the name was
  never evidence of anything. Live: searching "bob" from the player-search screen with **Case
  Insensitive** selected arrived as `{0, 1}`, we ran a case-SENSITIVE query, and it matched
  nothing against a character named "Bob"; the client reported "Unable to locate that character".
  A case-sensitive search is still reachable — the byte is 0 then.

  The polarity is the CLIENT'S, not a per-screen quirk: the clan-search screen (`0x4b90`) sends
  the same `{0, 1}` from its own toggles.

  Recorded because it is the failure mode CLAUDE.md warns about: an integration test asserted the
  OLD polarity, and its only authority was the field's own name — no capture, no disassembly.
  That is a regression guard, not a correctness check, and it guarded a wrong reading for as long
  as nobody searched for a name whose case differed.
doc-ref: dev/docs/PROTOCOL.md "0x4600 — player search"
seq:
  - id: match_criteria
    type: u1
    doc: "[CONFIRMED] 0x00. 0 = partial, 1 = full. The builder rejects other values (`0xD46140`). Both toggles are nibbles of one UI control byte; all four semantics combinations are **server policy**, not protocol — ours is substring for partial, SQL-escaped."
  - id: ignore_case
    type: u1
    doc: |
      [CONFIRMED live 2026-07-27] 0x01. **1 = ignore case, 0 = case sensitive.** Not range-checked
      by the sender, and its polarity is not readable from the ELF — the builder stores the
      argument and never tests it. Falsified reading: this field was named `match_case` and
      documented as a "case-sensitivity toggle", i.e. the opposite sense. See the top-level doc
      for the live observation and for why the test that agreed with the old name proved nothing.
  - id: name
    size: 16
    doc: "[CONFIRMED] 0x02-0x11. Search term, ISO-8859-1 NUL-padded; the client refuses to send more than 16 characters. Raw 16-byte copy, so trailing bytes are whatever the caller's buffer holds beyond the NUL."
