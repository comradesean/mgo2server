meta:
  id: mgo2_cmd_4a29_s2c
  title: "MGO2 0x4A29 - Tournament/Survival team roster status update, eight member slots (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1). **0x4A29 is the same shape as 0x4A02** - see mgo2_cmd_4a02_s2c.ksy,
  which carries the full write-up: it updates the eight 28-byte member slots at team+0x17C of
  the TEAM record (getter 0xD491F8, session+0xD928), not the event record at session+0xDBD0.
  The post-RD_END walk is at 0xD50BE4 (`addi r29,r26,380`), instruction-for-instruction the
  same as 0x4A02's at 0xD4F0D4.

  TIER. Post-launch content; no available client build exercises 0x4A29, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  **SIZE HAZARD - THE BLOB IS 8 BYTES, NOT 128.** `mr r25,r1` / `stdu r0,120(r25)` at
  0xD50B2C-0xD50B38 leaves r25 = r1+120 and zeroes exactly 8 bytes; the loop exits at r1+128
  (`addi r0,r1,128` / `cmpw cr6` at 0xD50BCC-0xD50BD8). Eight iterations, one byte per member
  slot. **The declaration below said 128 and was CORRECTED to 8 on 2026-08-02**, after a third
  independent ELF pass confirmed this reading. Together with mgo2_cmd_4a02_s2c.ksy,
  mgo2_cmd_4a22_s2c.ksy and mgo2_cmd_4a00_s2c.ksy, which the third pass found as a fourth.

  WHAT 0x4A29 DOES NOT SHARE WITH 0x4A02 is which copy of the id it checks - see `echo_id`.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD399A0,
  parser 0xD50A90.
  READ SEQUENCE IS IDENTICAL TO 0x4A02 (parser 0xD4EF5C) field for field. They are separate
  functions with separate storage, so this is a matching shape, not a proven duplicate - no
  divergence test has been run.

  THE 128-BYTE BLOB IS READ ONE BYTE AT A TIME (loop 0xD50BB4-0xD50BD8, bound `base+128`) into a
  stack scratch buffer. No store from that buffer into the clan/session struct was traced, so
  whether the client keeps the contents at all is [UNKNOWN] - but the 128 bytes MUST be on the
  wire or everything after them desyncs.
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
    doc: "[ELF] see the identity-header note above (helper 0xD49230, read at 0xD49274)."
  - id: obj_serial
    type: u2
    doc: "[ELF] see the identity-header note above (helper 0xD49230, read at 0xD492B0)."
  - id: event_id
    type: u4
    doc: |
      [ELF] read at 0xD50B6C and compared at 0xD50B88-0xD50B90 against **event record +0x000**
      (`addis r9,r31,1` / `lwz r9,-9264(r9)` = session+0xDBD0). A mismatch aborts with **-1106**
      and NOTHING after this field is consumed. That is the id 0x4A00 stamps and 0x4A24 echoes,
      so the name is a struct-offset bijection, not a guess.
      Note the difference from 0x4A02, which reads the same value from its other home,
      team+0x298 (0xD4F050); the two are kept in step by 0x4A00 (0xD50FA8).
      **Not a result code**: compared against stored state, never sign-extended into 0xD32E70,
      and this command consumes no request slot.
  - id: unknown_after_echo
    type: u1
    doc: "[UNKNOWN] read at 0xD50BA0 -> **team record +0x004** (`addi r4,r26,4`, r26 = 0xD491F8's object). Position exact, meaning unestablished; no reader traced."
  - id: member_status
    size: 8
    doc: |
      [ELF] **8 bytes on the wire, one per team member slot** - see the size hazard in the
      top-level doc; the declared 128 is wrong and is left only because sizes are evidence.
      Byte-at-a-time loop 0xD50BB4-0xD50BE0 into r1+120..r1+127. Fixed length, no count field.
      Byte `i` is the status of member slot `i` of the eight 28-byte slots at team+0x17C:
      0 clears the slot, non-zero is stored at slot+0x15. Full semantics in
      mgo2_cmd_4a02_s2c.ksy.


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