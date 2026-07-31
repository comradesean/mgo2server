meta:
  id: mgo2_cmd_4912_c2s
  title: "MGO2 0x4912 — game lobby request with id and optional 16-byte name (client -> server)"
  endian: be
doc: |
  Sender `0xD4AA48`, builder call `0xD4AB4C`, subsystem index `0x40` (`li r4,64` at `0xD4ABBC`).
  Unhandled. Arguments: r4 = u32, r5 = optional `char*`. If r5 is non-NULL it must be **3..16**
  characters (`0xDCC7F8` then `ble`/`bgt` at `0xD4AAA8`/`0xD4AAB0`) and pass `0xD32DD0`.
  The sender zeroes a 17-byte stack buffer (`vxor`/`stvx` + `stb 0,16` at `0xD4AB0C`–`0xD4AB1C`),
  `strcpy`s r5 into it when non-NULL, then writes the first 16 bytes: so a NULL argument sends
  16 zero bytes rather than omitting the field. Post-finalise `0xD5D124` retain call, no wire
  effect. Total payload: 20 bytes.

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
    doc: "[ELF] `0xD5C9BC` at `0xD4AB5C`, source = sender arg r4 (spilled `1480(r1)`). [UNKNOWN]."
  - id: unknown_04
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [ELF] Raw 16-byte block (`0xD5D0AC` r5=16 at `0xD4AB70`) from a zero-filled 17-byte stack
      buffer holding the optional name argument. All-zero when the caller passes NULL. [UNKNOWN].
