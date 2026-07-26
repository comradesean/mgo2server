meta:
  id: mgo2_cmd_4802_s2c
  title: "MGO2 0x4802 — mail-send notification, EMPTY payload (server -> client)"
  endian: be
doc: |
  Second parsed reply id of the 0x4800 send-mail family (with 0x4801). Parser 0xD54090,
  dispatcher stub 0xD394D4. COMMANDS.md lists it under "the rest of the mailbox" —
  parsed but never sent by us. PROTOCOL.md documents no layout for it.

  THE PAYLOAD IS EMPTY. The parser fetches the header (0xD3879C), compares the id
  (cmpwi 0x4802 at 0xD540C8), stores the byte -1 at ctx+0x1554 (0xD540E4) and calls 0xD33CD8
  with UI event id 0x32 (50) and value -1 (li r5,-1 at 0xD540BC, widened at 0xD540D0). No
  stream reader is opened (no 0xD5C844) and no read primitive is called.

  Because the value passed to the UI is the constant -1 rather than anything from the wire,
  this id carries no information beyond its own arrival: a bare notify.
seq:
  - id: unknown_body
    size-eos: true
    doc: |
      [ELF 0xD54090] Present only to state that nothing is parsed. Expected length 0.
