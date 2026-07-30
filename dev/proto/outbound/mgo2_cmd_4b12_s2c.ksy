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

  **Wire record = 48 bytes; client struct = 60** (traced 2026-07-30). The parser stages each
  record in a 60-byte scratch at `r1+116` (memset at 0xD560B0) and appends it with two string
  moves at 0xD56204-0xD56214 to `list+16+n*60`, count at `list+4`,
  `list = session[+0x10000+6404] + 0x20000 + 10344`. Wire-to-struct, therefore:
  `clan_id` +0x00, `name` +0x04 (client NUL at +0x14), `member_count` +0x18, `leader_name` +0x1c
  (NUL at +0x2c), then the four trailing bytes land at **+0x38, nowhere, nowhere and +0x30**, and
  `founded_at` at +0x34. The four bytes all pass through a single one-byte scratch at `r1+112`,
  which is why two of them cannot survive — see `discarded_29`.

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
      - id: row_display_flag
        type: u1
        doc: |
          [ELF — NAMED 2026-07-30] Read at 0xD56158 into the one-byte scratch at `r1+112`, then
          copied to **client struct +0x38** (`lbz r0,112(r1)` / `stb r0,172(r1)` at
          0xD56168-0xD56174; staging base is `r1+116`, so `172 - 116 = 56`).

          **Bit 0 drives a per-row UI element flag.** `0xAF5598` — the clan-list row decorator,
          called 15 times from the five list builders in 0xABFF54-0xAC3834 — does
          `lwz r9,0(r5)` (the row pointer out of the list node), `stw r9,48(r3)` (the row pointer
          into the row's element descriptor at +48), then `lbz r0,56(r9)` / `clrlwi r0,r0,31` at
          0xAF55D0-0xAF55D4. Set takes the arm at 0xAF55E0, which **sets** flag `0x00400000` on the
          element named by `descriptor+0` (`oris r0,r9,16448` at 0xAF5614); clear takes 0xAF56A8,
          which **clears** it (`rlwinm r0,r9,9,1,31` / `rotlwi 23` at 0xAF56DC). Both arms then set
          `0x40000000`, which looks like a redraw bit.

          So the byte shows or hides one element of every clan-list row. **The polarity is not
          established** — nothing here says whether `0x00400000` means shown or hidden — and the
          element is identified only by an id the descriptor carries, so what is being toggled is
          still [UNKNOWN]. We send zero, and the list renders, so zero is at worst the duller of
          the two states.

          Only bit 0 is ever tested; bits 1-7 have no reader.
      - id: discarded_29
        type: u1
        doc: |
          [ELF — DEAD 2026-07-30] **The parser reads this byte off the wire and throws it away
          before anything can see it.** Not "no reader found" — the discard is two instructions
          apart and is a proof.

          All four trailing bytes are read through the same one-byte scratch slot `r1+112`
          (`r29 = r1+112`, set at 0xD5614C). The read at 0xD56178 lands there, and the next
          instruction that touches `r1+112` is the *next read*, at 0xD56190, which overwrites it.
          Between them are only `nop`, `cmpwi`, `bne`, `mr r3`, `mr r4` — no `lbz r0,112(r1)`.
          Compare the neighbours, which each copy the scratch out immediately
          (0xD56168 and 0xD561BC).

          A server may send anything here.
      - id: discarded_2a
        type: u1
        doc: |
          [ELF — DEAD 2026-07-30] Same fate as `discarded_29`, one slot later: read at 0xD56190
          into scratch `r1+112`, overwritten by the read at 0xD561A8 before any copy-out. The
          instructions in between are `nop`, `cmpwi`, `bne`, `mr r4`, `mr r3`.

          The old note that "these four bytes are read as four separate u8, not one word" is
          correct and is now sharper: they are four separate reads through **one** scratch byte,
          and only the first and the last survive it.
      - id: dead_2b
        type: u1
        doc: |
          [ELF — DEAD 2026-07-30] Read at 0xD561A8 into scratch `r1+112`, then **zero-extended into
          a whole word** at client struct **+0x30**: `lbz r0,112(r1)` at 0xD561BC, `stw r0,164(r1)`
          at 0xD561C8 (`164 - 116 = 48`). So unlike `discarded_29`/`discarded_2a` it *is* stored —
          it is dead one level further out.

          **[ELF — NEGATIVE 2026-07-30] Nothing reads clan-list row +0x30.** The scan that
          establishes it, which is stronger than a displacement sweep because the row pointer's
          escape route is closed:

          * Rows live at `list+16+n*60`, `list = session[+0x10000+6404] + 0x20000 + 10344`
            (0xD56078, `mulli r4,r4,60` at 0xD561F0). The literal 10344 appears at eleven sites,
            **all of them inside the 0xD54000-0xD5A200 net layer** — no UI code computes the base.
          * The generated accessor `GetClanListRow(session, i)` at **0xD59FD8** is a **dead
            accessor**: zero `bl` sites, its OPD descriptor at 0x102A280 is referenced nowhere in
            the image, and the file is `ET_EXEC` with no relocation sections, so there is no third
            way to reach it. (Its siblings are alive: the roster's 0xD5A0A8 has three callers, the
            96-byte list's 0xD5A13C has one.)
          * The UI therefore reaches rows exactly one way — `0xD54420`, the "give me the clan-list
            object" accessor, which has **seven** callers (0xABFC80, 0xAC1034, 0xAC11A4, 0xAC27EC,
            0xAC2958, 0xAE30F0, 0xAE3108). Two of them walk the rows with `addi r31,r31,60` /
            `addi r29,r29,60` (0xAC108C, 0xAC286C) and push the row *pointer* into a UI list node
            (`stw r31,0(r3)`); the others read only `list+8`/`list+12`, the page indicator.
          * From the node the pointer escapes only into `descriptor+48` (0xAF55CC). The **only**
            dereferences of `descriptor+48` in the image are 0xAF3C14 and 0xAF3D48, and both go
            straight on to `lwz r3,52(r9)` — `founded_at`, nothing else.

          So the whole set of reads off a clan-list row is: `+0x34` (0xAF3C2C, 0xAF3D6C) and
          `+0x38` bit 0 (0xAF55D0). `+0x30` is written by the parser and never looked at again.
      - id: founded_at
        type: u4
        doc: |
          [CONFIRMED 2026-07-27] The clan's founding date, Unix seconds, read at 0xD561CC
          (-> r1+168, i.e. client struct **+0x34**). Last field of the record; it renders as the
          list's date column.

          [ELF 2026-07-30] The renderer is now anchored: `0xAF3BA0` and `0xAF3CC8` load the row
          pointer out of `descriptor+48`, do `lwz r3,52(r9)` (0xAF3C2C / 0xAF3D6C) and hand the
          value to the date formatter `0x8843CC`, whose output becomes the text of the element
          named by `descriptor+8`. That is independent confirmation that this field is a date and
          that it sits at struct +0x34.
