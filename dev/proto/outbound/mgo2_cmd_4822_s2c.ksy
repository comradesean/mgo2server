meta:
  id: mgo2_cmd_4822_s2c
  title: "MGO2 0x4822 — mailbox entry (server -> client)"
  endian: be
doc: |
  Request/reply neighbours: `../inbound/mgo2_cmd_4820_c2s.ksy` asks for the list;
  `../inbound/mgo2_cmd_4840_c2s.ksy` (open) and `../inbound/mgo2_cmd_4880_c2s.ksy` (delete) both
  echo this entry's `category` and `index` back to identify a letter.

  Item packet of the 0x4820 mailbox triple (0x4821 start / 0x4822 entries / 0x4823 end). Parser
  0xD536AC (ends 0xD53850), dispatcher stub 0xD39504. **SERVED since 2026-07-26** — see the LIVE
  section below. The following paragraph records the state before that and is kept for the
  provenance of the layout, not as a description of what we do. PROTOCOL.md: "never
  sent — the mailbox is always empty", which is reference parity for the mail selector 0x0f.

  ELF CONFIRMATION OF A TIER-4 LAYOUT. PROTOCOL.md carries a 266-byte entry transcribed from
  Nomad (used there only for clan applications, selector 0x10): `u8 mtype(0), u8 index, u8 1,
  name[128], comment[128], u32 time, u8 0, u8 important, u8 read`. The parser's read sequence is
  exactly that, field for field and width for width, and sums to the same 266 bytes. Widths and
  order are therefore [ELF]-confirmed; the *names* remain tier 4 and are marked below.

  Trace, in order: reader open 0xD5C844 (0xD53704); u8 0xD5CB54 → stack temp (0xD53714); u8
  0xD5CB8C → recordBase+0 (0xD53734); u8 → recordBase+1 (0xD5374C); 128-byte block 0xD5D018
  → recordBase+2 (0xD53768); 128-byte block → recordBase+131 (0xD53784, i.e. after the previous
  block's NUL); u32 0xD5CCD8 → temp, widened to 64 bits at 0xD537B8 (0xD5379C); u8 → +392,
  u8 → +393, u8 → +394 (0xD537BC / 0xD537D4 / 0xD537EC); reader close; then 0xD347E4 is called
  with the FIRST u8 (sign-extended, 0xD53810) and the record pointer.

  ## LIVE 2026-07-26 — served, and the category byte is a routing INDEX, not a type

  We now send this. What the trace and the live session together establish:

  * **Wire 0x00 is a mailbox INDEX passed unchecked to 0xD347E4** (`mail_store_add`). Valid values
    are 0..3 — four arrays of 16 records, stride 280, at `mailBlock+0x1E268` — plus 4, a
    pseudo-category meaning "flat view", which folds to index 0 with a limit of 64. The router
    does NOT range-check it (`extsb r3,r11` at 0xD34844); the only guard is `count < limit` at
    0xD34854, and the count is read from `counts[idx]` at `mailBlock+0x1E260`, an array **4 bytes
    wide**. The UI-facing wrappers 0xD5415C and 0xD542A8 both validate (`cmplwi cr6,cat,4; bgt →
    -24`); only the packet path does not.
  * **We sent 0x0F here and it corrupted the client heap.** `counts[15]` reads `mailBlock+0x1E26F`
    = byte 7 of category 0's record 0, i.e. `name[5]` of the first inbox letter; when that byte is
    below 16 the record is written at `mailBlock+0x1E268 + 15*4480 = mailBlock+0x2E8E8`, which is
    **26,816 bytes past the end of the 0x28028-byte allocation**, once per entry, and `name[5]` is
    then incremented. The 0x0F came from the 0x4820 *request* selector (a compile-time `li r9,15`
    at 0xD534C8) and has no business in the record. Do not echo the request byte here.
  * **Category 1 is the Sent tab** [CONFIRMED live 2026-07-26: an entry sent with 1 rendered under
    Sent, and the client's 0x4840 echoed `01 00` back]. Category 0 is the default tab, stored
    unconditionally at 0x8E28A0 / 0x8E6C20 / 0x8EACC4 / 0x8EBFA8 / 0x8EDBE0. Category 3 is the
    priority tab — the screen checks it first on open and force-selects it when it holds unread
    mail (0x8E5238-0x8E5388) — and the "new mail" badge sums unread(0) + unread(3) only
    (0x8F05A4), so 1 and 2 are never notified. Which of 0/3 is Inbox vs GM, and whether 2 is
    reachable at all, is [UNKNOWN].

  ## THERE IS NO DELETION FIELD, IN EITHER DIRECTION

  The nine fields below sum to exactly 266 bytes with nothing spare, so a per-side "deleted" flag
  cannot be expressed here — and no other mailbox command carries one (0x4880 delete is
  `{s1 category, u1 index}`, 0x4841 read is a result plus an opaque 708-byte block). Deletion is
  **absence**: 0x4821 zeroes all four category counters (0xD538D4-0xD538E0) and the client rebuilds
  each list purely from the 0x4822 entries that follow. So "deleted by the recipient but still in
  the sender's Sent list" is representable only in server storage, never on the wire.

  ONE RECORD PER PACKET — there is no 0xD5CEB0 loop test and no back-edge in this function,
  unlike 0x4582/0x4602/0x4902. Each mailbox entry needs its own 0x4822 packet.

  Note the first u8 is NOT part of the stored record: it is read into a separate slot and passed
  as an argument, so it selects where the record goes rather than describing it.
doc-ref: dev/docs/PROTOCOL.md "0x4820 — get messages"
seq:
  - id: mailbox_type
    type: u1
    doc: |
      [CONFIRMED live 2026-07-26; OBSERVED.md "The mailbox, live"] The mailbox **CATEGORY**:
      which of the client's four 16-record arrays this entry is filed into. Read first, then
      sign-extended and passed as the first argument of 0xD347E4 with the record (0xD53714).

      Valid values 0..3, plus 4 = flat view aliasing category 0 with a limit of 64. **Category 1
      is the Sent tab** (live). 0xD347E4 does NOT range-check it — sending the 0x4820 request's
      selector 0x0F here wrote 280 bytes 26,816 past the end of the client's mail arena and
      coincided with a tab vanishing from the screen. This is NOT the mailbox selector; the
      tier-4 name "mtype" and Nomad's constant 0 both describe the wrong thing. See the header.
  - id: index
    type: u1
    doc: |
      [CONFIRMED live 2026-07-26] The letter's **handle within its category**, not a display
      position: the client echoes this byte back in `0x4840` (open) and `0x4880` (delete) to say
      which letter it means — observed as `01 00` and `01 01`. Every entry in a category needs a
      distinct value or every row addresses the same letter.
      [ELF 0xD53734] recordBase+0x00. Tier-4 name "index", now earned.
  - id: unknown_0x02
    type: u1
    doc: "[ELF 0xD5374C] recordBase+0x01. Nomad sends the constant 1; meaning [UNKNOWN]."
  - id: name
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[ELF 0xD53768, 0xD5D018 r5=128] recordBase+0x02, NUL-terminated at +0x82 in the struct. Tier-4 name \"name\"."
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: "[ELF 0xD53784, r5=128] recordBase+0x83. Tier-4 name \"comment\"."
  - id: time
    type: u4
    doc: |
      [ELF 0xD5379C] Widened to 64 bits when stored (std at 0xD537B8) — the same time_t-shaped
      widening 0x4902's open/close times get, which is the only support for the tier-4 name
      "time". [INFERRED] Unix timestamp.
  - id: message_type
    type: u1
    doc: |
      [ELF 0xD537BC] -> record+272 (not +392; the destination offsets in the trace above are from
      the parser's own base). **A type discriminator, not padding**: the mailbox screen
      special-cases the value 3 at 0x8EA158. What 3 selects is [UNKNOWN] — a system or GM letter
      is the obvious guess and is NOT evidenced. Nomad sends 0 and so do we.
  - id: important
    type: u1
    doc: |
      [ELF 0xD537D4] -> record+273. Tier-4 name "important", still **unverified** — no client-side
      predicate reads it anywhere in the mailbox module. It IS echoed back to the server in the
      0x4800 send (struct+0x110), so the client round-trips it. We send 0.
  - id: read
    type: u1
    doc: |
      [ELF 0xD537EC] -> record+274. Last byte of the 266. **Tier-4 name "read" is now CONFIRMED**:
      every unread tally in the UI counts records whose value here is 0 (0x8E5298, 0x8F0638,
      0x8F08E8, stride 280 from list+274), and opening a letter sets it to 1 at 0x8E2CD8.
      So 0 = unread, nonzero = read. This is the ONLY per-record state byte the client acts on —
      note it is a read flag, not a deletion flag; see the header.
