meta:
  id: mgo2_cmd_4860_c2s
  title: "MGO2 0x4860 \u2014 file / forward mail (client -> server)"
  endian: be
doc: |
  ## THE `0xD53B6C` SENDER IS THE `0x4801` FAILURE PATH, NOT A USER ACTION

  `0x4801` (send-mail reply) tests bit 0 of its flags byte (`clrldi. r9,r0,63` at `0xD53E90`).
  When that bit is **clear** the parser calls `0xD53B6C`, which is a packet *sender*: it rebuilds
  the entire letter as this 969-byte `0x4860` (opcode 1, second byte `0xFF`) and puts request slot
  `0x55` back to state 1 = in-flight (`0xD32E08(ctx,85,1)` at `0xD53CE4`).

  So a server that answers `0x4800` with `flags = 0` and does not implement `0x4860` hangs the
  client exactly as if it had never replied. Nomad's `flags = 0` works only because Nomad also
  answers `0x4860` with a no-op `0x4861`; either half alone is a stall. We send `flags = 1` and
  therefore never see this command — see `../outbound/mgo2_cmd_4801_s2c.ksy`.

  The other sender, `0xD539B8` (opcode 2), is UI-initiated and its trigger is [UNKNOWN].

  **Two** senders, identical wire shape, differing only in the two leading literals:
  `0xD539B8` (builder call `0xD53A50`) writes `1st = 2`, and `0xD53B6C` (builder call `0xD53C04`)
  writes `1st = 1, 2nd = 0xFF`. Subsystem index `0x55` (`li r4,85`) in both.
  Fields 3..8 come from the mailbox compose struct at
  `base = *(u32*)(ctx+0x1904) + 0x20000`, and are **the same six fields, in the same order, as the
  whole of `0x4800`** (`mgo2_cmd_4800.ksy`); this command prefixes them with two bytes.
  Total payload: 969 bytes.

  PROTOCOL.md records only that Nomad answers `0x4861 {0}` as a no-op — tier 4, and silent on
  the request. All labels here are [UNKNOWN].

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
seq:
  - id: opcode
    type: s1
    doc: |
      [ELF] `0xD5C86C` at `0xD53A60` / `0xD53C14`. Literal per call site: **2** from the
      `0xD539B8` sender, **1** from the `0xD53B6C` sender. Two operations share the id;
      which is which is [UNKNOWN].
  - id: unknown_01
    type: u1
    doc: |
      [ELF] `0xD5C8A0` at `0xD53A70` / `0xD53C24`. Source differs by call site: `base-8576`
      in the opcode-2 sender, the literal `0xFF` (-1) in the opcode-1 sender. [UNKNOWN].
  - id: unknown_02
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD53A84` / `0xD53C38`, from `base-8575`. [UNKNOWN]."
  - id: unknown_03
    size: 128
    doc: "[ELF] Raw 128 bytes, `0xD5D0AC` r5=128 at `0xD53A9C` / `0xD53C50`, from `base-8574`. [UNKNOWN] — same slot as 0x4800's unknown_01."
  - id: unknown_83
    size: 128
    doc: "[ELF] Raw 128 bytes, `0xD5D0AC` at `0xD53AB4` / `0xD53C68`, from `base-8445`. [UNKNOWN]."
  - id: unknown_103
    size: 708
    doc: "[ELF] Raw 708 bytes (`0x2C4`), `0xD5D0AC` at `0xD53ACC` / `0xD53C80`, from `base-8296`. [UNKNOWN]."
  - id: unknown_3c7
    type: s1
    doc: "[ELF] `0xD5C86C` at `0xD53AE4` / `0xD53C98`, from `base-8304`. [UNKNOWN]."
  - id: unknown_3c8
    type: s1
    doc: "[ELF] `0xD5C86C` at `0xD53AF4` / `0xD53CA8`, from `base-8303`. [UNKNOWN]."
