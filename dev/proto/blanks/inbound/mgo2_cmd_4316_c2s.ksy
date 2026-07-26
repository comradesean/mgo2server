meta:
  id: mgo2_cmd_4316_c2s
  title: "MGO2 0x4316 — create game (client -> server)"
  endian: be
doc: |
  **One byte.** Evidence: builder call site `bl 0xd5cf40` at `0xd43ccc`. One write primitive:
  `bl 0xd5c8a0` (write-u8) at `0xd43cdc` from stack `1328(r1)`. Seal at `0xd43ce8`; wait slot
  `0x25` (`li r4,37`). [ELF]

  **This corrects PROTOCOL.md's phrasing.** It says "Request payload is **not read at all**",
  which is true of our handler but reads as though the packet is empty. It is not: the client
  sends one byte. PROTOCOL.md's own numbered finding 23 ("`0x4316` does not read its request
  payload at all") should likewise be read as a statement about the server, not the wire.
  Nothing here changes the conclusion that the *settings* arrive on `0x4310` — one byte cannot
  carry them.
doc-ref: dev/docs/PROTOCOL.md "0x4316 — create game"
seq:
  - id: unknown_00
    type: u1
    doc: |
      [UNKNOWN] Position exact, meaning unestablished. Sourced from a stack temporary at the
      top of the create-game sender, so its origin is not visible from the call site alone.
      Strongest candidate on position: the **lobby subtype** the game is being created in —
      the same value `0x4310` carries at its offset `0xA2` and `0x4313` reports at `0x09a`,
      and the value our server already needs to key `chara_host_settings` by
      (character, lobby subtype). Not tested; a capture of one `0x4316` next to its preceding
      `0x4310` would settle it in one round, since the two bytes should agree.
