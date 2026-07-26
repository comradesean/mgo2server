meta:
  id: mgo2_cmd_4441_s2c
  title: "MGO2 0x4441 \u2014 0x4440 ack (server -> client)"
  endian: be
doc: |
  The only reply the client parses for the unidentified 0x4440 team/spectator request. Parser
  0xD52980, reached from dispatcher 0xD38804 via the stub at 0xD3941C.

  The parser reads EXACTLY ONE u32 (0xD5CC64 at 0xD529DC) and nothing else, then drives the
  generic transaction pair used by every list triple in this protocol: status setter 0xD32E08
  (subsystem index 0x54, state 2) and result setter 0xD32E70 with the u32 verbatim. So 0x4441
  alone completes the 0x4440 transaction.

  FINDING for COMMANDS.md's open question ("check whether the 0x4440 team/spectator flow expects
  0x4442 as well"): it does not. 0x4442's parser (0xD52878) touches neither setter for index 0x54
  -- it fires UI event 0x31 instead -- so it is a server-initiated push, not the second half of
  this reply. See mgo2_cmd_4442.ksy.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Result code. Nonzero is stored verbatim and marks the 0x54 transaction failed;
      the reference-parity answer is 0. [ELF 0xD529DC]
