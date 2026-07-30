meta:
  id: mgo2_cmd_4603_s2c
  title: "MGO2 0x4603 — player search, list END (server -> client)"
  endian: be
doc: |
  End packet of the 0x4600 player-search triple. Parser 0xD45CF4, dispatcher stub 0xD39390.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD45D78) and stores it into the subsystem-0x53 result slot
  UNCONDITIONALLY (0xD32E08 / 0xD32E70), marking the transaction complete. Because the store is
  unconditional, the END value is the operative result on the success path: it must be 0 even
  when the start was 0.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code, stored unconditionally. MUST be 0 on the success path.
      [CONFIRMED by PROTOCOL.md; ELF 0xD45D78]
