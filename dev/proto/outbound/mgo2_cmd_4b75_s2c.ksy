meta:
  id: mgo2_cmd_4b75_s2c
  title: "MGO2 0x4b75 — clan APPLICANT rows, 93-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **The clan applicant list, and it is UNEXERCISED.** Middle packet of the 0x4b74 / 0x4b75 /
  0x4b76 triple answering 0x4b73. [CONFIRMED LIVE 2026-07-27] that **the client never sends
  0x4b73**: clan APPLICATIONS are delivered as MAIL instead — mailbox type 0x10 on 0x4820, where
  0x0f is ordinary mail — and a leader accepts or declines from the mailbox with 0x4b30 / 0x4b32.

  So this triple has never been on the wire, nothing here has been rendered, and a server can serve
  it or not without any screen noticing. Everything below stays [ELF]/[UNKNOWN] until that changes.

  One consequence worth recording: the 64-byte text field below has no source. An application
  carries no message — 0x4b42 sends only a clan id — so nothing on the wire ever fills it.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD55E40**, which re-checks the id (`cmpwi r0,19317`) before reading anything.

  Middle packet of the 0x4b74 / 0x4b75 / 0x4b76 triple (see mgo2_cmd_4b74.ksy). No request-slot
  update.

  **Count source: size-driven, no count field** (0xD5CEB0 test at 0xD55ED8, loop back at
  0xD55FCC). Records are appended at list+8+n*96 with the count at list+4; the client refuses at
  n > 31, so at most **32** records. List object: session[+0x10000+6404] + 0x20000 + 29724.

  Wire record = 93 bytes; client struct = 96. Wire-to-struct, from the staging buffer at `r1+112`
  (memset 96 at 0xD55ECC, appended by `0xDC95C0` at 0xD55FB8): `+0x00` u4 (0xD55EF0),
  `+0x04` 64 raw (0xD55F10, client NUL at +0x44), `+0x45` 16 raw (0xD55F30, NUL at +0x55),
  `+0x56` u1 (0xD55F4C), `+0x58` u4 (0xD55F68), `+0x5C` u4 (0xD55F84). Every offset in the field
  list below is confirmed against those six `addi r4,r1,N` instructions.

  ## The list object is SHARED, and it is not "the applicant list"

  [ELF 2026-07-30] `session[+0x10000+6404] + 0x20000 + 29724` is also the destination of the
  **0x4685 / 0x4686 / 0x4687** parsers (`addi ...,29724` at 0xD3AB20, 0xD3AC1C, 0xD3B488, off the
  identical `lwz r9,6404(r9)` / `addis r9,r9,2` base), which write **28-byte** records into it.
  So this is a general-purpose list slot reused by whichever screen filled it last, not a
  dedicated applicant array — and a server that somehow got 0x4b75 onto the wire while a friend
  list was live would be overwriting it.

  ## There IS a consumer screen, and it looks vestigial

  The earlier claim that "nothing here has been rendered" is right about the wire and wrong about
  the code. `GetApplicantRow(session, i)` at **0xD5A13C** (`mulli r9,r4,96` at 0xD5A174, rows at
  `list+8+i*96`) has exactly one caller, **0xA8A098**, inside a row loop at 0xA8A080-0xA8A224 that
  paints four columns from each record; the matching count accessor 0xD5A194 is called once, from
  0xA8A814. Since the client never sends 0x4b73 the loop can never see a record, which is the
  frame for reading everything below: these are the fields a screen *would* show.

  The strongest single sign that the screen is unfinished is in `unknown_00` — read on.

  Read primitives (from the primitive table at 0xD5C844+): 0xD5CB8C u1, 0xD5CC14 u2,
  0xD5CC64 / 0xD5CCD8 u4 (identical twins — see the CORRECTION below), 0xD5D018 fixed byte
  block of `len` (memcpy + a client-side NUL at
  dest[len]; the wire consumes exactly `len`), 0xD5CEB0 "cursor < payload_length?" (-1 at end;
  this is what makes a list size-driven), 0xD5C844/0xD5C858 begin/end read. An earlier revision
  added: "In each signed/unsigned pair the LOWER address is the signed accessor (write-side
  proof: 0xD5C95C uses `sraw`, 0xD5C9BC uses `srw`)." **That claim is SUPERSEDED — see the
  CORRECTION below.** Request slots: 0xD32E08(session,slot,state) ->
  session+0x160+slot*4+8; 0xD32E70(session,slot,value) -> session+0x330+slot*4+12.
  UI events: 0xD33CD8(session,event,arg).

  CORRECTION (verified 2026-07-26, whole-function compare at every width): that rule is wrong,
  and it is wrong on the READ side at ALL widths, not just at u32. Each "signed/unsigned pair"
  is instruction-for-instruction identical — same bound check, same byte-assembly loop, same
  `extsb` on each byte, same store width:
    * u8:  0xD5CB54 == 0xD5CB8C  (bound `cmpwi 1023`, `lbzx`/`stb`, cursor += 1)
    * u16: 0xD5CBC4 == 0xD5CC14  (bound `cmpwi 1022`, two `lbzx`, `sth`,  cursor += 2)
    * u32: 0xD5CC64 == 0xD5CCD8  (bound `cmpwi 1020`, 4-iteration loop, `stw`, cursor += 4)
    * u64: 0xD5CD4C == 0xD5CDC0  (bound `cmpwi 1016`, 8-iteration loop, `std`, cursor += 8)
  So **no read primitive is a signed accessor at any width**, and "0xD5CBC4 s2" / "0xD5CC64 s4"
  are as unfounded as the u32 claim. Signedness comes from the CALLER — the value being
  reloaded with `lwa`, or being compared against known-negative error constants — never from
  the primitive's address.

  The write side does not rescue the rule either. There are **three** u32 write primitives, not
  a signed/unsigned pair: 0xD5C95C (`sraw`), 0xD5C9BC (`srw`) and 0xD5CA1C (`sraw`). The
  sraw/srw difference is inert because each iteration masks with `and r0,r4,r0` where r0 =
  `slw r7,r10` of 255, and then stores only the low byte with `stbx`: for shifts 16/8/0 the
  masked operand is non-negative in 32 bits so the two shifts agree outright, and for shift 24
  they differ only in bits above bit 7, which `stbx` discards. Identical bytes on the wire.

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
  - id: records
    type: record
    repeat: eos
    doc: "[ELF] Size-driven; no leading count."
