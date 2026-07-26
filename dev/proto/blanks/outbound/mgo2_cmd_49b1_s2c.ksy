meta:
  id: mgo2_cmd_49b1_s2c
  title: "MGO2 0x49B1 - unmapped 0x49xx full-record reply, 420 bytes (server -> client)"
  endian: be
doc: |
  UNMAPPED SUBSYSTEM. Nothing in PROTOCOL.md or OBSERVED.md describes 0x49B1.

  Evidence: dispatcher 0xD38804, entry stub 0xD39660 -> thunk 0xD4B640, which sets
  `li r4,0x49B1` (0xD4B648) and `addi r5,r1,112` (the result out-param) and tail-calls the
  SHARED parser 0xD4AF34.

  0xD4AF34 SERVES A FAMILY: it dispatches on the id in r4 against 0x4911, 0x4913, 0x4985,
  0x4987, 0x49A1 and 0x49B1 (0xD4AF98-0xD4AFCC). 0x49B1 takes the same branch as 0x4985
  (0xD4AFDC) and skips the 0x4987-only sub-read at 0xD4B238. So the layout below is 0x49B1's
  path through a shared function - reading the function top to bottom without following the id
  compares would produce a layout no id actually uses.

  The record is memset to 680 bytes before parsing (0xD4B0F4, `li r5,680`), so unsent trailing
  fields read as 0 rather than stale. Total wire size on this path: 420 bytes.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.
seq:
  - id: result
    type: u4
    doc: |
      [ELF] read at 0xD4B074 into the thunk's out-param. MUST be 0 to continue: the parser
      checks it at 0xD4B084 and on non-zero jumps to 0xD4B454, past every other read - so an
      error reply is FOUR BYTES and nothing more. The thunk then only fires its notify when the
      value is not -1 (0xD4B668).
  - id: record_id
    type: u4
    doc: "[ELF] read at 0xD4B0A8, compared against a client-held id (0xD4B0D8) and stored at record+0x000. Mismatch aborts. [UNKNOWN] which id."
  - id: serial
    type: u2
    doc: "[ELF] read at 0xD4B148 -> record+0x29C. Same offset the shared identity helper 0xD49230 validates its u16 against in the 0x4Axx replies, which is why it is named `serial` here. [UNKNOWN] meaning."
  - id: unknown_0x0a
    type: u1
    doc: "[UNKNOWN] read at 0xD4B164 -> record+0x004."
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[INFERRED] 16-byte raw read (0xD4B184) -> record+0x005. Width certain, string role from the width and the NUL-terminating read; no renderer traced."
  - id: text
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[INFERRED] 128-byte raw read (0xD4B1A4) -> record+0x016. Width certain; string role inferred."
  - id: flags
    type: u1
    doc: |
      [ELF] 1-byte raw read (0xD4B1C0) expanded bit by bit: bit 0 -> 0x80, bit 1 -> 0x40,
      bit 2 -> 0x10 of the u32 at record+0x094 (0xD4B1DC-0xD4B22C). Only three of the eight
      bits are consumed; the other five are read and dropped. [UNKNOWN] meanings.
  - id: slots
    type: slot
    repeat: expr
    repeat-expr: 8
    doc: |
      [ELF] EXACTLY EIGHT, hard-coded (`cmpwi r26,7` at 0xD4B2D4, loop 0xD4B260-0xD4B2E4).
      No count on the wire. Stride 28 in the struct, 25 on the wire.
  - id: unknown_0x25c
    type: u4
    doc: "[UNKNOWN] read at 0xD4B2F4 -> record+0x25C."
  - id: unknown_0x260
    type: u1
    doc: "[UNKNOWN] read at 0xD4B310 -> record+0x260."
  - id: unknown_0x261
    type: u1
    doc: "[UNKNOWN] read at 0xD4B32C -> record+0x261."
  - id: unknown_0x262
    type: u2
    doc: "[UNKNOWN] read at 0xD4B348 -> record+0x262."
  - id: unknown_0x264
    type: u2
    doc: "[UNKNOWN] read at 0xD4B364 -> record+0x264."
  - id: unknown_0x268
    type: u4
    doc: "[UNKNOWN] read at 0xD4B380 -> record+0x268."
  - id: text_0x26c
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[INFERRED] 16-byte raw read (0xD4B3A0) -> record+0x26C."
  - id: unknown_0x280
    type: u4
    doc: "[UNKNOWN] read at 0xD4B3BC -> record+0x280."
  - id: text_0x284
    size: 16
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[INFERRED] 16-byte raw read (0xD4B3DC) -> record+0x284."
  - id: unknown_0x296
    type: u2
    doc: "[UNKNOWN] read at 0xD4B3F8 -> record+0x296."
  - id: unknown_0x298
    type: u4
    doc: "[UNKNOWN] read at 0xD4B40C -> record+0x298. Note: record+0x298 is the offset the 0x4Axx echo checks compare against (0xD4F050 etc.), so if these are the same object this is the field that must be echoed later. [INFERRED], offset-mirror reasoning only."
  - id: unknown_0x2a0
    type: u4
    doc: "[UNKNOWN] read at 0xD4B428 -> record+0x2A0."
  - id: unknown_0x2a4
    type: u4
    doc: "[UNKNOWN] read at 0xD4B444 -> record+0x2A4. Last field; the payload ends here at 420 bytes."
types:
  slot:
    doc: "[ELF] 25 wire bytes, stored with stride 28 at record+0x17C (word) / record+0x180 (the rest)."
    seq:
      - id: id
        type: u4
        doc: "[UNKNOWN] read at 0xD4B274 -> slot+0x00."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[INFERRED] 16-byte raw read (0xD4B290) -> slot+0x04 (17 bytes of struct with the NUL, which is where the 28-byte stride comes from)."
      - id: unknown_0x15
        type: u1
        doc: "[UNKNOWN] read at 0xD4B2AC -> slot+0x15."
      - id: unknown_0x18
        type: u4
        doc: "[UNKNOWN] read at 0xD4B2CC -> slot+0x18."
