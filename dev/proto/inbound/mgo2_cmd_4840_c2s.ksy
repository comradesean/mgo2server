meta:
  id: mgo2_cmd_4840_c2s
  title: "MGO2 0x4840 \u2014 get mail contents (client -> server)"
  endian: be
doc: |
  Sender `0xD53264`, builder call `0xD532F8`, subsystem index `0x55` (`li r4,85` at `0xD5333C`).
  Both bytes come from the mailbox state struct at `base = *(u32*)(ctx+0x1904) + 0x20000`
  (sources `base-8584` and `base-8576`). PROTOCOL.md only records tier-4 behaviour for this id
  (Nomad answers with the wrong command number); nothing about the request layout.
  Total payload: 2 bytes.

  `0x4880` (`mgo2_cmd_4880.ksy`) has an identical two-byte shape from the same two struct fields.

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
  - id: category
    type: s1
    doc: |
      [CONFIRMED live 2026-07-26] The mailbox category of the letter to open — the same value the
      server put in wire byte 0 of that letter's `0x4822`. A client opening the first letter of
      its Sent tab sent `01 00`, and 1 was the category we had assigned to Sent; opening the
      second sent `01 01`.
      [ELF] `0xD5C86C` (signed) at `0xD53308`, from `base-8584` — the category the UI saved at
      `0xD54218`. Valid range 0..3 (4 = flat view); see `../outbound/mgo2_cmd_4822_s2c.ksy`.
  - id: index
    type: u1
    doc: |
      [CONFIRMED live 2026-07-26] The letter's index WITHIN that category — the `0x4822` index
      byte (wire 0x01) echoed back. It is a message handle, not a display position: every entry
      we send needs a distinct value or every row asks to open the same letter.
      [ELF] `0xD5C8A0` at `0xD53318`, from `base-8576` = record struct+0x00.
