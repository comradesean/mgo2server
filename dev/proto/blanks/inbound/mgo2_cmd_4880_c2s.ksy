meta:
  id: mgo2_cmd_4880_c2s
  title: "MGO2 0x4880 \u2014 manage mail (client -> server)"
  endian: be
doc: |
  Sender `0xD53138`, builder call `0xD531CC`, subsystem index `0x55` (`li r4,85` at `0xD53210`).
  Byte-for-byte the same shape as `0x4840` (`mgo2_cmd_4840.ksy`) and reading the same two struct
  fields at `base-8584` / `base-8576`, `base = *(u32*)(ctx+0x1904) + 0x20000`.
  Total payload: 2 bytes.

  Per this project's rule, that is "has matched `0x4840` in the one comparison made", not
  "duplicate": no divergence test exists, and the two senders are distinct functions whose
  callers may load the struct differently. PROTOCOL.md says nothing about either request.

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
      [CONFIRMED live 2026-07-26] Mailbox category of the letter to delete — identical field to
      `0x4840`'s, read from the same struct slot. A client deleting the second letter of its Sent
      tab sent `01 01`.
      [ELF] `0xD5C86C` (signed) at `0xD531DC`, from `base-8584`.
  - id: index
    type: u1
    doc: |
      [CONFIRMED live 2026-07-26] The letter's index within that category, as in `0x4840`.
      [ELF] `0xD5C8A0` at `0xD531EC`, from `base-8576` = record struct+0x00.

      NOTE what is absent: there is no "delete for both parties" flag and no deletion state
      anywhere in the mailbox protocol. `0x4822` is 266 bytes fully accounted for without one, so
      "deleted by the recipient but still in the sender's Sent list" exists only in server
      storage. Deletion is expressed by not sending the entry next time the list is built.
