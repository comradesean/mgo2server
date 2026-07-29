meta:
  id: mgo2_cmd_4602_s2c
  title: "MGO2 0x4602 — player-search result records (server -> client)"
  endian: be
doc: |
  Item packets of the 0x4600 player-search triple (0x4601 start / N x 0x4602 / 0x4603 end).
  Parser 0xD45F38 (ends 0xD46124), dispatcher stub 0xD39380. PROTOCOL.md documents 59-byte
  records, client table capped at 100; the ELF confirms both.

  LOOP STRUCTURE. No per-packet count: 68-byte scratch zeroed (memset r5=68 at 0xD45FC4), loop
  test 0xD5CEB0 at 0xD45FD0 (cursor < payload length), seven field reads, memcpy into the array
  at stride 68 (mulli at 0xD460C0), count++ , back-edge at 0xD460E4. Cap check `cmpwi r3,99`
  at 0xD460B8 → 100 entries, then bail.

  BYTE-IDENTICAL TO 0x4582. Same seven reads in the same order at the same offsets, same 68-byte
  stride; the only differences are the table cap (100 here, 32 for 0x4582) and the array. Since
  2026-07-26 the two are tracked as *matching in all fields examined*, not as duplicates — no
  divergence test has been run, and the 0x4583 tail-field filter (see mgo2_cmd_4583.ksy) has no
  counterpart in the 0x4603 end handler (0xD45CF4 does no compaction pass), which is already one
  behavioural asymmetry between the families.

  WIRE 59 BYTES, CLIENT STRUCT 68 — the three 16-byte strings NUL-terminate at dest[16] and the
  following scalars re-align, so struct offsets run ahead of wire offsets: struct
  0/4/22/24/44/48/65 for wire 0/4/20/22/38/42/58.

  Field labels below stay [UNKNOWN] past id and name. PROTOCOL.md records a tier-4 reading from
  the SaveMGO Nomad dev-era test payload `search-player.bin` as a presence card
  ({id, name, u16 36 = level/rank?, 16B current lobby, u32 1 = in-game?, 16B current game,
  u8 4 = lobby id?}) — plausible labels awaiting a fingerprint pass, not evidence.
doc-ref: dev/docs/PROTOCOL.md "0x4600 — player search"
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF 0xD45FD0] Records until the payload ends; may be split across 0x4602 packets freely."
types:
  entry:
    doc: "59 bytes on the wire, 68 in the client struct."
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED by PROTOCOL.md] character id → struct+0x00. [ELF 0xD45FE8]"
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED by PROTOCOL.md] character name, NUL-padded → struct+0x04. [ELF 0xD46008]"
      - id: unknown_0x14
        type: u2
        doc: "[UNKNOWN] → struct+0x16. [ELF 0xD46024] Tier-4 candidate: level/rank (36 in the Nomad test payload)."
      - id: unknown_0x16
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[UNKNOWN] → struct+0x18. [ELF 0xD46044] Tier-4 candidate: current lobby name."
      - id: unknown_0x26
        type: u4
        doc: "[UNKNOWN] → struct+0x2C. [ELF 0xD46060] Tier-4 candidate: in-game flag."
      - id: unknown_0x2a
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[UNKNOWN] → struct+0x30. [ELF 0xD46080] Tier-4 candidate: current game name."
      - id: unknown_0x3a
        type: u1
        doc: "[UNKNOWN] last byte → struct+0x41. [ELF 0xD4609C] Tier-4 candidate: lobby id."
