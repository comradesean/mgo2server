meta:
  id: mgo2_cmd_4b46_c2s
  title: "MGO2 0x4b46 — clan/GHQ two-byte probe (client -> server), non-blocking"
  endian: be
doc: |
  2-byte payload: a single u16. **Capture-proven**: OBSERVED.md ("New: `0x4b46` observed,
  unhandled, non-blocking", 2026-07-23) records the client sending 0x4B46 with 2 bytes
  `0000` shortly after the lobby connect burst and then proceeding normally with **no reply
  at all** — the first observed command that does not stall on silence. Both the length and
  the value on the wire therefore agree with the ELF.

  Evidence (ELF, retail BLUS30109): sender 0xD58510. `sth r4,1416(r1)` in the prologue
  spills the caller's u16; builder `bl 0xD5CF40` at 0xD58584 (`li r4,0x4b46` at 0xD58580),
  one write `bl 0xD5C918` at 0xD58594 — the 2-byte serializer, which stores
  `(v >> 8) & 0xFF` then `v & 0xFF`, i.e. big-endian — then the seal `bl 0xD5C828` at
  0xD585A0 and the flush `bl 0xD34CC0` at 0xD585B0. On success the flow state advances via
  `0xD32E08(session, 98, 1)`.

  Unlike its 0x4Bxx siblings this sender has NO clan-record precondition: only
  session != NULL plus the two generic connection checks (0xD38504, 0xD3844C). That fits
  the observation that it fires unprompted during the connect sequence rather than from a
  clan menu.

  Operator note: harmless as-is. The value is hex-logged if it recurs; do not add a reply
  speculatively — the live trace proves the client does not wait for one, and 0x4115 is the
  precedent for a reply the client has no parser for.
seq:
  - id: unknown_0000
    type: u2
    doc: |
      [CONFIRMED] 2 bytes, observed `0000` live (OBSERVED.md 2026-07-23). Position and
      width exact (0xD5C918, big-endian). Meaning [UNKNOWN]: it is the caller's u16
      verbatim, unvalidated, and the one live sample carries zero, so the field has never
      been seen to vary. A version/flags word and a "which list" selector are both
      consistent with the single observation — nothing distinguishes them yet.
