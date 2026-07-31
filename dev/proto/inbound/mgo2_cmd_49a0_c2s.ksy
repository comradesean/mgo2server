meta:
  id: mgo2_cmd_49a0_c2s
  title: "MGO2 0x49a0 — game lobby request (one byte from a struct) (client -> server)"
  endian: be
doc: |
  Sender `0xD4A1F8`, builder call `0xD4A298`, subsystem index `0x49` (`li r4,73` after the send).
  Unhandled. The sender takes r4 = pointer to a struct `S` (rejected if NULL), and requires
  `0xD4908C != -1`. Immediately before building it **clears** `S+609` (u8) and `S+604` (u32)
  at `0xD4A280`/`0xD4A284`, then sends the single byte at `S+608`.
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
  - id: unknown_00
    type: u1
    doc: |
      [ELF] `0xD5C8A0` at `0xD4A2AC`, from `S+608` (`0x260`) — the same struct offset
      `0x4910` sends as its `unknown_a1`. Meaning [UNKNOWN].
