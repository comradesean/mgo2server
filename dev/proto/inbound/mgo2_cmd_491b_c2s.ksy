meta:
  id: mgo2_cmd_491b_c2s
  title: "MGO2 0x491b — game lobby request (u4, u2, u1, u4) (client -> server)"
  endian: be
doc: |
  Sender `0xD4D9E4`, builder call `0xD4DAA8`. Unhandled. Arguments: r4 = u32 (spilled
  `1432(r1)`), r5 = u8 (spilled `1440(r1)`). Two further fields come out of a state struct reached
  as `base = ctx + (1<<16)`; sources `base-9276` and `base-9328`.
  Total payload: 11 bytes.

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
    type: u4
    doc: "[ELF] `0xD5C9BC` at `0xD4DAB8`, source = sender arg r4. [UNKNOWN]."
  - id: unknown_04
    type: u2
    doc: "[ELF] `0xD5C918` (unsigned) at `0xD4DACC`, from `base-9276`. [UNKNOWN]."
  - id: unknown_06
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD4DADC`, source = sender arg r5. [UNKNOWN]."
  - id: unknown_07
    type: u4
    doc: "[ELF] `0xD5C9BC` at `0xD4DAF0`, from `base-9328`. [UNKNOWN]."
