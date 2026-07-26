meta:
  id: mgo2_cmd_4a30_c2s
  title: "MGO2 0x4a30 — unidentified subsystem, single u32 (client -> server)"
  endian: be
doc: |
  4-byte payload: one unsigned u32.

  Evidence (ELF, retail BLUS30109): sender 0xD5048C, signature (session, u32). Prologue
  spills `stw r4,1416(r1)`. Builder `bl 0xD5CF40` at 0xD50500 (`li r4,0x4a30` at 0xD504FC);
  the only write between builder and seal is `bl 0xD5C9BC` at 0xD50510 (unsigned u32, 4
  bytes MSB first). Seal `bl 0xD5C828` at 0xD5051C, flush `bl 0xD34CC0` at 0xD5052C.
  Preconditions: session != NULL plus the two generic connection checks (0xD38504,
  0xD3844C). The u32 is not range-checked.

  Useful extra: on a successful flush the client **caches the value it just sent** into the
  global block at `+0x6D08` (`lwz r0,1416(r1)` / `stw r0,27912(r9)` at 0xD50564..0xD50568),
  then advances the flow state via `0xD32E08(session, 87, 1)`. 0x4B20's sender does the same
  thing into the adjacent slot `+0x6D00`. So the argument is a *selection the client
  remembers* — a current-item or current-page id — rather than a one-shot action code.

  COMMANDS.md files 0x4A25/0x4A30/0x4A40 as an unidentified subsystem whose server->client
  side has lists at 0x4A11/0x4A33/0x4A42; the 0x4A33 list id is adjacent to this send id,
  which is suggestive of a request/list pairing but is [INFERRED] from numbering only.

  Never observed live; not answered by this server.
seq:
  - id: unknown_0000
    type: u4
    doc: |
      [ELF] Position and width exact (unsigned, 0xD5C9BC). Unvalidated caller argument.
      [INFERRED] a selector the client retains: the same value is stored to the session
      global `+0x6D08` after the send. Meaning otherwise [UNKNOWN].
