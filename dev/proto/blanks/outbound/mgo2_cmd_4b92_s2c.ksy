meta:
  id: mgo2_cmd_4b92_s2c
  title: "MGO2 0x4b92 — clan/GHQ list ITEMS, 44-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD55B04**, which re-checks the id (`cmpwi r0,19346`) before reading anything.

  Middle packet of the 0x4b91 / 0x4b92 / 0x4b93 triple (see mgo2_cmd_4b91.ksy). No request-slot
  update. Additional precondition: the list object pointer session[+0x10000+6404] must be
  non-NULL and its first word non-zero — i.e. **0x4b91 must have armed the gate first**, or this
  packet is rejected with -73.

  **Count source: size-driven, no count field** (0xD5CEB0 at 0xD55BB0, loop back at 0xD55C90).
  Records appended at list+16+n*60 with the count at list+4; refused at n > 99, so at most
  **100** records. List object: session[+0x10000+6404] + 0x20000 + 10344.

  Wire record = 44 bytes; client struct = 60 (copied as 32 + 28 bytes by the `lswi/stswi` pair at
  0xD55C78).

  The paired REQUEST builder sits right after this parser at 0xD55CE4 and emits **0x4b90**
  (`li r4,19344` at 0xD55D94) with {u8, u8, bytes[16]}, then sets slot 114 to state 1 — that is
  the client->server side of this triple, recorded here because it is the only place it appears.

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
seq:
  - id: records
    type: record
    repeat: eos
    doc: "[ELF] Size-driven; no leading count."
types:
  record:
    doc: "44 wire bytes -> 60-byte client struct."
    seq:
      - id: unknown_00
        type: u4
        doc: "[ELF] struct+0x00. [UNKNOWN]"
      - id: name_a
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x04, 16 bytes fixed. [UNKNOWN]"
      - id: unknown_18
        type: u4
        doc: "[ELF] struct+0x18. [UNKNOWN]"
      - id: name_b
        size: 16
        type: str
        encoding: ASCII
        doc: "[ELF] struct+0x1c, 16 bytes fixed. [UNKNOWN]"
      - id: unknown_30
        type: u4
        doc: "[ELF] struct+0x30, last 4 bytes of the record. [UNKNOWN]"
