meta:
  id: mgo2_cmd_4901_s2c
  title: "MGO2 0x4901 \u2014 game-lobby list START (server -> client)"
  endian: be
doc: |
  Start packet of the 0x4900 hub triple (0x4901 start / 0x4902 entries / 0x4903 end). Parser
  0xD4780C, dispatcher stub 0xD39598.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD4788C), then the subsystem-0x38 status/result setters
  (0xD32E08 / 0xD32E70), and on the zero branch a third 0xD32E70 with 0. LOBBIES.md records the
  same: "0x4901: result; sets count 0 and marker -1". PROTOCOL.md notes we send C0FFEE02 here and
  stop when there is no session -- i.e. a nonzero result is a deliberate failure signal.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 for success (resets the 64-entry array at ctx+0xB790 and its
      count); C0FFEE02 is our deliberate no-session failure. [CONFIRMED]
