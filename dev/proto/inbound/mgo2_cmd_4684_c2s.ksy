meta:
  id: mgo2_cmd_4684_c2s
  title: "MGO2 0x4684 — match detail request (client -> server)"
  endian: be
doc: |
  Sender `0xD3B778`, builder call `0xD3B7EC`. Start/item/end triple `0x4685`/`0x4686`/`0x4687`,
  subsystem index `0x1E` (`li r4,30` at `0xD3B820`). PROTOCOL.md documents the request as one u32
  entry id selected from the `0x4682` list; the ELF agrees — a single `0xD5C9BC` write.
  No UI path to this command has been observed live (Player Details sends `0x4220` instead).

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
  - id: entry_id
    type: u4
    doc: |
      [CONFIRMED per PROTOCOL.md; ELF-exact position/width] The selected history entry id.
      Sole payload field (`0xD5C9BC` at `0xD3B7FC`, source = the sender's r4 argument).
