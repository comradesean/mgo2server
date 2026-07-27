meta:
  id: mgo2_cmd_4e11_s2c
  title: "MGO2 0x4e11 — session/room list ITEMS, 47-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD5AADC**, which re-checks the id (`cmpwi r0,19985`) before reading anything.

  Items for the 0x4e10 / 0x4e11 / 0x4e12 exchange (slot 90).

  **Count source: size-driven, no count field** (0xD5CEB0 at 0xD5AB88, loop back at 0xD5AD10) —
  BUT unlike the 0x4b54/0x4b75/0x4b92 lists, records are **not appended**: the leading u2 of each
  record is used as the array INDEX (0xD5ACCC-0xD5ACF4: `cmplwi 127; bgt -> stop`, then
  `mulli x,52`), while the count at list+4 is merely incremented. So the server controls
  placement, records may arrive out of order, an index > 127 aborts the loop, and a repeated
  index silently overwrites while still bumping the count. That is a genuinely different
  count/placement model from the clan lists and is exactly the kind of thing that has bitten this
  project before — worth a server-side WARN if index >= 128 or a duplicate index appears.

  Wire record = 47 bytes; client struct = 52 (copied as 32 bytes to struct+8 and 20 bytes to
  struct+40).

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
  - id: records
    type: record
    repeat: eos
    doc: "[ELF] Size-driven; each record self-addresses via its `index` field."
types:
  record:
    doc: "47 wire bytes -> 52-byte client struct, placed at list+8+index*52."
    seq:
      - id: index
        type: u2
        doc: "[ELF] Array index for this record; must be <= 127 or the loop aborts. NOT a count. [UNKNOWN] what it indexes (slot number in the room?)."
      - id: unknown_02
        type: u4
        doc: "[ELF] [UNKNOWN]"
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] 16 bytes fixed. [UNKNOWN] whose name."
      - id: unknown_17
        type: u1
        doc: "[ELF] [UNKNOWN]"
      - id: unknown_18
        type: u1
        doc: "[ELF] [UNKNOWN]"
      - id: unknown_19
        type: u1
        doc: "[ELF] Read into the low end of the element buffer, out of order relative to its neighbours. [UNKNOWN]"
      - id: name_2
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] 16 bytes fixed. [UNKNOWN]"
      - id: unknown_2b
        type: u1
        doc: "[ELF] [UNKNOWN]"
      - id: unknown_2c
        type: s4
        doc: "[ELF] SIGNED accessor 0xD5CC64. [UNKNOWN]"
      - id: unknown_30
        type: u1
        doc: "[ELF] Last byte of the record. [UNKNOWN]"
