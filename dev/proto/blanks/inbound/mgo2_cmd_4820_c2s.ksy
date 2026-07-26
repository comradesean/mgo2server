meta:
  id: mgo2_cmd_4820_c2s
  title: "MGO2 0x4820 \u2014 get messages (client -> server)"
  endian: be
doc: |
  Two sender functions, both one byte long: `0xD53390` (builder call `0xD53414`) writes the
  literal **`0x10`** and `0xD53494` (builder call `0xD53518`) writes the literal **`0x0F`**;
  both use the signed-byte primitive `0xD5C86C` and both use subsystem index `0x55`
  (`li r4,85`). Replies `0x4821`/`0x4822`/`0x4823`.

  **Finding vs PROTOCOL.md:** the section on `0x4820` says "the selector values are named after
  the reference servers and are unverified". The *values* are now tier-1 verified — `0x0F` and
  `0x10` are the only two constants any builder puts here, hardcoded one per call site, so no
  other value can ever arrive. What is still unverified is which one means mail and which means
  clan applications: that mapping is not visible from the builders (both are literals) and needs
  a request log from the live client.

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
  - id: mailbox
    type: s1
    enum: mailbox_kind
    doc: |
      [ELF] Sole payload field, 1 byte. Exactly two producers: `0x10` (`0xD533D0`→`0xD53424`)
      and `0x0F` (`0xD534D4`→`0xD53528`), each a compile-time literal. The enum labels below
      follow PROTOCOL.md's reference-derived naming and are **[UNKNOWN]** as a mapping — the
      constants are proven, the semantics are not.
enums:
  mailbox_kind:
    0x0f: mail
    0x10: clan_applications
