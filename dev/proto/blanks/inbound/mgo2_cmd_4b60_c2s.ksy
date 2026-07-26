meta:
  id: mgo2_cmd_4b60_c2s
  title: "MGO2 0x4b60 — clan/GHQ request (client -> server)"
  endian: be
doc: |
  Payload is one big-endian u32 and nothing else — 4 bytes total.

  Evidence (ELF, retail BLUS30109): sender 0xD572FC. Builder `bl 0xD5CF40` at 0xD57384
  (`li r4,0x4b60` in the preceding instruction); the ONLY payload write between the
  builder and the seal `bl 0xD5C828` is `bl 0xD5C9BC`, the unsigned-u32 serializer
  (4 bytes, MSB first, from the u32 at r4). Flush is `bl 0xD34CC0`. The value is the
  sender's own r4 parameter, spilled by `stw r4,1416(r1)` in the prologue and passed
  back by address; the function range-checks it not at all.

  Preconditions: session != NULL, and 0xD5709C true (clan record present, status == 2);
  otherwise -1203 and no packet.

  On a successful flush the client advances its flow state with
  `0xD32E08(session, 106, 1)`. The sender does not name the reply id.

  Family context [INFERRED]: `0x4Bxx` is the clan / GHQ subsystem. The session carries a
  clan record at `session_ctx+0x1AA0` (accessor 0xD56EDC over the context returned by
  0xD3A094), shaped {u32 id @0x00, char name[] @0x04 (<=16), u8 status @0x15}; the 0x4B42
  sender writes all three, 0xD57750 gates on id != 0, and 0xD5709C gates on status == 2.
  That record is the whole basis for reading this family as clan/GHQ — structural, not
  capture-proven.

  Never observed live; this server does not answer it. An unanswered command normally
  stalls the client with FFFFFF60 (CLAUDE.md), so a reply is required before whatever menu
  sends this becomes reachable.
seq:
  - id: unknown_0000
    type: u4
    doc: |
      [ELF] Position and width exact (unsigned, 0xD5C9BC). Meaning [UNKNOWN]: it is the
      caller's u32 verbatim and nothing in this function narrows it. Some id or cursor,
      given the family; no evidence here chooses between clan id, member id and index.
