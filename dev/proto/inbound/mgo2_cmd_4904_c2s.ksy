meta:
  id: mgo2_cmd_4904_c2s
  title: "MGO2 0x4904 — game lobby info request variant (one id) (client -> server)"
  endian: be
doc: |
  Sender `0xD47AFC`, builder call `0xD47B70`, subsystem index `0x39` (`li r4,57` at `0xD47BAC`).
  Unhandled by our server (COMMANDS.md lists `0x4904`–`0x49C2` as the game-lobby/roster/GHQ gap).
  Single u32, the sender's r4 argument; on a successful send the same value is also cached into a
  global (`stw` at `0xD47BD8`, `(ctx+2<<16)+27908`), i.e. the client remembers what it asked for.
  Total payload: 4 bytes.

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
    doc: |
      [ELF] `0xD5C9BC` at `0xD47B80`, source = sender arg r4 (spilled `1416(r1)`).
      Meaning [UNKNOWN]. Its retention in a client global after send suggests a selector the
      client must remember to match the reply against — structural inference only.
