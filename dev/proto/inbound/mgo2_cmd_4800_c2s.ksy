meta:
  id: mgo2_cmd_4800_c2s
  title: "MGO2 0x4800 — send mail (client -> server)"
  endian: be
doc: |
  Sender `0xD53F10`, builder call `0xD53F98`, subsystem index `0x55` (`li r4,85` at `0xD54040`).
  Every field is copied out of the mailbox compose buffer, a struct reached as
  `base = *(u32*)(ctx+0x1904) + 0x20000`; the source offsets below are relative to that `base`
  and are struct offsets only — the wire is strictly sequential.

  `0x4860` (see `mgo2_cmd_4860.ksy`) writes the **same six fields** after two extra leading bytes,
  from the same struct: 967 bytes here, 969 there.

  PROTOCOL.md's `0x4800` note is tier-4 only (Nomad implements it as clan applications).
  Total payload: 967 bytes.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26.

  ## CAPTURE-CONFIRMED 2026-07-26 — the three big fields are recipient / subject / body

  A live `BLUS30109` client composed a letter with recipient `poop`, subject `hi`, body `poop`
  and pressed send. The server logged the whole payload (`No handler for command 4800`, the
  automatching lobby). It is **967 bytes**, matching this spec's ELF-derived figure exactly, and
  the three operator-typed strings land on the three previously-[UNKNOWN] blocks with no
  ambiguity: `poop` at `0x001`, `hi` at `0x081`, `poop` at `0x101`. Distinct values in three
  distinct fields in one shot — the fingerprint pass this doc asked for, done accidentally.

  This is the first live capture to validate one of the generated blank specs. Field order,
  widths and total size were derived from the disassembly before any capture existed and were
  correct on every count.

  **Two of those three are now resolved (2026-07-29), by doing exactly what this paragraph asked
  for — varying the recipient count.** A letter To -> GM produced count **0** with all eight name
  slots zeroed and `3` in the first trailing byte, against the earlier capture's count `1`, one
  filled slot and `0`. So the leading u8 is the **recipient count** and the byte at `0x3c5` is the
  **destination class**. The second trailing byte at `0x3c6` remains [UNKNOWN] and has no writer
  anywhere in the compose screen.

  Worth keeping as method: a single capture could not separate constant from variable here, and the
  thing that separated them was one deliberately different send, not more staring at the same
  bytes.

  ## THE SOURCE STRUCT IS A MAIL RECORD (2026-07-31, batch 3c)

  Every field below is at a **mail-record** offset, the same struct `0x4822` entries are parsed
  into. `0xD34728` `MailRecordCopy(dst, src)` copies exactly `+0`, `+1`, `+2`(128), `+131`(128),
  `+264`(8), `+272`, `+273`, `+274`; `0xD5415C` calls it with `dst = base-8576` when a letter is
  opened. `0xD342A4` clears the whole thing:

  ```
  base - 8584                                      (0xd342a4 ClearComposeLetter)
    +0    u8    category selector, -1 = none
    +8    ----  a 280-byte MAIL RECORD == base-8576, the offsets used below
    +288  ----  709 bytes at base-8296: `body`, and the 708 bytes 0x4841 delivers
  ```

  Field-by-field: `+1` `recipient_count` = `0x4822`'s `name_count`; `+2` `recipients` =
  `0x4822`'s `name` (both are eight 16-byte slots); `+131` `subject` = `0x4822`'s `comment`
  (which is really the subject); `+264` the 64-bit time, never sent by this packet; `+272`
  `destination` = `0x4822`'s `message_type`; `+273` `echoed_flag_273` = `0x4822`'s `important`;
  `+288` `body` = `0x4841`'s block, at the identical address.

  That is a proved bijection — a literal `memcpy` between the two objects plus a shared reader
  (`0x8E8AFC`, the OPENmail screen, which renders `+1`, `+2`, `+131`, `+264` and `+288` from
  `base-8576`) — not an inference from a neighbouring field's name.

  Nothing here says how the *server* should answer; see `../outbound/mgo2_cmd_4801_s2c.ksy`.
  We have no handler for this command, which is why the capture exists: the client hangs
  (`FFFFFF60`) after send.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
