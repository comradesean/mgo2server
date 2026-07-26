meta:
  id: mgo2_cmd_4600_c2s
  title: "MGO2 0x4600 — player search (client -> server)"
  endian: be
doc: |
  Builder function `0xD46128` = `f(ctx, u8 criteria, u8 match_case, char *name)`
  (`stb r4,1432(r1)` at `0xD46160`, `stb r5,1440(r1)` at `0xD4615C`); a null `name` aborts
  (`0xD46168`) and `strlen(name) > 16` aborts (`cmplwi cr7,r3,16` at `0xD46184`).
  `bl 0xD5CF40` at `0xD461E4` (`li r4,0x4600` at `0xD461E0`). Writes `0xD5C86C` (u8) at
  `0xD461F4`, `0xD5C86C` (u8) at `0xD46204`, then `0xD5D0AC` with `r5=16` at `0xD46218`;
  seal `0xD5C828` at `0xD46224`, flush `0xD34CC0` at `0xD46234`. Not encrypted.
  **Total payload 18 bytes (0x12)** — agrees with `PROTOCOL.md` exactly.

  The sender also guards the first argument at `0xD46140` (`cmplwi cr6,r0,1`), matching
  `PROTOCOL.md`'s "0 = partial, 1 = full — the builder rejects other values".
doc-ref: dev/docs/PROTOCOL.md "0x4600 — player search"
seq:
  - id: match_criteria
    type: u1
    doc: "[CONFIRMED] 0x00. 0 = partial, 1 = full. The builder rejects other values (`0xD46140`). Both toggles are nibbles of one UI control byte; all four semantics combinations are **server policy**, not protocol — ours is substring for partial, SQL-escaped."
  - id: match_case
    type: u1
    doc: "[CONFIRMED] 0x01. Case-sensitivity toggle. Not range-checked by the sender."
  - id: name
    size: 16
    doc: "[CONFIRMED] 0x02-0x11. Search term, ISO-8859-1 NUL-padded; the client refuses to send more than 16 characters. Raw 16-byte copy, so trailing bytes are whatever the caller's buffer holds beyond the NUL."
