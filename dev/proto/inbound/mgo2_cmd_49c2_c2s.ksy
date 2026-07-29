meta:
  id: mgo2_cmd_49c2_c2s
  title: "MGO2 0x49c2 — game-lobby / roster request, u32 + small enum (client -> server)"
  endian: be
doc: |
  5-byte payload: a u32 followed by a u8.

  Evidence (ELF, retail BLUS30109): sender 0xD4E008, signature (session, u32 a, u8 b).
  Prologue spills `stw r4,1416(r1)` and `stb r5,1424(r1)`. Builder `bl 0xD5CF40` at
  0xD4E0A8 (`li r4,0x49c2` at 0xD4E0A4), then
  `bl 0xD5C9BC` at 0xD4E0B8 (unsigned u32, 4 bytes MSB first, from 1416) and
  `bl 0xD5C8A0` at 0xD4E0C8 (u8, from 1424),
  then the seal `bl 0xD5C828` at 0xD4E0D4 and the flush `bl 0xD34CC0` at 0xD4E0E4.

  Validation, all returning -24 (0xFFFFFFE8) without sending: session != NULL;
  **a != 0** (`cmpdi cr6,r4,0` at 0xD4E028 — so the u32 is a real identifier, never a
  "none"); and **b in 1..4** (`cmpwi r5,0` rejects 0, `cmplwi r5,4` + `bgt` rejects >4, at
  0xD4E040..0xD4E050). It then requires 0xD4908C != -1... precisely: 0xD4908C returns -1
  when `session+0x6BA8` is non-zero and 0 otherwise, and the sender bails with -1004
  (0xFFFFFC14) when it returns -1 — i.e. this command may only be sent while that context
  slot is **clear**. On a successful flush the flow state advances via
  `0xD32E08(session, 76, 1)`.

  The 1..4 enum plus a mandatory non-zero id is the whole shape. COMMANDS.md files
  0x4904..0x49C2 as "game-lobby / roster / GHQ"; nothing in this sender narrows it further,
  and the neighbouring parsed-but-unsent range is 0x4905..0x49C3, so a bodied reply on
  0x49C3 is the obvious thing to look for when this is implemented — but that pairing is
  inference from id adjacency, not read from the dispatcher.

  Never observed live; not answered by this server.
seq:
  - id: unknown_0000
    type: u4
    doc: |
      [ELF] Position and width exact (unsigned, 0xD5C9BC). Constrained non-zero by the
      sender (0xD4E028), so it identifies something specific — lobby, player or roster
      entry. Which is [UNKNOWN].
  - id: unknown_0004
    type: u1
    doc: |
      [ELF] Position and width exact (0xD5C8A0). **Range-checked to 1..4** — the client
      never sends 0 or >4. A four-valued selector (kind / slot / sort / team are all
      consistent); no evidence in this function distinguishes them, so no enum is declared.
