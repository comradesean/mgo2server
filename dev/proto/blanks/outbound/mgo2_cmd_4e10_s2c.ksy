meta:
  id: mgo2_cmd_4e10_s2c
  title: "MGO2 0x4e10 — session/room state push, 236 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5AD5C**, which re-checks the id (`cmpwi r0,19984`) before reading anything.

  Sets pending-request slot **90** to state **1** (not 2) — i.e. this packet OPENS a request
  rather than closing one — and then immediately builds and sends **0x4E00** back to the server
  (`li r4,19968` into builder 0xD5CF40 at 0xD5B0CC). So a server that sends 0x4e10 must be ready
  to answer 0x4e00; the pair 0x4e11 (items) / 0x4e12 (end, same slot 90) completes the exchange.

  Bulk of the payload is a **204-byte settings block** read by the shared sub-parser
  **0xD4364C**, whose own read sequence was disassembled: a 16-iteration loop of three u1 reads
  (48 bytes, three parallel 16-byte arrays at dest+0/+16/+32), then u1,u1,bytes[16],u1,u1, three
  u4, two u2, two u4, u2, u1,u1, then 18 u4, bytes[2], u2, u4, u1, bytes[2], u1, u2, u2, u4, u1,
  u1, bytes[14] — 204 bytes total, ending at dest+204. That block is NOT expanded here: its
  canonical model is `mgo2_cmd_4313_s2c.ksy`, type `game_settings`, whose field names are
  backed by live capture of the `0x4310` push and the `0x4305` reply (OBSERVED.md).
  `0xD4364C` has nine call sites — `0xD445A4` (0x4313), `0xD48440` (0x4905), `0xD48964`
  (0x4909), `0xD4B244` (0x4987), `0xD4CB08` (0x4950), `0xD5006C` (0x4A24/0x4A31), `0xD51014`
  (0x4A00), `0xD5AF38` (here), `0xD5B78C` (0x43F1). Whether the game-settings semantics carry
  over to a 0x4E10 record is [UNKNOWN]; the byte boundaries are not.

  Wire size: 4 + 2 + 1 + 1 + 204 + 4 + 5*4 = **236 bytes**.

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
  - id: unknown_00
    type: u4
    doc: "[ELF] Read to a stack slot; not obviously validated. [UNKNOWN]"
  - id: unknown_04
    type: u2
    doc: "[ELF] [UNKNOWN]"
  - id: flags_byte
    size: 1
    doc: |
      [ELF] Read as a 1-byte block, then all 8 bits are expanded into a 64-bit flag word at
      ctx+0x00 (0xD5AE4C-0xD5AF0C): bit0 -> 0x80000000, bit1 -> 0x40000000, bit2 -> 0x20000000,
      bit3 -> 0x10000000, bit4 -> 0x08000000, bit5 -> 0x04000000, bit6 -> 0x02000000,
      bit7 (sign) -> 0x01000000. All eight bits are used — unlike 0x4b21's flags byte, which uses
      three. [UNKNOWN] meanings.
  - id: unknown_07
    type: u1
    doc: "[ELF] -> ctx+0x05. [UNKNOWN]"
  - id: settings_block
    size: 204
    doc: |
      [ELF] 204 bytes consumed by the shared reader 0xD4364C into ctx+0x08. Layout modelled
      canonically in `mgo2_cmd_4313_s2c.ksy`, type `game_settings`; kept opaque here so the
      copies cannot drift. The byte boundaries are [ELF]; whether the game-settings *meanings*
      apply to a 0x4E10 record is [UNKNOWN].
  - id: unknown_d4
    type: u4
    doc: "[ELF] -> ctx+7268. [UNKNOWN]"
  - id: unknown_d8
    type: s4
    doc: "[ELF] -> ctx+7272. SIGNED accessor. [UNKNOWN]"
  - id: unknown_dc
    type: s4
    doc: "[ELF] -> ctx+7276. SIGNED. [UNKNOWN]"
  - id: unknown_e0
    type: s4
    doc: "[ELF] -> ctx+7280. SIGNED. [UNKNOWN]"
  - id: unknown_e4
    type: s4
    doc: "[ELF] -> ctx+7284. SIGNED. [UNKNOWN]"
  - id: unknown_e8
    type: s4
    doc: "[ELF] -> ctx+7288, last 4 bytes. SIGNED. The five consecutive signed words look like a score/counter row. [UNKNOWN]"
