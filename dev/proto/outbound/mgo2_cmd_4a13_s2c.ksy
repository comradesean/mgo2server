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

  DESTINATION, corrected 2026-08-02 and completed 2026-08-03. The parser writes a **356-byte
  (0x164) record at session+0x11558**, not into the 7296-byte event record at session+0xDBD0.
  The base is `addis r27,r25,1` / `lwzu r0,5464(r31)` at 0xD44F8C-0xD44F9C. That record has its
  own getter **0xD3F7B0** (`return session ? session+0x11558 : NULL`; **38** call sites, not
  "~40") and its own clear-and-seed helper (entry **0xD41848** — `addis r9,r3,1`; the earlier
  0xD41850 citation is the instruction that USES r9 — plus 0xD418C0, `memset(rec,0,356)`), and
  it is SHARED with the rest of the game.

  **[2026-08-03] The shared record was already mapped by four sibling schemas, and this file
  had been written in isolation from them.** `session+0x11558` is the record
  `mgo2_cmd_43b0_c2s.ksy` calls the Survival ladder and `mgo2_cmd_43f0_s2c.ksy` /
  `mgo2_cmd_43f1_s2c.ksy` / `mgo2_cmd_4e20_s2c.ksy` name slot by slot. Every field below is
  named by struct-offset bijection WITH a traced reader, mirroring 43f0's names. The reason
  the old negatives missed the readers: they were session-relative displacement sweeps
  (5464+N), and every real reader reaches the record through the getter and then uses a small
  displacement off the returned r3 — structurally invisible to that sweep. Re-run as a
  getter-alias walk over all 38 sites, the readers appear immediately.

  READERS (this is what names the blocks). 0x8CDFA8 fetches this record through 0xD3F7B0,
  reads the u32 at **rec+0x14** (`team_a.team_id`), compares it against the local player's own
  team id, and copies **the OTHER block's name** — rec+0x50 when rec+0x14 is you, rec+0x18
  when it is not — as the `%s` of lobby string **761**, *"Your next opponent has been
  determined... Next match: vs. %s"*. [CORRECTED 2026-08-03] The second 761 renderer is
  **0x8CC574** (0x8CC604/0x8CC628/0x8CC640); **0x8CE0AC renders string 762** from rec+0x0C /
  rec+0x10 and rec+0x8C, not 761. Disc-string method: dev/docs/AUTOMATCH.md section 10;
  control: ids 251 and 245 in the same set come back "Automatching" and "Free Battle".

  TOURNAMENT-vs-SURVIVAL ROUTING [ELF 2026-08-03]: no 0x4Axx parser branches on subtype — the
  split is entirely consumer-side, on ONE byte: rec+0x08 -> app object +0x294 (written at
  0x8F9BF4). Subtype 4 routes to the 0x8CB8FC-0x8CFF40 Survival screen family (20 gates);
  3-or-5 routes to the in-game round manager 0x6EAC90/0x6EBFA8 — the only readers of
  rec+0x0C/rec+0x10 as a round total/index pair. Paired dialogs: 0x8CCD94 -> 5522 "Unable to
  cancel Survival." vs 5376 "...Tournament."; 0x8C5548/0x8C556C -> 5392 (3) / 5504 (4) / 4868
  (else). **For the version toggles: rec+0x08 is the switch; everything else about this packet
  is shared.**

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39578,
  parser 0xD44EF8.
  ODD ONE OUT: 0x4A13's parser does not live with the rest of the 0x4Axx block (0xD4Exxx -
  0xD52xxx) but at 0xD44EF8. That is now explained rather than merely noted: it writes the
  shared 356-byte record, not the tournament record, so it sits with the code that owns that
  record.

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
doc-ref: dev/proto/outbound/mgo2_cmd_43f0_s2c.ksy
seq:
  - id: card_id
    type: u4
    doc: |
      [ELF] read at 0xD44F7C (-> r1+120) and compared at 0xD44FA0 against **rec+0x00**, the id
      already sitting in the shared 356-byte record; a mismatch aborts with **-1106** and
      nothing else is read. [2026-08-03] The writer of rec+0x00 is now identified:
      **0xD512A4, inside 0x4A00's own parser**, from team+0x298 = 0x4A00's `new_id` (siblings:
      0xD4BDA0 0x49A2, 0xD4CBE4 0x4950, 0xD4D870 0x4918, 0xD51EA8 0x4A12). **So a server must
      echo 0x4A00's `new_id` here or the packet is dropped.** It is also the payload handed to
      the UI event dispatcher: 0xD45174 loads this same word and calls 0xD33CD8 with event 27.
  - id: lobby_id
    type: u4
    doc: |
      [ELF 2026-08-03 — named by bijection with traced readers; was unknown_0x04] Read at
      0xD44FB0, stored to rec+0x04 (0xD45050). **`lobby_id`** — same slot 43f0 wire 0x00 /
      43f1 wire 0x04 fill; readers 0x8F9BF8 -> app+0x290 and 0x8BE084 -> createTeam+708.
      In-family confirmation: 0x4A12 fills rec+0x04/0x08/0x09 from event+0x1BF8/+0x1BFC/+0x1BFD
      (0xD51EAC-0xD51EBC), the lobby-id/subtype/rule triple 0x4A00's own schema names.
  - id: lobby_subtype
    type: u1
    doc: |
      [ELF 2026-08-03 — named by traced readers; was unknown_0x08] Read at 0xD44FC8, stored to
      rec+0x08 (0xD45058). **`lobby_subtype`** — 0x272704 requires 2..6-excluding-2 before
      setting game+3020 bits 8/9/10; 0x6EAC90/0x6EBFA8 test ==3 / ==5; 0x8FA044 tests
      {0,1,2,7,8}; 0x8F9BF4 copies it to app+0x294, the byte ~20 screen gates read. **This
      byte is the Tournament-vs-Survival switch** (doc block). Note the parser stores this
      BEFORE the next byte despite reading it first - wire order is as listed.
  - id: lobby_subtype_sibling
    type: u1
    doc: |
      [ELF 2026-08-03 — named to match `mgo2_cmd_43f0_s2c.ksy`'s field for the same slot; was
      unknown_0x09] Read at 0xD44FE0, stored to rec+0x09 (0xD4505C). Readers 0x8F9C04 ->
      app+0x295, 0x8BE094 -> createTeam+713. The server-side evidence says a RULE ID travels
      here; the meaning is still contested exactly as 43f0 states it — same caveat, not
      re-litigated.
  - id: series_total
    type: u4
    doc: |
      [ELF 2026-08-03 — named to match 43f0; was unknown_0x0a, "[INFERRED] round count"] Read
      at 0xD44FF8, stored to rec+0x0C (0xD45060). **The slot is subtype-polymorphic, and the
      polymorphism is clean**: under Tournament (3/5) the only readers are 0x6EAC48/0x6EBF80
      evaluating `rec+0x0C - 1 == rec+0x10` — "is this the final round" — a round TOTAL; under
      Survival (4) the subtype-4 screens print the pair as the two participants' WIN COUNTS
      (lobby strings 762/763; 0x8CE0DC/0x8CC130/0x8CE1E0). Writers split the same way:
      0x4A01/0x4A20 fill it from the event record's halves[3] (0xD509EC/0xD51C50 — the old
      [INFERRED] upgraded to traced bijection), while 0x4A13/0x4E20/0x4A12 supply it directly.
      **Server hazard: mixing those writers in one session makes one reader wrong.**
  - id: series_index
    type: u4
    doc: |
      [ELF 2026-08-03 — named to match 43f0; was unknown_0x0e] Read at 0xD45010, stored to
      rec+0x10 (0xD45064). Companion of `series_total`, same polymorphism: Tournament reads it
      as the current round index (0x4A01/0x4A20 fill it from halves[5], 0xD509F4/0xD51C58);
      Survival reads it as participant B's win count. Same hazard.
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
  - id: rotation_index
    type: u1
    doc: |
      [ELF 2026-08-03 — the earlier "no reader found" was FALSE; was unknown_tail] Last byte,
      read at 0xD45158 -> rec+0x160. This is 43f1's **[CONFIRMED] `rotation_index`**, and
      exactly two commands write the slot (0x43F1 at 0xD5B7CC, 0x4A13 here at 0xD45158).
      Readers: 0x8D0158/0x8D0170/0x8D0188 and 0x93D3BC/0x93D3D4/0x93D3F0. The 0x8D0148 site
      closes the loop inside this family: it memcpys 204 bytes from **team_record+0xB0** —
      where 0x4A00's `block` lands (0xD51014) — then uses rec+0x160 to index block[idx],
      block[16+idx], block[32+idx] and promote them to entries 0/16/32, with a silent fallback
      to entry 0 when map==0 or rule>10. The old sweep missed all six readers because it was
      session-relative (displacement 5624) and every reader goes through the getter.
types:
  team_block:
    doc: |
      [ELF] 52 wire bytes: one team's identity plus eight words. The id/name pair is named by a
      traced reader (see the top-level doc); the eight words are the member character ids.
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
      - id: chara_ids
        type: u4
        repeat: expr
        repeat-expr: 8
        doc: |
          [ELF 2026-08-03 — the earlier "no reader for any of the eight" was FALSE; was
          `words`] Exactly eight u32; hard-coded loop bound (`cmpdi r28,8` at
          0xD450C8/0xD4513C). **The team's member CHARACTER IDS** — the same slots
          rec+0x2C..0x48 / rec+0x64..0x80 that 43f0 names `team0_chara_ids`/`team1_chara_ids`,
          and the reader is the roster team-assignment at 0x270CDC-0x270D94 (plus
          0x272D40-, 0x273914): it compares the local character id (session+0x57D8) against
          all sixteen, interleaved, and writes team 0 or 1 into the roster entry's team byte.
          The old sweep missed it for the same session-relative reason as `rotation_index`.
