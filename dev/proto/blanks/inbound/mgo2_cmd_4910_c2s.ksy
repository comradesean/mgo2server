meta:
  id: mgo2_cmd_4910_c2s
  title: "MGO2 0x4910 \u2014 create/configure game lobby entry (168 bytes) (client -> server)"
  endian: be
doc: |
  Sender `0xD4AC20`, builder call `0xD4AD64`, subsystem index `0x3C` (`li r4,60` at `0xD4AEC0`).
  Unhandled. The sender takes r4 = pointer to a settings struct (call it `S`) and validates it
  before building:

  - `strlen(S+5)` must be **3..16** (`0xDCC7F8`, `ble`/`bgt` at `0xD4AC8C`/`0xD4AC94`) and must
    pass the string-validity check `0xD32DD0`.
  - `strlen(S+22)` must be **<= 128** (`0xD4ACC0`).
  - if bit `0x80` of the u32 at `S+148` is set, `strlen(S+152)` must also be 3..16 and pass
    `0xD32DD0` (`0xD4ACC8`–`0xD4AD08`) — i.e. that field is conditional on the flag but is
    **always written**, so the wire layout is fixed.
  - the caller must have a selected/current something: `0xD4908C` must not return -1.

  After the finaliser the function calls the packet-retain helper `0xD5D124` (post-finalise, no
  wire effect). Total payload: 168 bytes.

  Every label is [UNKNOWN]: the widths (16-byte validated name, 128-byte free text, packed flag
  byte, second 16-byte validated name) are the shape of a "create room" form, but nothing here
  proves it and PROTOCOL.md does not cover the id.

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
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [ELF] Raw 16-byte block (`0xD5D0AC` r5=16 at `0xD4AD78`) from `S+5`, a string the sender
      requires to be 3..16 characters and name-valid. NUL-padded by the source buffer. [UNKNOWN].
  - id: unknown_10
    type: str
    size: 128
    encoding: ASCII
    doc: |
      [ELF] Raw 128-byte block (`0xD5D0AC` r5=128 at `0xD4AD8C`) from `S+22`, length-capped at 128.
      [UNKNOWN] — free text of some kind.
  - id: flags_90
    type: u1
    doc: |
      [ELF] One byte built on the stack at `1328(r1)` and written raw (`0xD5D0AC` r5=1 at
      `0xD4AE0C`). It repacks four bits of the u32 at `S+148`:
      `S+148 & 0x80 -> bit 0x01`, `& 0x40 -> 0x02`, `& 0x08 -> 0x10`, `& 0x04 -> 0x20`
      (`rldicl. r9,r0,57/58/61/62,63` at `0xD4ADA8`–`0xD4ADF4`). Bits `0x04`, `0x08`, `0x40`,
      `0x80` of this byte are never set. Meanings [UNKNOWN]; bit `0x01` gates the
      `unknown_91` validation above, so those two are linked.
  - id: unknown_91
    type: str
    size: 16
    encoding: ASCII
    doc: |
      [ELF] Raw 16-byte block (`0xD5D0AC` r5=16 at `0xD4AE24`) from `S+152`. Validated 3..16 chars
      only when `flags_90 & 0x01`; always present on the wire. [UNKNOWN].
  - id: unknown_a1
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD4AE44`, from `S+608` (`0x260`). Meaning [UNKNOWN]."
  - id: unknown_a2
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD4AE58`, from `S+168` (`0xA8`). Meaning [UNKNOWN]."
  - id: unknown_a3
    type: u1
    doc: "[ELF] `0xD5C8A0` at `0xD4AE6C`, from `S+169` (`0xA9`). Meaning [UNKNOWN]."
  - id: unknown_a4
    type: u4
    doc: "[ELF] `0xD5C9BC` at `0xD4AE80`, from `S+172` (`0xAC`). Meaning [UNKNOWN]."
