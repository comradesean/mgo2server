meta:
  id: mgo2_cmd_4b21_s2c
  title: "MGO2 0x4b21 — clan/GHQ profile block, 777 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD587AC**, which re-checks the id (`cmpwi r0,19233`) before reading anything.

  Preconditions the parser enforces before it will parse: pending-request slot **99** must be in
  state 1 (getter 0xD32E3C at 0xD587F8-0xD58818) and, if the session already holds a clan
  context, the `subject_id` field below must equal the stored one at
  session[+0x10000+6404]+0x20000+27904, else the packet is dropped with no error.

  Destination struct: T = session + 0x10000 - 1968, memset to 0 over 6968 (0x1B38) bytes before
  the reads (0xD588A8). Destination offsets are given per field as T+0x...; they are NOT wire
  offsets. The same struct is partially rewritten by 0x4b81 (parser 0xD58C74) — see
  mgo2_cmd_4b81.ksy.

  Wire size when result == 0: **777 bytes**. When result != 0 the parser jumps straight to
  end-read (0xD58C04), so an error reply is 4 bytes.

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
    doc: "[ELF] 0 = success and the body follows; non-zero = 4-byte reply, body absent. Published to request slot 99."
  - id: subject_id
    type: u4
    doc: "[ELF] T+0x00. Cross-checked against the session's stored clan id; mismatch drops the packet. [UNKNOWN] whether this is a clan id or a member id."
  - id: name_a
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x04, 16 bytes fixed, client NUL-terminates at T+0x14. [UNKNOWN] which name."
  - id: unknown_15
    type: u1
    doc: "[ELF] T+0x15. [UNKNOWN]"
  - id: unknown_18
    type: u4
    doc: "[ELF] T+0x18. [UNKNOWN]"
  - id: name_b
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x1c, 16 bytes fixed. [UNKNOWN] which name."
  - id: unknown_30
    type: u4
    doc: "[ELF] T+0x30. [UNKNOWN]"
  - id: name_c
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x34, 16 bytes fixed. [UNKNOWN] which name."
  - id: unknown_48
    type: u4
    doc: "[ELF] Read as u4 into a stack slot then stored with `std` into T+0x48 as a 64-bit word (0xD5899C). Only 4 bytes are on the wire. [UNKNOWN]"
  - id: unknown_58
    type: u4
    doc: "[ELF] T+0x58. [UNKNOWN]"
  - id: unknown_5c
    type: u4
    doc: "[ELF] T+0x5c. [UNKNOWN]"
  - id: unknown_60
    type: u4
    doc: "[ELF] T+0x60. [UNKNOWN]"
  - id: unknown_64
    type: u4
    doc: "[ELF] T+0x64. [UNKNOWN]"
  - id: unknown_68
    type: u4
    doc: "[ELF] T+0x68. [UNKNOWN]"
  - id: unknown_6c
    type: u4
    doc: "[ELF] T+0x6c. [UNKNOWN]"
  - id: flags_word
    type: u4
    doc: "[ELF] T+0x70. A bitfield: the `flags_byte` below is merged into this same word, so the server must not treat the two as independent. [UNKNOWN] bit meanings."
  - id: unknown_74
    type: u1
    doc: "[ELF] T+0x74. [UNKNOWN]"
  - id: flags_byte
    size: 1
    doc: |
      [ELF] Read as a 1-byte block (0xD58A80), then three bits are OR-ed into the 64-bit word at
      T+0x70 (0xD58A90-0xD58AD8): bit0 -> 0x00800000, bit1 -> 0x00400000, bit2 -> 0x00010000.
      Bits 3..7 are read and discarded. [UNKNOWN] meanings.
  - id: unknown_76
    type: u1
    doc: "[ELF] T+0x76. [UNKNOWN]"
  - id: unknown_378
    type: u1
    doc: "[ELF] T+0x378 — a long way from its neighbours, so this lands in a different sub-struct. [UNKNOWN]"
  - id: text_67a
    size: 128
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x67A, 128 bytes fixed. Size and position fit a motto/announcement string. [UNKNOWN]"
  - id: unknown_6fc
    type: u4
    doc: "[ELF] T+0x6FC. [UNKNOWN]"
  - id: blob_700
    size: 512
    doc: "[ELF] T+0x700, 512 bytes fixed, read with 0xD5D018 so the client NUL-terminates at T+0x900. Largest single field in the packet. [UNKNOWN] — could be a long text block or a packed table; nothing in the parser interprets it."
  - id: unknown_904
    type: u4
    doc: "[ELF] read to a stack slot then `stw` to T+0x904 (0xD58B9C). [UNKNOWN]"
  - id: name_d
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x908, 16 bytes fixed. [UNKNOWN]"
  - id: unknown_1b2c
    type: u4
    doc: "[ELF] T+0x1B2C. [UNKNOWN]"
  - id: unknown_1b30
    type: u4
    doc: "[ELF] T+0x1B30. [UNKNOWN]"
  - id: unknown_1b34
    type: u4
    doc: "[ELF] T+0x1B34, last 4 bytes of the payload. [UNKNOWN]"
