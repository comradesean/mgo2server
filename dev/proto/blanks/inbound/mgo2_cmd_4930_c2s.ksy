meta:
  id: mgo2_cmd_4930_c2s
  title: "MGO2 0x4930 \u2014 game lobby request (boolean byte) (client -> server)"
  endian: be
doc: |
  Sender `0xD4A324`, builder call `0xD4A3B0`, subsystem index `0x41` (`li r4,65` after the send).
  Unhandled. Single u8 from the sender's r4 argument — and the sender **rejects any value
  above 1** before building (`cmplwi cr6,r4,1` at `0xD4A344`, `bgt` to the error exit at
  `0xD4A358`, returning -24). So the field is a boolean on the wire, tier-1.
  Total payload: 1 byte.

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
  - id: flag
    type: u1
    doc: |
      [ELF] `0xD5C8A0` at `0xD4A3C0`, source = sender arg r4, constrained to 0 or 1 by the
      guard at `0xD4A344`/`0xD4A358`. Which toggle it carries is [UNKNOWN].
