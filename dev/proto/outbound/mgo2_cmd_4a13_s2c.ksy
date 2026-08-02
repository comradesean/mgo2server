meta:
  id: mgo2_cmd_4a13_s2c
  title: "MGO2 0x4A13 - Tournament/Survival next-match card, two team blocks (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1); see mgo2_cmd_4a24_s2c.ksy and mgo2_cmd_4a00_s2c.ksy for the identifying
  evidence. 0x4A13 carries **the two teams of your next match**: two identical
  {team id, team name, u32[8]} blocks, and the renderer picks whichever block is NOT yours to
  print as the opponent.

  TIER. Tournament and Survival are post-launch content (Ver. 1.20 / Ver. 1.10). No available
  client build exercises 0x4A13, so **everything here is tier 1, read from MGO2.elf, and cannot
  be raised to tier 2.** Nothing below is backed by a capture. Mapping is in scope; serving it
  in v1 is not.

  DESTINATION, corrected 2026-08-02. The parser writes a **356-byte (0x164) record at
  session+0x11558**, not into the 7296-byte event record at session+0xDBD0. The base is
  `addis r27,r25,1` / `lwzu r0,5464(r31)` at 0xD44F8C-0xD44F9C. That record has its own getter
  **0xD3F7B0** (`return session ? session+0x11558 : NULL`) and its own clear-and-seed helper
  **0xD41850 / 0xD418C0** (`memset(rec,0,356)`), and it is SHARED with the rest of the game -
  0xD3F7B0 has ~40 call sites. So the offsets below are offsets into that shared record, and
  the 0x4A24 event record's field names do NOT apply to them.

  READERS FOUND (this is what names the two blocks). 0x8CDFA8 and 0x8CE0AC fetch this record
  through 0xD3F7B0, read the u32 at **rec+0x14** (`group_a.team_id`), compare it against the
  local player's own team id (`lwz r9,108(...)` then `lwz r0,0(r9)`), and then copy **the OTHER
  block's name** - rec+0x50 when rec+0x14 is you, rec+0x18 when it is not - as the `%s` of
  lobby string **761**, *"Your next opponent has been determined.\nThe match will begin
  shortly.\nPlease wait.\nNext match: vs. %s"*. Disc-string method: dev/docs/AUTOMATCH.md
  section 10; string set `$strres:9789..11033`, string base 11034. Control for the resolution:
  ids 251 and 245 in the same set come back "Automatching" and "Free Battle", matching
  PROTOCOL.md's already-established Lobby Select labels.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39578,
  parser 0xD44EF8.
  ODD ONE OUT: 0x4A13's parser does not live with the rest of the 0x4Axx block (0xD4Exxx -
  0xD52xxx) but at 0xD44EF8. That is now explained rather than merely noted: it writes the
  shared 356-byte record, not the tournament record, so it sits with the code that owns that
  record.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39578,
  parser 0xD44EF8.
  No identity header. Two structurally identical groups of {u32, 16-byte text, u32 x8}, each
  eight-word array hard-coded (`cmpdi r28,8` at 0xD450C8 and 0xD4513C) - no counts on the wire.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: card_id
    type: u4
    doc: |
      [ELF] read at 0xD44F7C (-> r1+120) and compared at 0xD44FA0 against **rec+0x00**, the id
      already sitting in the shared 356-byte record; a mismatch aborts with **-1106** and
      nothing else is read. So the server must echo the id that record was last stamped with.
      [UNKNOWN] which producer stamps it - 0xD41850 writes rec+0x04/+0x08/+0x09 but not +0x00,
      so the writer of rec+0x00 was not identified. It is also the payload handed to the UI
      event dispatcher: 0xD45174 loads this same word and calls 0xD33CD8 with **event 27**.
  - id: unknown_0x04
    type: u4
    doc: "[UNKNOWN] read at 0xD44FB0 (-> r1+116), stored to rec+0x04 (0xD45050). Shared slot: the generic seeder 0xD41850 writes rec+0x04 from its own first argument, so this field is not specific to 0x4A13 and no single reader names it."
  - id: unknown_0x08
    type: u1
    doc: "[UNKNOWN] read at 0xD44FC8 (-> r1+113), stored to rec+0x08 (0xD45058). Also written by 0xD41850 from its second argument. Note the parser stores this BEFORE the next byte despite reading it first - wire order is as listed."
  - id: unknown_0x09
    type: u1
    doc: "[UNKNOWN] read at 0xD44FE0 (-> r1+112), stored to rec+0x09 (0xD4505C). Also written by 0xD41850 from its third argument."
  - id: unknown_0x0a
    type: u4
    doc: "[UNKNOWN] read at 0xD44FF8 (-> r1+124), stored to rec+0x0C (0xD45060). Same slot the 0x4A01 and 0x4A20 parsers fill from the event record's `halves[3]` (round count) at 0xD509EC / 0xD51C50 - so a round number is the shape that fits, but this packet supplies it directly and no reader was traced. [INFERRED] round count."
  - id: unknown_0x0e
    type: u4
    doc: "[UNKNOWN] read at 0xD45010 (-> r1+128), stored to rec+0x10 (0xD45064). Companion of the field above: 0x4A01/0x4A20 fill this same slot from `halves[5]`, the **current round** (0xD509F4 / 0xD51C58). [INFERRED] current round."
  - id: team_a
    type: team_block
    doc: |
      [ELF] u32 at 0xD45070 -> rec+0x14, 16-byte raw at 0xD45090 -> rec+0x18, then the
      eight-word loop 0xD450A4-0xD450D4 -> rec+0x2C..+0x48.
      **This block's id is what the client compares against your own team** (0x8CDFC0
      `lwz r10,20(r3)`), so of the two blocks this is the one the comparison is written around.
  - id: team_b
    type: team_block
    doc: "[ELF] u32 at 0xD450E4 -> rec+0x4C, 16-byte raw at 0xD45104 -> rec+0x50, eight-word loop 0xD45118-0xD45148 -> rec+0x64..+0x80. Structurally identical to team_a; separate storage. The renderer prints team_b's name when team_a's id is your own team."
  - id: unknown_tail
    type: u1
    doc: "[UNKNOWN] last byte, read at 0xD45158 -> rec+0x160. **No reader found.** Swept for `lbz` at displacement 5464+0x160 = 5624 across the whole cached disassembly: zero hits in either form. Control: the same displacement sweep does return the writers at 5464/5472/5480, and the record's readers were found by following 0xD3F7B0 instead, which is how rec+0x14/+0x18/+0x50 above were named."
types:
  team_block:
    doc: |
      [ELF] 52 wire bytes: one team's identity plus eight words. The id/name pair is named by a
      traced reader (see the top-level doc); the eight words are not.
    seq:
      - id: team_id
        type: u4
        doc: "[ELF] the team's record id. 0x8CDFC0 compares rec+0x14 against the local player's own team id and branches on the result, which is only meaningful if this is a team id."
      - id: team_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[ELF] the team's display name, 16 bytes with the reader's NUL written at +16. Not inferred from width: 0x8CDFF8/0x8CE01C hand rec+0x50 or rec+0x18 to the string copier 0xAF70F0 and then to lobby string 761 as its `%s` - *\"Next match: vs. %s\"*."
      - id: words
        type: u4
        repeat: expr
        repeat-expr: 8
        doc: "[UNKNOWN] exactly eight u32; the count is a hard-coded loop bound (`cmpdi r28,8` at 0xD450C8 / 0xD4513C), not a wire field. **No reader for any of the eight.** Swept the cached disassembly for loads at displacements 5508..5544 (team_a's words) and 5564..5600 (team_b's) - only the two write loops. Per-team match scores is the obvious reading beside a team id and name, but nothing in this build displays them, so it stays [UNKNOWN] rather than [INFERRED]."
