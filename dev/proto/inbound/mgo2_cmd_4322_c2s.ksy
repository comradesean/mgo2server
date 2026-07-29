meta:
  id: mgo2_cmd_4322_c2s
  title: "MGO2 0x4322 — join failed (client -> server)"
  endian: be
doc: |
  **Empty payload — confirmed from the ELF.** Builder function `0xD43458`; `bl 0xD5CF40` at
  `0xD434C8` (`li r4,0x4322` at `0xD434C0`) is followed immediately by the seal `0xD5C828`
  at `0xD434D4` and the flush `0xD34CC0` at `0xD434E4`. **No write primitive is called
  between them**, so the length the seal banks is 0. Not encrypted.

  Agrees with `PROTOCOL.md` ("empty payload"), which had this from live capture; the ELF now
  confirms it independently.
doc-ref: dev/docs/PROTOCOL.md "0x4322 — join failed"
seq: []
