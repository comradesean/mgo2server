meta:
  id: mgo2_cmd_4680_c2s
  title: "MGO2 0x4680 \u2014 match history list request (client -> server)"
  endian: be
doc: |
  Sender `0xD3B864`, builder call `0xD3B8D8`. Start/item/end triple `0x4681`/`0x4682`/`0x4683`,
  subsystem index `0x1D` (`li r4,29` before the status setter `0xD32E08` at `0xD3B924`).
  PROTOCOL.md "`0x4600` / `0x4680` / `0x4684`" documents this request as a single u32 character id;
  the ELF agrees exactly — one `0xD5C9BC` write of the function's r4 argument, nothing else.

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
  - id: character_id
    type: u4
    doc: |
      [CONFIRMED] The character whose met-players history is wanted. Sole payload field
      (`0xD5C9BC` at `0xD3B8E8`, source = the sender's r4 argument spilled at `1416(r1)`).
      PROTOCOL.md records this served live 2026-07-23.
