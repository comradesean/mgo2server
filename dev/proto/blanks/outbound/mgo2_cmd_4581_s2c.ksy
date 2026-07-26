meta:
  id: mgo2_cmd_4581_s2c
  title: "MGO2 0x4581 \u2014 bulk roster fetch, list START (server -> client)"
  endian: be
doc: |
  Start packet of the 0x4580 roster triple (0x4581 start / 0x4582 records / 0x4583 end).
  Parser 0xD469C0, dispatcher stub 0xD39340.

  Reads EXACTLY ONE u32 (0xD5CC64 at 0xD46A90). Semantics read out of 0xD46AB4-0xD46B20:

    * the subsystem index is NOT fixed -- it is 0x51 + the u8 state the client sent in its 0x4580
      request (0x51 friends, 0x52 blocked). Both list arrays are per-state.
    * NONZERO: status setter 0xD32E08(idx, 2) then result setter 0xD32E70(idx, value) -- the
      transaction completes as failed with the value stored verbatim, exactly the mechanism that
      produced the 1032:00000005 dialog for the 0x4680 family (OBSERVED.md).
    * ZERO: takes the other branch (0xD46B04) and zeroes both list count words -- the client
      counts 0x4582 records itself.

  PROTOCOL.md ("0x4580 -- bulk roster fetch") records this as a 4-byte result, 0 for success;
  the ELF agrees.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. 0 = success (resets the count for state 0x51/0x52); nonzero =
      the roster screen fails with this value. [CONFIRMED by PROTOCOL.md; ELF 0xD46A90]
