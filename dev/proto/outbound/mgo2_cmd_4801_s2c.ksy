meta:
  id: mgo2_cmd_4801_s2c
  title: "MGO2 0x4801 — send-mail reply with per-field error list (server -> client)"
  endian: be
doc: |
  Reply to 0x4800 (send mail / clan application). Parser 0xD53D1C (ends 0xD53F0C), dispatcher
  stub 0xD394C4. **SERVED since 2026-07-26** (`MessageGameController.sendMessage`), with
  `flags = 1`; COMMANDS.md still files it under "the rest of the mailbox", which is stale.

  PROTOCOL.md transcribes a tier-4 shape from Nomad: `{u32 status, u8 0, u32 error count, then
  name[16]+u32 code per error}`. THE ELF CONFIRMS THAT SHAPE, widths and order, and adds the
  gating condition the transcription does not mention.

  Trace. Reader opened (0xD53DA0). u32 (0xD5CC64 at 0xD53DB0) → stack. u8 (0xD5CB8C at
  0xD53DC8) → stack. Then at 0xD53DD8 the u32 is reloaded and `cmpwi 0; beq -> 0xD53E7C`:
  **the count and the record list are read ONLY when the u32 is NONZERO.** On zero the parser
  goes straight to reader-close. That is consistent with calling it a status whose nonzero value
  means "rejected, here is why", but note the polarity is the opposite of 0x4502/0x4512/0x4841,
  where zero is what carries the body.

  On the nonzero path: u32 count (0xD5CCD8 at 0xD53DF0) stored at arrayBase+0x00, then a loop
  (0xD53E04–0xD53E78) reading, per record, a 16-byte block (0xD5D018 r5=16) into
  arrayBase+4+i*17 and a u32 (0xD5CC64 at 0xD53E48) into arrayBase+548+i*4. The loop bound is the
  count word itself (lwz r0,0(r9) at 0xD53E6C, `cmplw i,count; blt`) — a LEADING COUNT field,
  not size-driven, unlike every list-triple item packet in this protocol. No cap check was seen
  in the loop, and the name table is 548 bytes → 32 slots of 17; a count above 32 overruns it.

  Finally bit 0 of the u8 selects the completion path: set → status setter 0xD32E08(0x55, 2) and
  result setter 0xD32E70(0x55, status) at 0xD53EA4/0xD53EB8; clear → 0xD53B6C instead.
doc-ref: dev/docs/PROTOCOL.md "0x4820 — get messages" (the mailbox family notes)
seq:
  - id: status
    type: u4
    doc: |
      [ELF 0xD53DB0] Nonzero → the error list below follows; ZERO → the packet ends here, 5 bytes
      total. Forwarded to the subsystem-0x55 result slot when the flag bit is set. The name
      "status" is PROTOCOL.md's tier-4 label, and the ELF's gating polarity agrees with it.
  - id: flags
    type: u1
    doc: |
      [ELF 0xD53DC8] Only bit 0 is read (`clrldi. r9,r0,63` at 0xD53E90). The other 7 bits are
      [UNKNOWN] — never examined.

      **BIT 0 MUST BE SET.** Set → `0xD32E08(0x55,2)` at 0xD53EA4 then `0xD32E70(0x55,status)` at
      0xD53EB8, i.e. the request completes with our status. **Clear → `0xD53B6C`, which is a
      packet SENDER, not a completion routine**: it builds `0x4860` (`li r4,18528` at 0xD53BFC,
      969 bytes — the same six fields as `0x4800` after two extra leading bytes preset to 1 and
      0xFF) and then `0xD32E08(ctx,85,1)` at 0xD53CE4 puts slot 0x55 back to state 1 = in-flight.
      So a zero here does not release the client; it silently re-sends the whole letter as a
      command we do not answer, and the player sees the same hang as no reply at all.

      PROTOCOL.md transcribes Nomad's `flags = 0`. That is self-consistent *for Nomad*, which also
      answers `0x4860` with a no-op `0x4861` (a bare u32; parser 0xD53064, completes slot 85) — the
      pair works, either half alone does not. This is the tier-4 trap in miniature: the value is
      transcribed correctly and is wrong here. **We send 1** [live 2026-07-26: send completes in
      one round trip].
  - id: error_count
    type: u4
    if: status != 0
    doc: |
      [ELF 0xD53DF0] LEADING COUNT — this one really is a count, unlike the start/end words of
      the list triples. It drives the loop bound directly. The client's name table holds 32
      slots (548 bytes / 17); larger values overrun it, and no bound check was found.
  - id: errors
    type: error_entry
    repeat: expr
    repeat-expr: error_count
    if: status != 0
    doc: "[ELF] 20 bytes each on the wire; count-driven, not size-driven."
types:
  error_entry:
    seq:
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[ELF 0xD53E14] 16-byte NUL-padded name → nameTable+i*17 (17 in the struct, the extra byte being the terminator 0xD5D018 writes)."
      - id: code
        type: u4
        doc: "[ELF 0xD53E48] u32 → codeTable+i*4. [UNKNOWN] which codes exist."
