meta:
  id: mgo2_cmd_4a22_s2c
  title: "MGO2 0x4A22 - Tournament/Survival team roster status update plus a trailing word (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1). **0x4A22 is 0x4A02's shape with one extra word on the end** - see
  mgo2_cmd_4a02_s2c.ksy for the full write-up: it updates the eight 28-byte member slots at
  team+0x17C of the TEAM record (getter 0xD491F8, session+0xD928), not the event record at
  session+0xDBD0. The post-RD_END walk is at 0xD51540 (`addi r29,r26,380`),
  instruction-for-instruction the same as 0x4A02's at 0xD4F0D4.

  TIER. Post-launch content; no available client build exercises 0x4A22, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  **SIZE HAZARD - THE BLOB IS 8 BYTES, NOT 128.** `mr r24,r1` / `stdu r0,120(r24)` at
  0xD51470-0xD5147C leaves r24 = r1+120 and zeroes exactly 8 bytes; the loop exits at r1+128
  (`addi r0,r1,128` / `cmpw cr6` at 0xD51510-0xD51518). Eight iterations, one byte per member
  slot. **The declaration below said 128 and was CORRECTED to 8 on 2026-08-02**, after a third
  independent ELF pass confirmed this reading. Together with mgo2_cmd_4a02_s2c.ksy,
  mgo2_cmd_4a29_s2c.ksy and mgo2_cmd_4a00_s2c.ksy, which the third pass found as a fourth.
  Correcting the size also moves the following `unknown_tail` to its true wire offset 19; it had
  been landing at 139, 120 bytes late, for anyone parsing to the schema.

  FOR THE RECORD, the parser at 0xD50700-0xD50A60 that rewrites the *entrant* status column is
  **0x4A01**, not this command and not 0x4A29: its only id compare is `cmpwi r0,0x4A01` at
  0xD50608. 0x4A22's is `cmpwi r0,0x4A22` at 0xD51454.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD398E0,
  parser 0xD513D0.
  Same shape as 0x4A02/0x4A29 with one extra u32 AFTER the blob. The 128-byte blob is read
  one byte at a time (0xD514F8-0xD51518, bound base+128) into a stack scratch buffer.
  LEADING IDENTITY HEADER (6 bytes), read by the shared helper 0xD49230 and therefore easy to
  miss when reading this parser alone: u32 then u16. Both are validated against the client's
  currently open object for this subsystem (u32 vs obj+0x000 at 0xD4929C, u16 vs obj+0x29C at
  0xD492D4); a mismatch aborts with -1018 (0xFFFFFC06) before another byte is consumed. For
  command id 0x4960 only, 0xD49230 skips both comparisons and just consumes the six bytes.
  Modelled below as `obj_id` + `obj_serial`; the names describe the check, not a proven meaning.
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
  - id: obj_id
    type: u4
    doc: "[ELF] identity header, helper 0xD49230."
  - id: obj_serial
    type: u2
    doc: "[ELF] identity header, helper 0xD49230."
  - id: event_id
    type: u4
    doc: "[ELF] read at 0xD514B0, compared at 0xD514D0 against **event record +0x000** (equivalently team+0x298; 0x4A00 keeps the two in step at 0xD50FA8). Mismatch aborts with -1106 and nothing further is read. Same id as 0x4A24's `obj_id`. **Not a result code**: compared against stored state, never sign-extended into 0xD32E70, and this command consumes no request slot."
  - id: unknown_after_echo
    type: u1
    doc: "[UNKNOWN] read at 0xD514E4 -> **team record +0x004** (`addi r4,r26,4`, r26 = 0xD491F8's object). No reader traced."
  - id: member_status
    size: 8
    doc: |
      [ELF] **8 bytes on the wire, one per team member slot** - see the size hazard in the
      top-level doc; the declared 128 is wrong and is left only because sizes are evidence.
      Byte-at-a-time loop 0xD514F4-0xD51520 into r1+120..r1+127. Byte `i` is the status of
      member slot `i` of the eight 28-byte slots at team+0x17C: 0 clears the slot, non-zero is
      stored at slot+0x15. Full semantics in mgo2_cmd_4a02_s2c.ksy.

      **CORRECTED 2026-08-02 from 128 to 8**, by a third independent ELF pass that adjudicated
      the disagreement between the two earlier readings. The cause was one letter: the store is
      **`stdu`**, not `std` -- DS-form with the low two bits `01`, the update form, which rewrites
      the base register. `mr rX,r1` then `stdu r0,120(rX)` leaves rX = **r1+120**, so the loop's
      exit test `addi r0,r1,128` is an **end ADDRESS, not a byte count**: the cursor runs
      r1+120..r1+128 exclusive. Eight iterations, eight wire bytes, one per 28-byte member slot.

      Corroborated independently by the post-read walk (`addi r0,r1,120` / `add r0,r28,r0` /
      `lbz`, bounded `cmpwi cr7,r28,7`), which puts byte *i* at r1+120+i for i in 0..7.

      **The control that diagnoses the error is `0x4A27`**, whose declared 8 was always right: it
      uses a plain `std r0,112(r1)` with no update, and forms its cursor explicitly with
      `addi r29,r1,112`. Where the base was written out, the earlier pass read it correctly. So
      the failure was not tracking a register mutated by an update-form store, which silently
      turns an end-address into a length -- and the 120-byte error is exactly the base
      displacement.

      The class is closed, not merely fixed: a sweep of the whole parser block 0xD33000-0xD5D000
      for `stdu rX,disp(rY)` with `rY != r1` -- the only encoding that can silently rebase a
      scratch buffer -- returns exactly four sites, `0x4A00`, `0x4A02`, `0x4A22`, `0x4A29`. The
      complementary plain-`std` set contains `0x4A27`, so the sweep discriminates. No other
      schema can carry this error.
  - id: unknown_tail
    type: u4
    doc: "[UNKNOWN] read at 0xD5152C (-> r1+116) after the status bytes - the one field 0x4A02 and 0x4A29 do not have. It is read into a stack slot that the post-RD_END walk never touches, so it is parsed and discarded within this function; no consumer traced. Position exact, meaning unestablished."
