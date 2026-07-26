meta:
  id: mgo2_cmd_43f3_s2c
  title: "MGO2 0x43f3 \u2014 unidentified in-match notification (server -> client)"
  endian: be
doc: |
  Parser 0xD5B4D0, dispatcher stub 0xD39D8C. One of the four 0x43Fx ids in the in-match
  subsystem the client sends 0x43E0 / 0x43E2 into (COMMANDS.md).

  Reads EXACTLY ONE u32 (0xD5CCD8 at 0xD5B52C) into a stack temp, then calls 0xD33CD8 with UI
  event id 0x2E (46) and the u32 as its value, then 0xD5B41C (a screen/state poke shared with
  0x43F2 and 0x43F4).

  [UNKNOWN] what event 0x2E renders: the ELF gives the width and the event number, nothing about
  meaning, and neither PROTOCOL.md nor OBSERVED.md mentions this id. We have never sent it.

  Read primitives, identified from their bodies and cross-checked against the verified
  mgo2_cmd_4902.ksy: 0xD5CB8C / 0xD5CB54 u8, 0xD5CC14 / 0xD5CBC4 u16, 0xD5CCD8 / 0xD5CC64 u32,
  0xD5D018 fixed-width byte block (r5 = length, NUL-terminated on store), 0xD5CE34
  delimiter-terminated string, 0xD5CEB0 "cursor < payload length" loop test, 0xD5C844 /
  0xD5C858 reader open/close.
seq:
  - id: result
    type: u4
    doc: |
      Payload of UI event 0x2E. Meaning [UNKNOWN]. [ELF 0xD5B52C]
