meta:
  id: mgo2_cmd_4a02_s2c
  title: "MGO2 0x4A02 - Tournament/Survival team roster status update, eight member slots (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL. The 0x4Axx block is the Tournament / Survival subsystem, settled
  2026-08-02 (tier 1). **0x4A02 updates the eight member slots of the player's TEAM record** -
  the object behind getter 0xD491F8 at session+0xD928, *not* the event record at
  session+0xDBD0. Keep the two apart: they are adjacent (0xD928 + 0x2A8 = 0xDBD0) and the same
  shape of mistake produced this project's team-vs-clan misidentification.

  TIER. Post-launch content; no available client build exercises 0x4A02, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  WHAT THE PARSER DOES AFTER RD_END (0xD4F0D4-0xD4F174), which is what names the blob. It walks
  **eight 28-byte slots starting at team+0x17C** and, for slot `i`:
    * skips the slot if its leading u32 (the member id) is 0;
    * remembers `i` if that id equals the local player's own id (`lwz r0,0(r21)`);
    * takes **byte `i` of the blob**: if the byte is 0 it `memset`s the whole 28-byte slot to
      zero - i.e. **0 removes the member**; otherwise it stores the byte at **slot+0x15**, the
      member's status byte.
  Then, if the local player's own slot was found, it fires **event 20** with `slot+0x11` as the
  payload (0xD4F150-0xD4F170); if it was not found the whole command fails with **-1007**.
  So a server must include the recipient in the roster or the update is rejected outright.

  **SIZE HAZARD - THE BLOB IS 8 BYTES, NOT 128.** The loop cursor is initialised by
  `mr r23,r1` / `stdu r0,120(r23)` (0xD4F000-0xD4F00C), which leaves r23 = r1+120, and the
  loop exits when the cursor reaches **r1+128** (`addi r0,r1,128` / `cmpw cr6` at
  0xD4F09C-0xD4F0B0). Eight iterations, eight bytes, one per member slot - and the `stdu`
  zeroing exactly 8 bytes corroborates it. **The declaration below said 128 and was CORRECTED
  to 8 on 2026-08-02**, after a third independent ELF pass adjudicated the disagreement and
  confirmed this reading. The same error was in mgo2_cmd_4a22_s2c.ksy, mgo2_cmd_4a29_s2c.ksy
  and -- found only by the third pass -- mgo2_cmd_4a00_s2c.ksy, all now corrected.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39860,
  parser 0xD4EF5C.
  READ SEQUENCE IS IDENTICAL TO 0x4A29 (parser 0xD50A90) field for field. They are separate
  functions with separate storage, so this is a matching shape, not a proven duplicate - no
  divergence test has been run.

  THE 128-BYTE BLOB IS READ ONE BYTE AT A TIME (loop 0xD4F084-0xD4F0A8, bound `base+128`) into a
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
  - id: echo_id
    type: u4
    doc: |
      [ELF] read at 0xD4F040 and compared against a u32 the client already holds
      (obj+0x298 in the 0x4A02 path, 0xD4F050). A mismatch aborts the parse with -1106
      (0xFFFFFBAE) and NOTHING after this field is consumed. So the server must echo back the
      same id it delivered in the earlier packet of this exchange. [UNKNOWN] which id that is.
  - id: unknown_after_echo
    type: u1
    doc: "[UNKNOWN] read at 0xD4F070 -> **team record +0x004** (`addi r4,r26,4`, r26 = 0xD491F8's object). Position exact, meaning unestablished; no reader traced. Note this is the team record's +0x004, not the event record's flags byte at the same displacement - different object."
  - id: member_status
    size: 8
    doc: |
      [ELF] **8 bytes on the wire, one per team member slot** - see the size hazard in the
      top-level doc; the declared 128 is wrong and is left only because sizes are evidence.
      Byte-at-a-time loop 0xD4F084-0xD4F0B0 into r1+120..r1+127. Fixed length, no count field.
      Byte `i` is the status of member slot `i` of the eight 28-byte slots at team+0x17C:
      **0 clears the slot** (`memset(slot,0,28)` at 0xD4F124), non-zero is stored at slot+0x15.


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