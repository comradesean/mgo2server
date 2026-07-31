meta:
  id: mgo2_cmd_4700_c2s
  title: "MGO2 0x4700 — update connection info (client -> server)"
  endian: be
doc: |
  Sender `0xD38614`, builder call `0xD386C4`, subsystem index `0x73` (`li r4,115` at `0xD38748`).
  **Payload is Blowfish-encrypted** (PROTOCOL.md, DECRYPT_COMMANDS). Reply `0x4701`.

  The sender takes (r4 u16, r5 char*, r6 u16, r7 u16); it rejects `strlen(r5) > 16` (`0xDCC7F8`
  then `bgt` at `0xD3866C`) and requires `0xD32DD0` (the string-validity check) to pass, so the
  16-byte field is a validated ASCII string, NUL-padded by the source buffer.

  **Finding vs PROTOCOL.md:** the "`0x14` — 2 bytes, present in echo's parser, which skips it,
  purpose unknown" slot is a real u16 the client writes from its **fourth argument**
  (`0xD5C918` at `0xD38708`). The payload is therefore exactly 22 bytes, not "at least 20", and the
  trailing pair is a field, not padding. Its meaning is still unknown — only its provenance
  is now known.

  After the finaliser and before the send the function calls `0xD5D124` with r3 = ctx+0x1908(+1<<16)
  and r4 = the packet: that routine memsets a 1024-byte scratch buffer and memcpys the finished
  payload into it (packet retained/logged). It runs post-finalise with the cursor already reset, so
  it contributes **no** wire bytes.

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
  - id: private_port
    type: u2
    doc: "[CONFIRMED] PROTOCOL.md 0x00. `0xD5C918` at `0xD386D4`, source = sender arg r4."
  - id: private_ip
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [CONFIRMED] PROTOCOL.md 0x02: dotted quad, NUL-padded. Written as a fixed 16-byte raw block
      (`0xD5D0AC` with r5=16 at `0xD386E8`) from a caller string whose length the sender caps at 16.
  - id: public_port
    type: u2
    doc: "[CONFIRMED] PROTOCOL.md 0x12. `0xD5C918` at `0xD386F8`, source = sender arg r6."
  - id: unknown_14
    type: u2
    doc: |
      [ELF] `0xD5C918` at `0xD38708`, source = sender arg r7. PROTOCOL.md had this slot as
      unexplained bytes echo's parser skips; the ELF shows it is a u16 the client genuinely fills
      from a caller-supplied value. Meaning [UNKNOWN] — candidates not narrowed. Never read by us.
