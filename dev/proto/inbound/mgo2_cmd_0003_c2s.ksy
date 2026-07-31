meta:
  id: mgo2_cmd_0003_c2s
  title: "MGO2 0x0003 — disconnect (client -> server)"
  endian: be
doc: |
  **Empty payload — zero bytes.**

  Evidence: builder call site `bl 0xd5cf40` at `0xd34e80` (`li r4,3` at `0xd34e7c`), enclosing
  sender `0xd34e40`. The packet-builder pair that brackets the payload is
  `0xd5cf40` (new: memset the 1024-byte buffer at obj+0x40, store the id at obj+0x00,
  cursor obj+0x454 = 0) and `0xd5c828` (seal: obj+0x04 = cursor, i.e. the payload length).
  Between the two calls — `0xd34e84`..`0xd34e8c` — there is **not one write primitive call**,
  so the sealed length is 0. The flush is `bl 0xd34cc0` at `0xd34e9c`.

  No request-status slot is registered after the flush (no `li r4,<slot>` /
  `bl 0xd32e08` pair): the client does not wait for a reply. [ELF]
  Matches PROTOCOL.md "0x0003 — disconnect" (empty payload, no reply). [CONFIRMED]
doc-ref: dev/docs/PROTOCOL.md "0x0003 — disconnect"
seq: []
