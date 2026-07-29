meta:
  id: mgo2_cmd_4b47_s2c
  title: "MGO2 0x4b47 — clan record refresh, 28 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md).

  **The character's own clan record.** The reply to 0x4b46, a bare probe with no payload.
  [CONFIRMED LIVE 2026-07-27] — every field below is populated and rendered.

  The clan record is one struct the client keeps at a fixed place in its profile, and two commands
  fill it: 0x4122 carries it inside the connect burst, and this one replaces it on demand. Both
  write the same five fields, which is how the layout is known.

  **0x4b46 BLOCKS, despite what was recorded.** The inbound spec
  `dev/proto/inbound/mgo2_cmd_4b46_c2s.ksy` says "the live trace proves the client does not
  wait for one" and warns against replying speculatively. That is true of the connect burst, where
  0x4b46 fires unprompted and the player walks on. From the **clan menu** it stalls and fails with
  "Unable to update clan information (1933:FFFFFF60)", observed live 2026-07-27. One command, two
  contexts, and only one of them had ever been tested. The sender 0xD58510 advances flow state via
  0xD32E08(session, 98, 1) either way, so the difference is in what the screen does next, not in
  the request.

  **"No clan" is a record, not a failure.** A non-zero result ends the payload after four bytes
  (0xD5835C reads no further), which leaves the client's existing record in place rather than
  correcting it. Send result 0 with `state = 99`.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5835C**, which re-checks the id (`cmpwi r0,19271`) before reading anything.

  Closes pending-request slot **98**. When result == 0 the fields are copied into the object
  returned by 0xD3A094 at +6816 (u4), +6837 (u1), +6838 (u2), +6872 (u1) and +6820 (the 17-byte
  NUL-terminated name), via `lswi/stswi` at 0xD584B4. When result != 0 only the 4-byte result is
  read. Wire size on success: **28 bytes**.

  NOTE the wire order is NOT the struct order — the u2 is read before the second u1 even though
  it lands at a higher offset. Order below is the read order, which is what matters on the wire.

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 / 0xD5CCD8 u4 (identical twins — see the CORRECTION below), 0xD5D018 fixed byte
  block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. An earlier revision
  added: "In each signed/unsigned pair the LOWER address is the signed accessor (write-side
  proof: 0xD5C95C uses `sraw`, 0xD5C9BC uses `srw`)." **That claim is SUPERSEDED — see the
  CORRECTION below.** Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare at every width): that rule is wrong,
  and it is wrong on the READ side at ALL widths, not just at u32. Each "signed/unsigned pair"
  is instruction-for-instruction identical — same bound check, same byte-assembly loop, same
  `extsb` on each byte, same store width:
    * u8:  0xD5CB54 == 0xD5CB8C  (bound `cmpwi 1023`, `lbzx`/`stb`, cursor += 1)
    * u16: 0xD5CBC4 == 0xD5CC14  (bound `cmpwi 1022`, two `lbzx`, `sth`,  cursor += 2)
    * u32: 0xD5CC64 == 0xD5CCD8  (bound `cmpwi 1020`, 4-iteration loop, `stw`, cursor += 4)
    * u64: 0xD5CD4C == 0xD5CDC0  (bound `cmpwi 1016`, 8-iteration loop, `std`, cursor += 8)
  So **no read primitive is a signed accessor at any width**, and "0xD5CBC4 s2" / "0xD5CC64 s4"
  are as unfounded as the u32 claim. Signedness comes from the CALLER — the value being
  reloaded with `lwa`, or being compared against known-negative error constants — never from
  the primitive's address.

  The write side does not rescue the rule either. There are **three** u32 write primitives, not
  a signed/unsigned pair: 0xD5C95C (`sraw`), 0xD5C9BC (`srw`) and 0xD5CA1C (`sraw`). The
  sraw/srw difference is inert because each iteration masks with `and r0,r4,r0` where r0 =
  `slw r7,r10` of 255, and then stores only the low byte with `stbx`: for shifts 16/8/0 the
  masked operand is non-negative in 32 bits so the two shifts agree outright, and for shift 24
  they differ only in bits above bit 7, which `stbx` discards. Identical bytes on the wire.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

seq:
  - id: result
    type: s4
    doc: |
      [CONFIRMED 2026-07-27] 0 = success, body follows. Published to request slot 98.
      **Always send 0**, even when the character has no clan — see the top-level doc.
  - id: clan_id
    type: u4
    doc: "[CONFIRMED 2026-07-27] The character's clan id, 0 when they have none. -> profile+6816."
  - id: state
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] Membership state -> profile+6837:
      **0 pending, 1 member, 2 leader, 99 none.** Same encoding as 0x4b21's T+0x15.

      State 2 alone is what unlocks committing an emblem: 0xAD409C tests ctx+788 & 4, and that bit
      is set purely from this byte being 2.
  - id: privileges
    type: u2
    doc: |
      [CONFIRMED 2026-07-27] The clan privilege / notification word -> profile+6838.
      **Send ZERO.**

      [EXPERIMENT 2026-07-27, both halves live] Granting a leader all sixteen bits put a saluting-
      soldier "!" badge on the clan and sent the client into a hard poll loop, re-sending 0x4b46
      about every 73ms. The clan screen's coroutine stalls on any bit it does not tolerate:
      0xAB0074 ands this word with -1, or with -257 when the player is the leader (0xAB004C), and
      returns WITHOUT advancing its state machine if anything survives. -257 is ~0x0100, so bit 8
      is the one bit a leader may hold without the screen re-entering forever; every other bit
      stalls, and a non-leader tolerates nothing.

      **Bit 8 on its own was then tried and is NOT emblem-editing rights.** It behaved exactly as
      the tolerance mask predicts — no stall, no poll loop — but it produced only the "!" badge and
      no new menu row anywhere, and emblem loading worked with or without it. So bit 8 is a
      PENDING-NOTIFICATION bit, the whole word is a notification mask the client drains to zero
      rather than a permission mask, and **no privilege bit gates applying an emblem**. That is
      keyed off `state == 2` alone (0xAD409C, ctx+788 & 4), and who may edit the emblem is carried
      as a character id at 0x4b21's T+0x6FC.

      The narrow lesson, per dev/docs/OBSERVED.md: do not turn on unknown bits in bulk.
  - id: emblem_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] -> profile+6872. **3 when the clan has a published emblem**, 0
      otherwise — the same encoding as 0x4b21's T+0x378 and as the mode byte 0x4b50 uploads with.
  - id: name
    size: 16
    type: str
    encoding: ASCII
    doc: "[CONFIRMED 2026-07-27] The CLAN's name, 16 bytes fixed -> profile+6820 (copied as 17 bytes; the client appends its own NUL)."
