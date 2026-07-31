meta:
  id: mgo2_cmd_4900_c2s
  title: "MGO2 0x4900 — get game lobby info (client -> server)"
  endian: be
doc: |
  Sender `0xD47C08`, builder call `0xD47C78`, subsystem index `0x38` (`li r4,56` at `0xD47C9C`).
  Replies `0x4901`/`0x4902`/`0x4903` (the `0x4902` entry is specced in
  `../mgo2_cmd_4902.ksy`).

  **Zero payload bytes.** Between the builder call at `0xD47C78` and the finaliser `0xD5C828` at
  `0xD47C84` there is exactly one instruction (`mr r3,r31`) — no primitive is called, so the
  finalised length is 0. This confirms PROTOCOL.md's "request payload is not read" from the other
  side: there is nothing to read.

  Read from the send path in `MGO2.elf` (`dev/ref/MGO2 (decrypted).elf`) on 2026-07-26.
  Method: the packet builder `0xD5CF40` (`li r4,<id>` at builder_call-4) memsets a 1024-byte
  payload buffer at `pkt+0x40`, zeroes the cursor at `pkt+0x454` and stores the id at `pkt+0x00`;
  the enclosing function then appends fields with the serialisation primitives; `0xD5C828`
  finalises (copies the cursor into `pkt+0x04` as the length) and `0xD34CC0` sends. Everything
  between the builder call and the finaliser is the payload, in wire order.

  Primitive map used below (all take r3=packet, r4=pointer to the value):
  `0xD5C86C` s1 · `0xD5C8A0` u1 · `0xD5C8D4` s2 · `0xD5C918` u2 · `0xD5C95C` s4 · `0xD5C9BC` u4 ·
  `0xD5CADC` NUL-terminated string · `0xD5D0AC` raw block of r5 bytes.
seq: []
