meta:
  id: mgo2_cmd_4b11_s2c
  title: "MGO2 0x4b11 — clan list HEADER, {result, offset, total} (server -> client)"
  endian: be
doc: |
  **Header of the clan list.** First packet of the 0x4b11 / 0x4b12 / 0x4b13 triple answering the
  paged clan list request 0x4b10 `{u8 kind, s32 amount, u8}` (builder 0xD58164). `kind` selects
  the arm — 1 steps back 100, 2 forward 100, 4 is absolute, 0 and 3 are the first page — and the
  client's own array holds 100 entries (`cmpwi r4,99` at 0xD561E4), so **100 is the page size**.
  `amount` is a 1-BASED ENTRY INDEX, not a page number: after being shown one entry the client
  asked for 101.

  **CORRECTION — the two words after the result are {OFFSET, TOTAL}, IN THAT ORDER.**
  [CONFIRMED LIVE 2026-07-27]. An earlier revision of this spec recorded both as [UNKNOWN] and the
  server sent them as {total, offset}; that swap is the whole of the "2 out of 1" bug. The client
  stores them at block+0x08 and block+0x0C and renders a "%d/%d" page indicator (format string at
  0xE11518, drawn at 0xAC11A4 and at 0xAC2958) as:

      left  = A <= 0 ? 1 : (A - 1) / 100 + 2        A = block+0x08 = offset
      right = (B - 1) / 100 + 1                     B = block+0x0C = total

  Sending A = 1 puts it in the 1..100 bucket and renders page 2 — of 1. **The record count never
  enters that text at all**, which is why changing the number of 0x4b12 rows changed nothing; only
  these two words move the indicator.

  Corroborated by the sibling clan-search triple, which fills the same two slots itself rather than
  from the wire: 0x4b93 sets block+0x08 = 0 and block+0x0C = the record count (0xD54D64,
  0xD54D78). Same two slots, same meaning, one page.

  The client also pages **optimistically** — it asks for the next 100 without knowing whether they
  exist — so a server that honours `amount` literally will be asked to describe a page past the
  end. Clamping to the last populated page is the fix; answering "0 clans, starting at 101, out of
  a total of 1" is self-contradictory and the screen renders it as "2 out of 1" and then corrupts
  the list on the next scroll. That clamp is **operator policy** — the protocol does not say it —
  but the contradiction it avoids is the client's own arithmetic above.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39B4C,
  parser 0xD557A0.
  Raises two completion events (0xD32E70 at 0xD558B4 and 0xD558D4), so two UI waiters key off
  this one reply.
  Read primitives (naming as in ../mgo2_cmd_4902.ksy): 0xD5CCD8 / 0xD5CC64 u32,
  0xD5CC14 / 0xD5CBC4 u16, 0xD5CB8C u8, 0xD5D018 raw N (writes a NUL at dest+N but consumes
  exactly N on the wire), 0xD5CE34 delimiter-terminated string, 0xD5CEB0 "cursor < payload length"
  (the only length-aware call). All of them bound-check the 1023-byte receive buffer, not the
  payload length, so a short packet desyncs rather than erroring - see mgo2_cmd_4902.ksy.

  ADDRESS AND SEMANTICS CORRECTION (2026-07-26, read out of the primitive itself): the string
  reader's entry point is **0xD5CE34**, not 0xD5CE3C — the previous function's `blr` is at
  0xD5CE30 and 0xD5CE3C is two instructions into the body. It is **not** a NUL-terminated
  string reader: the loop compares each byte against **r5, a caller-supplied delimiter**
  (`cmpw cr7,r0,r5` at 0xD5CE78); NUL is only a secondary stop (`cmpwi cr6,r0,0` at 0xD5CE7C).
  Callers that pass r5 = 0 get NUL termination as a special case. Either way the cursor is
  advanced **past** the terminator (`addi r9,r9,1` at 0xD5CEA4 after `stw r11` at 0xD5CE94), so
  the field consumes **len + 1** wire bytes, and the client writes its own NUL at dest+len
  (0xD5CE9C).

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
seq:
  - id: result
    type: u4
    doc: "[CONFIRMED 2026-07-27] Clan-list result, read at 0xD5582C. 0 = the header and the rows follow."
  - id: offset
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The **0-based row offset of this page**, read at 0xD55854 and stored
      at block+0x08. This is the FIRST of the two words, not the second — see the CORRECTION in the
      top-level doc.

      It is the only input to the left half of the "%d/%d" page indicator:
      `left = offset <= 0 ? 1 : (offset - 1) / 100 + 2`. Send 0 for the first page; sending 1
      renders "page 2".
  - id: total
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] The **total number of clans across all pages**, read at 0xD5586C and
      stored at block+0x0C. Second of the two words. Drives the right half of the page indicator:
      `right = (total - 1) / 100 + 1`.

      Not a count of the rows in this reply — the 0x4b12 records are size-driven and the client
      counts them itself.
