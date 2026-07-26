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

  PROTOCOL.md's `0x4800` note is tier-4 only (Nomad implements it as clan applications). The field
  meanings below are therefore [UNKNOWN]; the widths 128/128/708 match the reference `0x4822`
  entry's `name[128], comment[128]` pair closely enough to be worth a fingerprint pass, but no
  label is asserted here.
  Total payload: 967 bytes.

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
  - id: unknown_00
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD53FAC`, from `base-8575`. Meaning [UNKNOWN]."
  - id: unknown_01
    size: 128
    doc: |
      [ELF] Raw 128-byte block, `0xD5D0AC` r5=128 at `0xD53FC4`, from `base-8574`.
      [UNKNOWN] — candidate: recipient name (the reference `0x4822` entry has a `name[128]`).
  - id: unknown_81
    size: 128
    doc: |
      [ELF] Raw 128-byte block, `0xD5D0AC` r5=128 at `0xD53FDC`, from `base-8445`.
      [UNKNOWN] — candidate: subject/comment (reference `0x4822` has `comment[128]`).
  - id: unknown_101
    size: 708
    doc: |
      [ELF] Raw 708-byte (`0x2C4`) block, `0xD5D0AC` r5=708 at `0xD53FF4`, from `base-8296`.
      [UNKNOWN] — the largest field; candidate: message body.
  - id: unknown_3c5
    type: s1
    doc: "[ELF] `0xD5C86C` (signed) at `0xD5400C`, from `base-8304`. Meaning [UNKNOWN]."
  - id: unknown_3c6
    type: s1
    doc: "[ELF] `0xD5C86C` (signed) at `0xD5401C`, from `base-8303`. Meaning [UNKNOWN]."
