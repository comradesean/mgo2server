meta:
  id: mgo2_cmd_4a50_s2c
  title: "MGO2 0x4A50 - server notice record, nine-way dispatch (server -> client)"
  endian: be
doc: |
  TOURNAMENT / SURVIVAL BLOCK, but **not the event record**. 0x4A50's id puts it in the 0x4Axx
  range and its parser sits in that block, yet its destination is a general session slot, not
  the 7296-byte event record - see below. Treat the 0x4A24 field names as NOT applying here.

  TIER. Post-launch content; no available client build exercises 0x4A50, so **everything here
  is tier 1, read from MGO2.elf, and cannot be raised to tier 2.**

  WHAT IT IS: a **one-at-a-time pending notice slot**. The parser builds a 276-byte (0x114)
  record on the stack at r1+112 (memset at 0xD50318-0xD5032C) and, after RD_END, memcpys it to
  **session+0x16BC** (0xD503D4-0xD503E8, `li r5,276`). That slot has exactly two other
  functions in the binary and they are the classic pair for a mailbox:
    * **0xD346C8 - take the notice.** `if (*(u32*)(session+0x16BC) != 0) { if (out) memcpy(out,
      session+0x16BC, 276); return that u32; } return 0;` - so a non-zero leading word means
      "a notice is pending", and the caller gets the whole 276 bytes.
    * **0xD341E0 - clear it.** `memset(session+0x16BC, 0, 276)`.
  Both address it as `addis rX,rY,1` / displacement 5820, the same form the parser uses.

  AND THE PARSER DISPATCHES ON IT IMMEDIATELY. 0xD503F0-0xD50418 reloads the leading word,
  computes `code - 19152`, requires the result `<= 8` unsigned, and uses it as an index into a
  **nine-arm jump table** (`lwax` off the TOC anchor, then `bctr`), with `notice_flags`
  (rec+0x04) preloaded in r11 for every arm. Out of range falls through to 0xD50448 and the
  record is stored but not acted on. So the leading word is a **discriminator with nine legal
  values, 19152..19160 = 0x4AD0..0x4AD8**, not a count and not a result code: it is never
  sign-extended into `0xD32E70` and this command consumes no request slot.

  Evidence: GAME dispatcher 0xD387C8, compare tree at 0xD38804, entry stub 0xD39ABC,
  parser 0xD502C8 (id compare `cmpwi 0x4A50` at 0xD50310).
  269 bytes on the wire at most, no loop, no identity header. The 256-byte block at the end is
  the largest single text field seen anywhere in Channel A, and it is **conditional** - see
  `notice_flags`.
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
  **UI event dispatch, traced 2026-07-26.** This spec cites `0xD33CD8`. That helper is generic
  ("command N arrived") and does two things on the net-session context: it calls a callback at
  `netctx+0x11388 + 4*id` **immediately and synchronously inside the parse** if one is registered
  (`0xD33D24`), and it bumps a saturating one-byte pending counter at `netctx+0x11468 + id`
  (`0xD33D4C`), read and cleared by the poller `0xD33F8C`. Only ten ids are ever polled — `3`,
  `0x1C`, `0x1D`, `0x1E`, `0x22`, `0x24`, `0x27`, `0x28`, `0x29`, `0x37` — so any other event
  reaches the game **only** through the callback table. The value is handed to the callback and
  otherwise dropped; nothing queues. Enumerating every `bl 0xD33CD8` gives 49 sites with 49
  distinct ids, one per command parser, so the id says which command arrived and nothing about what
  is rendered. Full mechanism and its consequences: `dev/docs/PROTOCOL.md` "UI events: how
  0xD33CD8 dispatches".

seq:
  - id: notice_code
    type: u4
    doc: |
      [ELF] read at 0xD50348 -> record+0x00. **The notice discriminator.** 0xD503F4-0xD50418
      subtracts 19152 and, when the unsigned result is `<= 8`, jumps through a nine-entry table
      to the handler for that code; anything else is stored and ignored. So the legal values
      are **19152..19160 (0x4AD0..0x4AD8)** and nothing else does anything.
      It doubles as the "slot occupied" marker: 0xD346DC treats a non-zero word here as "a
      notice is pending", which is why 0 must never be sent.
      **Not a result code and not a count** - it is neither sign-extended into 0xD32E70 nor
      used as a loop bound; it is a jump-table index. Stated because the leading-integer
      ambiguity has shipped a live bug in this project before.
      [UNKNOWN] which of the nine codes means what: the arms are reached only through the table
      and each would need tracing separately.
  - id: notice_flags
    type: u1
    doc: |
      [ELF] read at 0xD50360 -> record+0x04, and live in r11 across the `bctr`, so every one of
      the nine handlers receives it.
      **Bit 0 (value 1) decides whether `text` is on the wire at all**: 0xD503A0-0xD503A8
      (`lbz r0,116(r1)` / `clrldi. r9,r0,63` / `beq`) skips the 256-byte read when the bit is
      clear. **The packet is therefore 269 bytes or 13.**
      **CORRECTED 2026-08-02**: `text` now carries `if: (notice_flags & 0x01) != 0`, confirmed
      byte-exactly by a third independent ELF pass. Note the record is memset and memcpy'd at
      276 bytes - the MEMORY size, which never appears on the wire; the earlier reading got the
      269 right and simply walked through the `beq`. Superseded note: not changed here because
      sizes are evidence and this batch may only rename
      and document; flagged for a structural correction. A server that clears bit 0 and still
      sends the text block leaves 256 bytes in the stream.
      The other seven bits are [UNKNOWN].
  - id: notice_arg_a
    type: u4
    doc: "[UNKNOWN] read at 0xD50378 -> record+0x08. Reaches the handlers only inside the 276-byte copy that 0xD346C8 hands out, so which arm consumes it depends on `notice_code`; no individual reader traced."
  - id: notice_arg_b
    type: u4
    doc: "[UNKNOWN] read at 0xD50390 -> record+0x0C. Same as above. Note the record's last four bytes, +0x110..+0x113, are memset to zero and never written from the wire."
  - id: text
    size: 256
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    if: (notice_flags & 0x01) != 0
    doc: |
      [ELF] 256-byte raw read (0xD503B8, 0xD5D018 with len 256) into r1+128 = record+0x10, with
      the reader's NUL at record+0x110. Width is certain. **Conditional on `notice_flags` bit
      0.** "text" remains [INFERRED] - from the width, from 0xD5D018's NUL-terminating
      behaviour, and from the fact that a presence bit gating exactly this field is what an
      optional message body looks like. No renderer was traced.
