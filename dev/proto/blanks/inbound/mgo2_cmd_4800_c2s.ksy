meta:
  id: mgo2_cmd_4800_c2s
  title: "MGO2 0x4800 \u2014 send mail (client -> server)"
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

  Still [UNKNOWN] after the capture: the leading u8 (observed `1`) and the two trailing signed
  bytes (both `0`). One capture cannot separate a constant from a variable — vary the mailbox
  or the recipient count before naming them.

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
      708 is the same width as the block `0x4841` reads on success — consistent with a stored
      mail body round-tripping, though that pairing is [INFERRED], not tested.
  - id: unknown_3c5
    type: s1
    doc: |
      [ELF] `0xD5C86C` (signed) at `0xD5400C`, from `base-8304`. A **mode byte**: the only
      writer found in the compose screen is `li r0,3; stb r0,272(r24)` at `0x8EEAA8`, taken
      conditionally on a bit of `372(r31)` tested at `0x8EEDE0`; the other branch keeps a value
      set elsewhere. Observed **`0`** in the 2026-07-26 capture, so the capture took the other
      branch. What 0 vs 3 select is [UNKNOWN].
  - id: unknown_3c6
    type: s1
    doc: |
      [ELF] `0xD5C86C` (signed) at `0xD5401C`, from `base-8303`. Meaning [UNKNOWN]; **observed
      `0`**. **No writer was found anywhere in the compose screen** — [UNDETERMINED] whether
      anything ever sets it.