types:
  record:
    doc: "93 wire bytes -> 96-byte client struct."
    seq:
      - id: unknown_00
        type: u4
        doc: |
          [ELF] struct+0x00, read at 0xD55EF0. **The consumer treats this address as a time value
          and renders it as a date** — and does so at the wrong width, which is the best evidence
          on this page that the whole screen is vestigial.

          At 0xA8A0B0-0xA8A0D0 the row pointer goes straight into `0xDC9358`, which does
          `sc` 144 (the current-time syscall), then **`ld r0,0(r28)` — an EIGHT-byte load at
          row+0** — adds a minutes-to-seconds offset and calls `0xDCFEA0`, returning a broken-down
          time. That is handed to `0xDCC7C8(dest, 32, fmt, tm)` with `fmt = "%Y/%m/%d %H:%M:%S"`
          (`0xE14040`), and the result becomes the row's first column.

          **The parser writes a 4-byte value here and a 64-byte block immediately after it**
          (0xD55F10), so the u64 the consumer loads is `unknown_00 << 32 | first four bytes of
          text_04`. Those cannot both be right. Since the containing triple is never requested —
          the client never sends 0x4b73, applications arrive as mailbox type 0x10 instead — the
          most economical reading is that the screen was left unfinished, not that the field is
          8 bytes wide.

          **NOT renamed deliberately.** "A timestamp" is what the only reader does with it, but the
          width disagreement means we cannot say this u32 *is* the timestamp. Naming it would
          launder the contradiction. If 0x4b73 ever gets exercised, this is the field to watch.
      - id: text_04
        size: 64
        type: str
        encoding: ASCII
        doc: |
          [ELF] struct+0x04, 64 bytes fixed (client NUL at +0x44). 64 is comment/message sized.

          [ELF 2026-07-30] **It is rendered**: at 0xA8A134 the consumer does `addi r5,r27,4` — the
          address of this field — and passes it as the text of the element named by the column-id
          table entry `[r28+16]` (`0x244340` / `0x2452A0` / `0x246EC0` at 0xA8A110-0xA8A148). So
          the client does have a place to put it.

          What it never has is a **source**: 0x4b42, the apply-to-clan request, sends only a clan
          id, so no message ever reaches the server to put here. [UNKNOWN] what it was meant to
          carry.
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: |
          [ELF] struct+0x45, 16 bytes fixed. [UNKNOWN] whose name — the applicant's is the obvious
          reading and remains unevidenced.

          [ELF 2026-07-30] It is rendered as one of the row's columns: 0xA8A144 computes
          `addi r27,r27,69` (= `struct+0x45`, this field) and 0xA8A174-0xA8A180 sets it as the text
          of the element named by `[r28+32]`.
      - id: unknown_56
        type: u1
        doc: |
          [ELF] struct+0x56, read at 0xD55F4C. [UNKNOWN].

          **[ELF — NEGATIVE 2026-07-30] No reader.** The consumer loop 0xA8A080-0xA8A224 touches
          the record only at +0 (via 0xDC9358), +4, +69, +88 and +92. Image-wide, every
          `lbz rX,86(rY)` is outside the clan/UI code entirely (0x263584, 0x269E10, the 0x4EAxxx
          and 0x5ECxxx and 0x6FExxx bands), and nothing takes the address of `struct+0x56`. The
          only other route to a record is `GetApplicantRow` 0xD5A13C, whose single `bl` is the one
          in that loop.
      - id: unknown_58
        type: s4
        doc: |
          [ELF] struct+0x58, read at 0xD55F68. [UNKNOWN].

          [ELF 2026-07-30] **Rendered as a decimal number** in one of the row's columns:
          0xA8A188 `lwz r3,88(r26)`, `extsw`, `bl 0xCFB8C8` (the integer-to-string helper), then
          set as the text of the element named by `[r28+48]`. That says it is a *number* and says
          nothing about which number.

          [ELF 2026-08-01] **The column's element name is now resolved, and it is why the ELF
          cannot name this field.** `r28 = r17 + 4*row` with `r17 = r1+200` (`addi r17,r1,200` at
          `0xA89ED8`), so the loop reads a 5-column x 4-row table of element-name hashes built on
          the stack at `0xA89F00`-`0xA8A04C` — column stride 16, row stride 4. Resolving each
          store against the screen module's mini-TOC (`lwz r30,-27996(r2)`, r2 = `0x10353A8`, so
          r30 = `0xFF4D18`) gives the whole table:

          | col | read at | stack slots | element names | source |
          | --- | --- | --- | --- | --- |
          | 0 | `0(r28)` | 200-212 | `STRING_low1_DATE`..`low4_DATE` | `unknown_00` via `0xDC9358` + `strftime` |
          | 1 | `16(r28)` | 216-228 | `STRING_low_1_1`..`low_4_1` | `text_04` |
          | 2 | `32(r28)` | 232-244 | `STRING_low_1_2`..`low_4_2` | `name` |
          | 3 | `48(r28)` | 248-260 | `STRING_low_1_3`..`low_4_3` | **this field** |
          | 4 | `64(r28)` | 264-276 | `STRING_low_1_4`..`low_4_4` | `unknown_5c` |

          The names are **purely positional** — row N, cell M. Unlike `NULL_OPENmail_SUBJECT` or
          `STRING_F_LIST_LOBBY`, they carry no vocabulary, so the developer-element-name lever
          (FIELD_MAPPING.md, batch 3c) is exhausted here: the caption is bound to `STRING_low_N_3`
          in the **layout file**, not in the ELF. That is the thing that would have to be read to
          name this field statically, and it is on the disc, not in the binary.

          **Two corrections to this file's own account of the screen.** It paints **five** columns
          per row, not four — the date column was not counted. And the row count is fixed at
          **four**: `r29 = min(r29 - r16, 0)` then `r25 = r29 + 4` (`0xA8A044`-`0xA8A050`), so the
          loop can never run more than four times, which matches the four-row element table exactly
          and caps what the 32-record parser limit could ever display.

          **The `s4` here is not evidence and should be treated as suspect.** Its justification was
          "read with the SIGNED accessor 0xD5CC64" — the rule this file's own CORRECTION block
          declares superseded: 0xD5CC64 and 0xD5CCD8 are instruction-for-instruction identical, so
          the accessor's address carries no signedness. The caller does `extsw` before formatting,
          which is consistent with signed but is also what you would emit for a 32-bit value in a
          64-bit register either way. Width and offset are exact regardless; the type is left
          alone here on purpose (see dev/proto/README.md) and flagged instead.
      - id: unknown_5c
        type: u4
        doc: |
          [ELF] struct+0x5c, last 4 bytes of the record, read at 0xD55F84. [UNKNOWN].

          [ELF 2026-07-30] **Rendered as a decimal number**, in the column after `unknown_58`'s:
          0xA8A1D4 `lwz r3,92(r26)`, `extsw`, `bl 0xCFB8C8`, then set as the text of the element
          named by `[r28+64]`. Same status as its neighbour — provably a displayed integer, with
          no evidence of what it counts.

          [ELF 2026-08-01] Its element is `STRING_low_N_4`, the last of the five columns; the full
          column table, how it was resolved and why it cannot name the field are under
          `unknown_58`. Same conclusion: the caption binding lives in the layout file on the disc,
          not in the ELF.

          **What would decide both fields.** Nothing static — the ELF has been closed out. The
          experiment is to make the client send `0x4b73` (it never does on its own; applications
          arrive as mailbox type `0x10`), answer with a `0x4b74`/`0x4b75`/`0x4b76` triple carrying
          distinct sentinels in `+0x58` and `+0x5C`, and read the two right-hand columns off the
          screen against its printed captions. Note the row-0 hazard recorded under `unknown_00`:
          the date column loads eight bytes from `+0`, so the first column will be garbage
          regardless and is not evidence about anything.
