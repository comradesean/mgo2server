meta:
  id: mgo2_cmd_3041_s2c
  title: "MGO2 0x3041 — reply to 0x3040 (server -> client)"
  endian: be
doc: |
  Parser arm 0xd377d4 (ACCOUNT dispatcher 0xd37024 (compare tree at 0xd37074)). Wait slot 13 (0xd).

  Two-stage: read a u32 result (0xd5cc64 at 0xd37814); **only if it is zero** does the parser
  continue and read a u32 plus a fixed 16-byte block (0xd37838, 0xd37858) into the object returned
  by 0xd3a094. A non-zero result skips straight to `READ_END`, so an error reply is legitimately
  four bytes long.

  This matches OBSERVED.md exactly ("`0x3041` is s32 result, then (if 0) a u32 and 16 bytes"), now
  re-confirmed from the binary. `0x3040` has a live builder at 0xd37b6c taking a u8 (COMMANDS.md)
  and is still unanswered by us; the reply shape above is what closing that gap needs.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/OBSERVED.md
seq:
  - id: result
    type: u4
    doc: "[ELF] Wire 0x00. Zero gates the rest of the packet (0xd37828 `cmpwi r0,0; bne -> skip`)."
  - id: body
    type: success_body
    if: result == 0
    doc: "[ELF] Present only when result == 0; the parser does not read it otherwise."
types:
  success_body:
    seq:
      - id: unknown_04
        type: u4
        doc: "[UNKNOWN] Wire 0x04. Stored at offset +0 of the 0xd3a094 object. Meaning unestablished — `0x3040`'s subsystem is unidentified."
      - id: unknown_08
        size: 16
        doc: "[UNKNOWN] Wire 0x08, fixed 16 bytes (0xd5d018, r5=16) -> object +4, NUL written at +20. Width suggests a 16-char name field, by analogy with every other 16-byte field in the protocol — but that is a guess, not a read."
