meta:
  id: mgo2_cmd_4b01_s2c
  title: "MGO2 0x4b01 — create clan result, {result, clan_id} (server -> client)"
  endian: be
doc: |
  **Create a clan.** The reply to 0x4b00, `{name[16], description[128]}` = 144 bytes.
  [CONFIRMED LIVE 2026-07-27] — creating "best clan" with the comment "numbuh 1" produced exactly
  this exchange, and the clan appeared with the creator as its leader.

  Two words on success:

    * on **result == 0** the client stores the second word as ITS OWN clan id and sets itself
      LEADER — 0xD56E84 (`lwz r9,116(r1)` / `stw r9,6816`) then 0xD56E90 (`li r0,2; stb r0,6837`),
      i.e. profile+6816 = clan id and profile+6837 = membership state 2. So the server does not
      have to follow up with a 0x4b47; the client has already made itself leader.
    * a **non-zero result ends the payload after four bytes** and the client keeps whatever clan
      record it had.

  Refusal codes the client has strings for on this operation (its own table at 0x106D714, not
  ours): -1206 "Conditions to create clan have not been met.", -1200 a clan by that name already
  exists, -1230 banned from creating clans, -1231 comment contains an invalid word, -1233 clan
  name contains an invalid character, -24 clan name is not long enough.

  Note the requirement check is NOT client-side: 0xD579AC validates only the name (3..16
  characters, character-class check 0xD32DD0) and the comment length before sending, with no
  play-time or level read anywhere. The 20-hours-and-level-3 rule (lobby string 17193) is real but
  the server is the only thing that can enforce it.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39ACC,
  parser 0xD56DBC.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE34 delimiter-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  ADDRESS AND SEMANTICS CORRECTION (2026-07-26, read out of the primitive itself): the string
  reader's entry point is **0xD5CE34**, not 0xD5CE3C — the previous function's `blr` is at
  0xD5CE30 and 0xD5CE3C is two instructions into the body. It is **not** a NUL-terminated
  string reader: the loop compares each byte against **r5, a caller-supplied delimiter**
  (`cmpw cr7,r0,r5` at 0xD5CE78); NUL is only a secondary stop (`cmpwi cr6,r0,0` at 0xD5CE7C).
  Callers that pass r5 = 0 get NUL termination as a special case. Either way the cursor is
  advanced **past** the terminator (`addi r9,r9,1` at 0xD5CEA4 after `stw r11` at 0xD5CE94), so
  the field consumes **len + 1** wire bytes, and the client writes its own NUL at dest+len
  (0xD5CE9C).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: result
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] Create-clan result, read at 0xD56E2C. 0 = the clan was created and
      `clan_id` follows; non-zero ends the payload here, four bytes total.

      The parser itself does not compare it against 0 — the branch that stores the clan id and the
      leader byte is downstream — but the live exchange settles the convention for this id.
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The id of the clan just created, read at 0xD56E50 into a stack slot
      (r1+116). On result 0 the client copies it to profile+6816 (0xD56E84,
      `lwz r9,116(r1)` / `stw r9,6816`) and immediately sets profile+6837 = 2, LEADER
      (0xD56E90, `li r0,2; stb r0,6837`). Present only when result == 0.
