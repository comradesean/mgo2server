meta:
  id: mgo2_cmd_4b72_s2c
  title: "MGO2 0x4b72 — clan stat blocks, 580 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD58F3C**, which re-checks the id (`cmpwi r0,19314`) before reading anything.

  Closes pending-request slot **111**. Body present only when result == 0.

  Structure recovered from 0xD59068-0xD5988C: **two** iterations of a body containing exactly
  **72 u4 reads**, contiguous in the destination (verified by emulating the address arithmetic:
  session+0x10000+4404 .. +4688 in steps of 4). The loop counter starts at 2 and exits when the
  pre-increment value is 3 (0xD59834), so the count is a hard 2 — nothing on the wire selects it.
  Between iterations every destination pointer advances by **292** = 72*4 + 4, so each block has
  a 4-byte client-side field that is NOT on the wire.

  Wire size: 4 + 2 * 72 * 4 = **580 bytes**. Destination base is memset over 1168 bytes = 4 * 292
  (0xD58FF8), i.e. four block slots exist but only two are filled here — plausibly the same
  page-pairing as 0x4b71 (personal 0/1, clan 2/3), which is [INFERRED], not read.

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
  - id: result
    type: s4
    doc: "[ELF] 0 = success, blocks follow; non-zero = 4-byte reply. Published to request slot 111."
  - id: blocks
    type: block
    repeat: expr
    repeat-expr: 2
    doc: "[ELF] Exactly 2, from the unrolled loop bound at 0xD59834. No count on the wire."
types:
  block:
    doc: "[ELF] 72 u4 = 288 wire bytes; client stride 292 (one 4-byte non-wire field per block)."
    seq:
      - id: values
        type: u4
        repeat: expr
        repeat-expr: 72
        doc: "[UNKNOWN] All 72. The parser only stores them; nothing in it reveals meaning. 72 is not 18*4, so this is not a second copy of the 0x4b71 / 0x4105 grid."
