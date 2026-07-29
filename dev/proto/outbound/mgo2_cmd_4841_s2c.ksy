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

  The 708 bytes are opaque here — the parser stores them verbatim with no internal structure,
  so any field layout must come from whatever reads ctx-8296 later, which was not traced.
doc-ref: dev/docs/PROTOCOL.md "0x4820 — get messages" (mailbox family notes)
seq:
  - id: result
    type: u4
    doc: |
      [ELF 0xD5360C] Stored into the subsystem-0x55 result slot. ZERO makes the client read the
      708-byte body; nonzero skips it and completes the transaction with the value.
  - id: unknown_body
    size: 708
    if: result == 0
    doc: |
      [UNKNOWN] 708 bytes (0x2C4), read as one opaque block by 0xD5D018 (r5=708 at 0xD5363C) and
      memcpy-equivalent-stored at the mailbox object. No internal fields are parsed here; the
      consumers of that object were not traced, so nothing about its layout is established.

      WHAT WE SEND (2026-07-26): the letter's body text, NUL-padded to 708. The reasoning is that
      the `0x4800` send carries a 708-byte body field of exactly this width, capture-confirmed to
      hold the operator's typed message, so a round trip of the same block is the likeliest shape.
      That is [INFERRED] and is the first assumption to attack if the reading screen renders
      wrongly — the block may well have a header the send side fills from elsewhere.

      A short reply is the dangerous failure: 0xD5D018 bound-checks against the 1023-byte receive
      buffer, not the payload length, so fewer than 708 bytes copies stale buffer into the mail
      object and reports success.
      Almost certainly the mail body/header record, but that is [INFERRED] from the id alone.