seq:
  - id: recipient_count
    type: u1
    doc: |
      [ELF 2026-07-26] Number of populated recipient slots. The compose screen stores it at
      `0x8EEDC8` (`lwz r0,13736(...); stb r0,1(r24)` -> `base-8575`), and the same word at
      `+13736` is the loop bound over the recipient table. Capture: **1**, with exactly one
      name slot filled — consistent.
      Not the `0x4820` mailbox selector, whose only two values are `0x0F`/`0x10` (compile-time
      literals). Max is 8; see `recipients`.
  - id: recipients
    type: str
    size: 16
    encoding: ISO-8859-1
    pad-right: 0
    repeat: expr
    repeat-expr: 8
    doc: |
      [CONFIRMED 2026-07-26] **Eight fixed 16-byte recipient-name slots**, not one 128-byte name.
      Only the first `recipient_count` are populated; the block is zeroed before filling
      (`bzero(base-8574,128)` at `0x8EEA00`/`0x8EED08`) so unused slots are NUL.
      The screen loops an 8-entry x 28-byte table at `+13740` (occupied flag `+0`, name `+8`),
      memcpy'ing **16 bytes** per occupied entry into consecutive slots
      (`0x8EEA5C`-`0x8EEAA0`; single-recipient fast path `0x8EED24`-`0x8EED6C`). 8 x 16 = 128,
      and 16 is the character-name width used everywhere else in this protocol.
      [ELF] The wire block itself: `0xD5D0AC` r5=128 at `0xD53FC4`, from `base-8574`.
      Live capture: `recipient_count = 1`, slot 0 = `poop` (the operator's `to:`), slots 1-7 NUL.
      Each name is also whitespace-validated at `0x8EEB34` (see `subject`).
  - id: subject
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [CONFIRMED 2026-07-26] Subject line, NUL-padded to 128. Live capture: `hi`.
      [ELF] Raw 128-byte block, `0xD5D0AC` r5=128 at `0xD53FDC`, from `base-8445`; copied from
      screen `+14001` at `0x8EEADC`.
      The client refuses to send a **whitespace-only** value: the validator at `0x8EEBCC` scans
      all 128 bytes skipping `0x20`, `0x0A` and the 3-byte `E3 80 80` (UTF-8 U+3000 ideographic
      space) and reports "empty" if it reaches NUL. So a non-blank subject is guaranteed on the
      wire — but note the blankness rule is what is proven; "subject" as a *name* rests on the
      capture.
  - id: body
    size: 708
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [CONFIRMED 2026-07-26] Message body, NUL-padded to 708. Live capture: `poop`.
      [ELF] Raw 708-byte (`0x2C4`) block, `0xD5D0AC` r5=708 at `0xD53FF4`, from `base-8296`;
      copied from screen `+14130` at `0x8EEB00`, and whitespace-validated over all 708 bytes at
      `0x8EEC3C` by the same rule as `subject`.
      [ELF 2026-07-31] **The `0x4841` pairing is no longer [INFERRED] — it is the same address.**
      `0x4841`'s parser computes its 708-byte destination as `*(session+6404) + 0x20000 - 8296`
      (`0xd535f8`, `0xd53620`, `0xd5362c`); this field's source is `*(session+6404) + 0x20000 -
      8296` (`0xd53f80`, `0xd53f8c`, `0xd53fe4`). Same session field, same displacement, same
      width. The OPENmail screen word-wraps that buffer from byte 0 into twelve line elements
      (`0x8e8d68`, `0x8e90b4`), so there is no header in front of the text.
  - id: destination
    type: s1
    doc: |
      [ELF + CONFIRMED LIVE 2026-07-29] `0xD5C86C` (signed) at `0xD5400C`, from `base-8304`.
      **The destination class: 0 = an ordinary letter to named recipients, 3 = the GAME MASTER.**
      Was `unknown_3c5`, correctly identified as a mode byte with "what 0 vs 3 select is [UNKNOWN]".

      Only writer: `li r0,3; stb r0,272(r24)` at `0x8EEAA8`, taken on **bit 18 of the compose
      screen's flags word at `372(r31)`** (tested `0x8EEDE0`). The same bit gates the send at
      `0x8EE9C8`-`0x8EE9D0`: set, the builder memsets the 128-byte recipient-name block and skips
      the recipient build entirely; clear, it takes the ordinary path requiring a nonzero count.

      **Bit 18, not 17.** `rldicl. rX,r0,46,63` tests bit `64-46`. Two independent traces recorded
      17 before the rotate arithmetic was checked; bit 17 is real but unrelated — it is the
      message-body editor modal (`0x8EE940`), which is why the wrong label kept half-fitting.

      Bit 18 is set by the **GM menu item** (`0x8EF098`, dispatch case 3) and by the
      already-addressed screen-entry arm (`0x8E6ECC`); it is cleared by all four other To-menu
      items and by the send itself (`0x8EEAB4`). It is **not** cleared by leaving the screen.

      **That bit is the GM selection, confirmed live** — selecting To -> GM greys out the
      "View/Edit Address Book" row, which dims on exactly that bit (`0x8E4B30`). A GM letter has no
      recipient list, so the row correctly becomes meaningless.

      Value set is **{0, 3}**: `stb ...,272(rN)` occurs once in the whole mail module and 3 is the
      only literal stored. It is a boolean in a byte, not an enum — friend and clan picks travel the
      ordinary named path and are indistinguishable on the wire from a typed name.

      Live frame, 2026-07-29: a GM letter's entire 967-byte payload was zero apart from the subject
      at `0x081`, the body at `0x101`, and **`3` here**. Count 0, all eight name slots zero.

      Server note: this needs its own path. A GM letter has no recipient character, so it falls
      through a recipient loop as "0 of 0 delivered" — we answered SUCCESS and stored nothing until
      this was identified. See V61 and `gm_mail`.
  - id: echoed_flag_273
    type: s1
    doc: |
      [ELF 2026-07-31, batch 3c] `0xD5C86C` (signed) at `0xD5401C`, from `base-8303` = compose
      `+273`. Was `unknown_3c6`. **It is the same byte as `0x4822` field 8** — the one whose
      tier-4 name is "important" — round-tripped, and this file's "no writer was found anywhere in
      the compose screen" was true and misleading: the writer is not in the compose screen at all.

      The compose buffer is a **mail record**, byte for byte. `0xD5415C`'s open path computes
      `records[cat] + idx*280` and calls `MailRecordCopy` (`0xD34728`) with the destination
      `base-8576`, and that function copies `+0`, `+1`, `+2`(128), `+131`(128), `+264`(8), `+272`,
      `+273`, `+274` (`0xd347a4`-`0xd347c0`). So opening a letter loads `+273` from the server's
      `0x4822` entry, and a subsequent send hands it straight back here. `0xD342A4`
      (`ClearComposeLetter`, the only caller of `0xD34220`) zeroes it when the buffer is reset,
      which is why the observed value was `0`.

      **Only the identity is claimed, not the meaning.** "important" is a tier-4 label and is not
      adopted here. What is proven about the byte on the *client* side is that its sole reader is
      the mailbox row painter at `0x8e3934`, where it combines with `read` (`+274`) and
      `message_type` (`+272`) to pick one of three UI state hashes — see `0x4822`'s `important`
      for the table. Nothing in the binary writes it except that clear and that copy.

      Server note: a value we put in a `0x4822` entry will come back to us on the next `0x4800`
      the player sends after opening that letter. Treat it as untrusted echo, not as new input.
