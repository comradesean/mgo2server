meta:
  id: mgo2_cmd_4841_s2c
  title: "MGO2 0x4841 — mail contents reply, result + 708-byte blob (server -> client)"
  endian: be
doc: |
  Reply to 0x4840 (get mail contents). Parser 0xD53598 (ends 0xD536A8), dispatcher stub
  0xD39524. **SERVED since 2026-07-26** (`MessageGameController.readMessage`); COMMANDS.md still
  files it under "the rest of the mailbox", which is stale.

  FINDING — THIS IS NOT AN EMPTY ACK. PROTOCOL.md notes that Nomad answers 0x4840 with
  "command 0x4341, empty — almost certainly a Nomad typo for 0x4841; do not copy it". The
  correction is right about the id and understates the problem about the body: the parser reads a
  **708-byte (0x2C4) block after the result word, and it reads it exactly when the result is
  ZERO**.

  Trace: reader open 0xD5C844 (0xD535FC); u32 0xD5CC64 → stack (0xD5360C); then at 0xD53628 the
  value is reloaded and `cmpwi 0; bne -> 0xD5364C` skips the blob. On the zero path,
  0xD5D018 with r5 = 708 (0xD5363C) copies 708 bytes into the mailbox object at
  ctx+0x2xxxx (`addis r9,r29,2; addi r4,r9,-8296`), NUL-terminating at +708. Reader close, then
  status setter 0xD32E08(0x55, 2) and result setter 0xD32E70(0x55, result).

  WHY A BARE `{u32 0}` IS WORSE THAN AN ERROR. As mgo2_cmd_4902.ksy documents for the same
  primitive family, 0xD5D018 bound-checks the cursor against the 1023-byte packet BUFFER, not
  against the payload length: a 4-byte 0x4841 does not fail, it copies 708 bytes of stale buffer
  into the mail object and reports success. If this id is ever implemented, either send
  4 + 708 = 712 bytes, or send a NONZERO result so the read is skipped.

  ## RESOLVED 2026-07-31 (batch 3c) — the destination is the compose buffer's body slot

  `ctx-8296` was traced, and it is not a new object. `r29 = *(session+6404)` at `0xd535f8` and the
  destination is `r29 + 0x20000 - 8296` (`addis r9,r29,2; addi r4,r9,-8296` at `0xd53620`/
  `0xd5362c`). The `0x4800` send builder computes its `body` source the identical way — `r29 =
  *(session+6404)` at `0xd53f80`, `addis r29,r29,2` at `0xd53f8c`, `addi r4,r29,-8296` at
  `0xd53fe4`, `li r5,708`. **Same session field, same displacement, same width: one address.**

  That address is the mail module's "current letter" object, whose shape is fully readable from
  `0xd342a4` (`ClearComposeLetter`) and `0xd34220` (`ClearMailRecord`):

  ```
  base = *(session+6404) + 0x20000 - 8584
    +0    u8    category selector, -1 = none
    +8    ----  a 280-byte MAIL RECORD, identical in layout to a 0x4822 entry
                (+8 == B-8576; see ../outbound/mgo2_cmd_4822_s2c.ksy)
    +288  ----  709 bytes: this packet's 708-byte block, plus the NUL the parser writes
  ```

  So the block is not opaque and it has no header: `0x8e8afc`, the OPENmail (read-a-letter)
  screen, sets `r16 = base+288` at `0x8e8d68` and word-wraps it from **byte 0** into the twelve
  `NULL_OPENmail_01`..`_12` line elements (hashes built at `0x8e8f30`-`0x8e8fe4`, body walk from
  `0x8e90b4`). The same screen renders the record beside it — `+1` recipient count, `+2` name,
  `+131` subject, `+264` time.

  `0xd342a4` clears 709 bytes here, which is where the NUL-terminator byte lives.
doc-ref: dev/docs/PROTOCOL.md "0x4820 — get messages" (mailbox family notes)
seq:
  - id: result
    type: u4
    doc: |
      [ELF 0xD5360C] Stored into the subsystem-0x55 result slot. ZERO makes the client read the
      708-byte body; nonzero skips it and completes the transaction with the value.
  - id: body_text
    size: 708
    if: result == 0
    doc: |
      [ELF 2026-07-31, batch 3c] **The letter's body text, NUL-padded to 708** — plain text with no
      header and no internal structure. Was `unknown_body`, [UNKNOWN].

      Read as one block by 0xD5D018 (r5=708 at 0xD5363C) into `*(session+6404) + 0x20000 - 8296`,
      which is **byte-for-byte the same address the 0x4800 send reads its `body` field from**
      (0xD53FE4, r5=708, same session field and displacement). It is the `+288` slot of the mail
      module's current-letter object; see the header for the full struct.

      Two independent readers confirm it is text starting at byte 0:
      * the OPENmail screen (`0x8e8afc`) takes `base+288` at `0x8e8d68` and word-wraps from offset
        0 into the twelve `NULL_OPENmail_01`..`_12` line elements;
      * `0x8eeb00` copies the compose screen's editor buffer (`screen+14130`) into it, and
        `0x8eec3c` whitespace-validates all 708 bytes before allowing a send.

      **This retires the caveat this field used to carry.** WHAT WE SEND (the letter's body text,
      NUL-padded to 708) was recorded as [INFERRED] from the width alone, with "the block may well
      have a header the send side fills from elsewhere" flagged as the first thing to attack.
      There is no header: the render starts at byte 0. What we send is right.

      A short reply is still the dangerous failure: 0xD5D018 bound-checks against the 1023-byte
      receive buffer, not the payload length, so fewer than 708 bytes copies stale buffer into the
      mail object and reports success.
