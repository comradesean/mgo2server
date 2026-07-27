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

  ## CORRECTION 2026-07-27: it DOES block, from the clan menu

  The note below said "harmless as-is ... do not add a reply speculatively — the live trace proves
  the client does not wait for one". That was true of the context it was observed in and false in
  general. Opening the **Clan** menu sends the same `0x4b46` and stalls on silence, failing with
  *Unable to update clan information (1933:FFFFFF60)* — observed live 2026-07-27 in an automatching
  lobby, payload `0000`, the only unanswered command in the log.

  So one command has two contexts: fired unprompted during the connect burst, where the player
  walks on regardless, and fired from the clan menu, where it is blocked on. The earlier
  elimination tested only the first. The sender (`0xD58510`) is identical in both cases and
  advances flow state via `0xD32E08(session, 98, 1)` either way; the difference is entirely in what
  the screen does while waiting.

  A general lesson for this project's "the client does not wait for a reply" claims: a command
  observed as non-blocking in one screen is not established as non-blocking, only as non-blocking
  *there*.

  We now answer it with `0x4b47` (28 bytes, result 0, an empty clan record with state 99).
seq:
  - id: unknown_0000
    type: u2
    doc: |
      [CONFIRMED] 2 bytes, observed `0000` live (OBSERVED.md 2026-07-23). Position and
      width exact (0xD5C918, big-endian). Meaning [UNKNOWN]: it is the caller's u16
      verbatim, unvalidated, and the one live sample carries zero, so the field has never
      been seen to vary. A version/flags word and a "which list" selector are both
      consistent with the single observation — nothing distinguishes them yet.
