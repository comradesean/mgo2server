meta:
  id: mgo2_cmd_4b12_s2c
  title: "MGO2 0x4b12 — clan list ROWS, 48-byte records (server -> client)"
  endian: be
doc: |
  **The clan list rows.** Middle packet of the 0x4b11 / 0x4b12 / 0x4b13 triple answering 0x4b10.
  [CONFIRMED LIVE 2026-07-27] — the clan list renders name, member count, leader name and founding
  date from these rows in this order.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39B5C,
  parser 0xD56010.
  Size-driven: fronted by the length-aware call 0xD5CEB0 at 0xD560BC (`cmpwi r3,-1` -> exit),
  N records back to back, **no count field**. Omit the packet entirely for an empty page.

  **CORRECTION — the 101st record is a hard PARSE FAILURE, not a silent drop.** An earlier
  revision of this spec said the client array holds 100 entries (`cmpwi r4,99` at 0xD561E4) and
  that "anything past that is parsed and dropped". It is not dropped: exceeding the array fails
  the whole packet with **-71**, the same way the sibling item lists do at their own bounds
  (0x4b54 at 65 records, 0x4b92 at 101). The page size is therefore a hard limit on what may be
  put on the wire, not a convenience.

  The paging arithmetic that decides WHICH 100 rows these are lives entirely in 0x4b11's two
  header words — the record count never enters the page indicator. See mgo2_cmd_4b11_s2c.ksy.

  The two 16-byte text fields with a word between them are the same shape as one entry of the
  0x4A11 / 0x4A33 lists, at a different width - the resemblance is noted, not asserted.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CEB0 "cursor < payload length" (the only length-aware call).
  All of them bound-check the 1023-byte receive buffer, not the payload length, so a short
  packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: entries
    type: entry
    repeat: eos
    doc: "[ELF] size-driven (0xD560BC). 48 bytes each. At most 100 — a 101st fails the packet with -71."
types:
  entry:
    doc: "[CONFIRMED 2026-07-27] 48 wire bytes: one clan as the clan list draws it."
    seq:
      - id: clan_id
        type: u4
        doc: "[CONFIRMED 2026-07-27] The clan's id, read at 0xD560D4 -> record+0x00. What 0x4b80 is then sent with when the row is picked."
      - id: name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: "[CONFIRMED 2026-07-27] The clan's name, 16-byte fixed-width raw read (0xD560F4, -> r1+120)."
      - id: member_count
        type: u4
        doc: "[CONFIRMED 2026-07-27] How many members the clan has, read at 0xD56110 (-> r1+140). Renders as the list's member column."
      - id: leader_name
        size: 16
        type: str
        encoding: ISO-8859-1
        pad-right: 0
        doc: |
          [CONFIRMED 2026-07-27] The clan LEADER's name, second 16-byte raw read (0xD56130,
          -> r1+144). The leader is the only other name a list row could want, and it renders in
          the leader column, so this one is settled.
      - id: unknown_0x28
        type: u1
        doc: "[UNKNOWN] read at 0xD56158. Sent as zero; nothing on screen has changed with it."
      - id: unknown_0x29
        type: u1
        doc: "[UNKNOWN] read at 0xD56178. Sent as zero."
      - id: unknown_0x2a
        type: u1
        doc: "[UNKNOWN] read at 0xD56190. Sent as zero."
      - id: unknown_0x2b
        type: u1
        doc: "[UNKNOWN] read at 0xD561A8. Sent as zero. These four bytes are read as four separate u8, not one word - a server writing a u32 here would still parse, but the client treats them as four values."
      - id: founded_at
        type: u4
        doc: |
          [CONFIRMED 2026-07-27] The clan's founding date, Unix seconds, read at 0xD561CC
          (-> r1+168). Last field of the record; it renders as the list's date column.
