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

  ## THE RECORD AND THE COMPOSE BUFFER ARE THE SAME STRUCT (2026-07-31, batch 3c)

  This is the lever that resolved four things at once, and it is a *proved* offset bijection, not
  an inference from neighbouring names — there is a literal `memcpy` between the two objects.

  * `0xD34728` is `MailRecordCopy(dst, src)`: `+0`, `+1`, 128 bytes at `+2`, 128 bytes at `+131`,
    then `ld/std +264`, `lbz/stb +272`, `+273`, `+274` (`0xd347a4`-`0xd347c0`). That is the whole
    record, and it is the canonical field list.
  * `0xD34220` is `MailRecordClear(rec)`: `rec[0] = -1` (0xFF is the empty-slot sentinel),
    `rec[1] = 0`, `bzero(rec+2, 129)`, `bzero(rec+131, 129)`, `rec[274] = 0`, `*(u64*)(rec+264) =
    0`, `rec[272] = 0`, `rec[273] = 0`. Note the 129s: `+130` and `+259` are NUL-terminator slots,
    which is why the two 128-byte blocks are not adjacent in the struct even though they are on
    the wire.
  * `0xD5415C`'s open path (`0xd541fc`-`0xd54208`) computes `records[cat] + idx*280` and calls
    `MailRecordCopy` with the destination `*(session+6404) + 0x20000 - 8576` — **the compose
    buffer**, the `r24` of `../inbound/mgo2_cmd_4800_c2s.ksy`.

  So the current-letter object is:

  ```
  base = *(session+6404) + 0x20000 - 8584          (cleared by 0xd342a4)
    +0    u8    category selector, -1 = none
    +8    ----  a 280-byte MAIL RECORD == this packet's fields 2..9, in order
    +288  ----  709 bytes: the 0x4841 body block plus its NUL
  ```

  `base+8` is the `0x4800` builder's base, so the send-side offsets transfer directly:
  `+1` `recipient_count`, `+2` the eight 16-byte `recipients` slots, `+131` `subject`,
  `+272` `destination`, `+273` the byte `0x4800` sends at wire `0x3c6`, `+288` `body`.

  ## THE ROW PAINTER, WHICH THREE FIELD DOCS HERE WERE WRITTEN WITHOUT

  `0x8E2F30` is the mailbox list painter. It hashes 48 UI element names out of the module TOC
  (`r30 = 0xFEFA80`) — `NULL_jyusin_NAME_01`..`_08` / `_DATE_` / `_TIME_` and the same three
  families under `NULL_tochu-sousinzumi_` — i.e. **eight rows × {name, date, time} × two tabs**.
  (`jyusin` = 受信, received; `sousinzumi` = 送信済み, sent. These are the developers' own names and
  they independently confirm the live finding that category 1 is the Sent tab.) At `0x8e3390` it
  loads `count`/`base` from `screen+0x180000+13716/13720` and walks records at **stride 280**,
  keeping the row's record in `r25`. `0x8E8AFC` is the OPENmail (read-a-letter) painter and reads
  the copied record out of the compose buffer.

  Between them they read `+1`, `+2`, `+131`, `+264`, `+272`, `+273` and `+274`. Three fields below
  were documented as unread or unverified against a search that never reached these two functions.
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

      **[CATEGORY 2 IS A HOLE — 2026-08-04.]** Every function that hands out a category's record
      list (`0xD54134` base, `0xD5410C` count, `0xD5415C`, `0xD542A8`) was enumerated at every
      call site and the argument read at each: the literal categories appearing anywhere in the
      image are **0, 1, 3 and 4 — never 2**. Control: the same scan finds `li r4,1` at
      `0x8E7F00`, `li r4,3` at `0x8E5240`, `li r4,0` at `0x8F05E4` and `li r4,4` at `0xAD1D14`,
      so it demonstrably finds category constants. Separately, the screen's current-box word is
      written at **eleven** sites and every one stores 0 or 3. An entry filed under 2 would be
      invisible and uncounted, so 2 is not a spare tab — it is a hole. (An earlier note in the
      server proposed trying `=2` as an experiment; it must not be run.)

      **[THE FOUR TABS, READ FROM THE DISC — 2026-08-04.]** The menu is built from disc string
      resources `text00`..`text03` (`0x8E3D84`), and **only items 0 and 3 get an unread count
      appended** via `%s(%d)`, from the category-0 and category-3 tallies at `+0x35A0`/`+0x35A4`.
      The lobby's extracted resources carry the four labels as consecutive records at file
      indices **17981-18010**, in menu order:

      | item | label | help text |
      | --- | --- | --- |
      | 0 | 受信BOX / **Inbox** | *"View mail you have received. Up to 16 messages can be stored."* |
      | 1 | 新規メール作成 / **Create New Mail** | *"Send mail to up to 8 players simultaneously."* |
      | 2 | 送信済みBOX / **Sent** | *"View mail you have sent. Up to 5 messages can be stored."* |
      | 3 | 重要なお知らせ / **Announcements** | *"Notices from the administrative team will appear here. Be sure to read these whenever you receive one."* |

      (A fifth label, 編集途中BOX / **Drafts**, exists at 18005-18010 but has no help text in that
      run and is not one of the four.)

      So **category 0 = Inbox and category 3 = Announcements** — the two counted received boxes,
      matching the two the client sums for its "new mail" badge (`0x8F05A4`) and the one it
      force-selects when it has unread (`0x8E520C` -> `li r0,3`). The rest of the shape follows:
      item 1 is a compose action rather than a box, and item 2 (Sent) is category **1**, which is
      why the Sent screen hardcodes its category at `0x8E7EF0` rather than reaching it through the
      current-box selector.

      Two caps appear in that help text and only one of them is a rule. The Inbox's **16** is
      enforced by the client: `0xD34858` compares the category counter against the limit and
      `bge`-skips the record, so a 17th entry is silently dropped on arrival — it does not evict
      an existing one. The Sent box's **5** is *not* a client rule at all; the router loads
      `li r10,16` as the limit for every category and only raises it to 64 for category 4, so the
      Sent array holds 16 like every other. The 5 describes the original server's retention
      policy, and the sentence is the only evidence of it — there is no counter, no eviction and
      no error code behind it. Note also that both caps count **undeleted** entries, not unread
      ones; unread is the separate byte at `+274`.

      **What the player sees:** this byte is the filing clerk. It decides which tab a letter lands
      under and is never itself displayed. Wrong-but-valid puts the letter in the wrong list;
      out-of-range corrupts the heap, which is what the `0x0F` incident was.
  - id: index
    type: u1
    doc: |
      [CONFIRMED live 2026-07-26] The letter's **handle within its category**, not a display
      position: the client echoes this byte back in `0x4840` (open) and `0x4880` (delete) to say
      which letter it means — observed as `01 00` and `01 01`. Every entry in a category needs a
      distinct value or every row addresses the same letter.
      [ELF 0xD53734] recordBase+0x00. Tier-4 name "index", now earned.
  - id: name_count
    type: u1
    doc: |
      [ELF 2026-07-31, batch 3c] **How many of the eight 16-byte name slots in `name` are
      populated.** Was `unknown_0x02`, [UNKNOWN]; Nomad's constant 1 happens to be a sane value
      for a single-correspondent letter, but the name it had was not.

      recordBase+0x01 (`0xD5374C`), which the struct bijection above puts on the same byte the
      `0x4800` builder sends as `recipient_count` (`0xd53fa0`, from `base-8575`), written by the
      compose screen at `0x8eedd8` (`stb r0,1(r24)`) from its recipient-table loop bound.

      **Two readers, not one** (the second added 2026-08-04), and they render *different*
      ellipses:

      - **OPENmail painter `0x8e8b94`**: `lbz r0,1(r24); cmplwi cr7,r0,1; ble` — at most 1, the
        To/From element is the plain 16-byte string at `+2`; above 1, the screen `sprintf`s
        `"%s ....."` (module TOC `-32372`, string `0xE12120`) with that same first slot, i.e.
        **"<first name> ....."** standing in for the rest of the list.
      - **List-row painter `0x8E3A1C`**: the same `<= 1` test, but above 1 it calls
        `0xDCCC28(buf, rec+2, 14)` — truncating slot 0 to **14 characters** — and appends
        **`" ..."`**, a different string (TOC `-32544`, `0xE11EE0`, three dots not five).

      Nothing renders slots 1..7 individually.

      **What it is for.** MGO2 lets one letter be addressed to up to eight people. This byte is
      how the client decides between printing the recipient plainly and printing "the first one,
      and others" — on a mailbox row (eight rows to a page, so space is tight) you get
      `Snake ...`, and on the opened letter's To/From line you get `Snake .....`. It is on the
      wire because the list is server-side; the client is shown one name and a count, never the
      other seven names.

      **Server:** we send the constant 1, which takes the plain path in both readers and is
      correct for our one-recipient model. The constant was inherited unexplained and has been
      right all along.

      Sending 0 with a populated slot 0 is therefore safe and is what makes the single-name path
      run; sending >1 appends the ellipsis whether or not further slots hold anything.
  - id: name
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF 0xD53768, 0xD5D018 r5=128] recordBase+0x02, NUL-terminated at +0x82 in the struct.
      [ELF 2026-07-31] **Not one 128-byte name — the same eight fixed 16-byte slots the `0x4800`
      send fills**, on the identical struct offset (see the header's bijection, and
      `../inbound/mgo2_cmd_4800_c2s.ksy` `recipients`, whose compose-screen loop memcpy's 16 bytes
      per occupied entry into consecutive slots at `base-8574`). `name_count` says how many are
      live. Both painters render slot 0 only — `0x8e3708` (list, via `0xaf72c0`) and `0x8e8c04`
      (OPENmail). Whose name it is is a server-side question the client never asks: it prints slot
      0 under the tab it was filed in.
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    pad-right: 0
    doc: |
      [ELF 0xD53784, r5=128] recordBase+0x83.
      [ELF 2026-07-31] **This is the letter's SUBJECT line, not a "comment".** Tier-4 name
      corrected. Same struct offset as the `0x4800` send's `subject` (`0xd53fcc`, from
      `base-8445` = `+131`), which the compose screen fills at `0x8eeac4` from its subject editor;
      and the OPENmail painter renders `+131` into the element **`NULL_OPENmail_SUBJECT`** at
      `0x8e8e78`/`0x8e8ec4` — the developers' own name for the slot.
  - id: time
    type: u4
    doc: |
      [ELF 0xD5379C] Widened to 64 bits when stored (std at 0xD537B8, to record+264) — the same
      time_t-shaped widening 0x4902's open/close times get.
      [ELF 2026-07-31] **The tier-4 name is now earned.** The OPENmail painter loads it as
      `ld r28,264(r24)` at `0x8e8cc4` and passes it straight to the shared date formatter
      `0x8843CC` (r5=128), whose two outputs fill `NULL_OPENmail_DATE` and `NULL_OPENmail_TIME`;
      the list painter does the same at `0x8e3754`/`0x8e3788` for the row's `_DATE_`/`_TIME_`
      elements. Unix seconds, rendered as the letter's timestamp.
  - id: message_type
    type: u1
    doc: |
      [ELF 0xD537BC] -> record+272 (not +392; the destination offsets in the trace above are from
      the parser's own base). **A type discriminator, not padding.**

      **[1 AND 2 ARE CLAN MAIL, AND THE BRANCH IS VISIBLE — 2026-08-04.]** `0x8E81DC`:
      `lbz r9,0x110(r9); addi r9,r9,-1; clrlwi r9,r9,24; cmplwi cr7,r9,1; bgt 0x8e8244` — so
      values **1 and 2** take one path and everything else takes the other. On the 1/2 path the
      mailbox list's **preview line does not show the letter's own subject**: the code hashes the
      element/resource name **`CLAN_SUBJECT`** (module TOC `-32380`, string `0xE120E8`) and pulls
      a canned sentence from string group `0x6B01B5`. On every other value (`0x8E8244`) it renders
      `rec+131`, the letter's own subject. A second fork at `0x8E837C` gives the 1/2 path a
      different open sound (SE 91 vs SE 93) and leaves screen flag bit 16 clear.

      **Nothing anywhere distinguishes 1 from 2** — both readers test the pair `(v-1) <= 1`. That
      is a genuine remaining unknown, not a coin flip to be resolved by picking one.

      **Server hazard, recorded rather than fixed.** Clan applications (mailbox selector `0x10`)
      are sent with `message_type = 0` and an **empty** `comment`/subject, so `0x8E81DC` takes the
      else-branch and renders 128 zero bytes — the preview line under a selected clan application
      is **blank**. With 1 or 2 the client would supply its own clan line instead. The fix is not
      applied here because it requires choosing between 1 and 2 with no evidence, and a wrong
      guess would be undetectable; filling the subject field server-side achieves the same visible
      result without asserting an enum value. There is an adjacent issue worth its own look:
      applications are filed under **category 0**, the same array as the Inbox, while `0x4840`
      resolves `{category, index}` against personal received mail.

      **3 = GAME MASTER, evidenced 2026-07-31 (batch 3c).** The doc used to read "what 3 selects is
      [UNKNOWN] — a system or GM letter is the obvious guess and is NOT evidenced". It is now
      evidenced twice over:

      * `0x8EA154`, the letter-open handler, reads `lbz r0,272(rec)` off `records[cat] + idx*280`
        and, on `== 3`, does `oris r0,r11,4` -> `stw r0,372(r31)` — it **sets bit 18 of the compose
        screen's flags word**. That is the exact bit
        `../inbound/mgo2_cmd_4800_c2s.ksy` proves is the GM selection: set by the GM menu item at
        `0x8EF098`, tested at `0x8E4B30` to grey out the recipient-list row, and the single gate on
        `li r0,3; stb r0,272(r24)` at `0x8EEAA8`.
      * record+272 **is** the byte the send reads as `destination`, by the struct bijection above.
        Opening a GM letter and replying re-sends 3 without the operator touching the To menu.

      **1 and 2 are a further pair, and they are clan mail.** Two sites test
      `(value - 1) <= 1` unsigned: `0x8e81dc` selects the element name **`CLAN_SUBJECT`**
      (module TOC `-32380`) for the preview line, and `0x8e837c` lets the open proceed with SE 91
      where every other value sets flag bit 16 and plays SE 93. That is the first tier-1 support
      for PROTOCOL.md's tier-4 note that this family carries clan applications.

      So the values with known meaning are **0 ordinary, 1/2 clan, 3 Game Master**. Nomad sends 0
      and so do we; 0 is correct for an ordinary letter.
  - id: important
    type: u1
    doc: |
      [ELF 0xD537D4] -> record+273. **Tier-4 name "important" is still unproven as a *meaning*,
      but the two claims this doc used to make about it were both wrong** (corrected 2026-07-31,
      batch 3c):

      1. "No client-side predicate reads it anywhere in the mailbox module" — **it does.** The row
         painter reads it at `0x8e3934` (`lbz r0,273(r25)`, with `r25` the stride-280 record),
         together with `read` at `+274` and `message_type` at `+272`, and picks the row's display
         state from the three:

         | +273 | +274 read | +272 | state hash passed to `0x995D80` |
         | --- | --- | --- | --- |
         | nonzero | nonzero | — | `0x0CD73E` |
         | nonzero | 0 | nonzero | `0x989DFB` |
         | nonzero | 0 | 0 | `0xF55717` |
         | 0 | 0 | — | `0xF55717` |
         | 0 | nonzero | — | branch `0x8e3d64`, a second element array at `container+320` |

         Those are 24-bit rotate-5-add resource-name hashes (`0xD25D0`), the same encoding as the
         verified `0x5C86D9` = **`ST6_ON`** this painter applies to every name/date/time element.
         The three above resolve against a disc resource, not the ELF, so the state *names* are
         not recovered — but a placeholder-free three-way split is proof the byte is displayed.

         **[MECHANISM SETTLED 2026-08-04.] The element being switched is the row's ICON, and the
         real rule is that this byte keeps the icon lit after the letter has been read.**

         The element family was recovered by name. The row painter binds a fourth element per row
         from a 16-entry hash table at `0xE11848`, holding two runs of eight *consecutive*
         hashes — `0x8847CF..0x8847D6` and `0xC8C546..0xC8C54D`. Consecutive-by-one is the
         signature of an `_01`..`_08` family, which fixes the suffix and leaves only the middle
         token; because the rotate-5-add step is invertible, a meet-in-the-middle requiring
         **both** families to match simultaneously returns exactly one answer:

         ```
         h("NULL_jyusin_ICON_01")           = 0x8847CF
         h("NULL_tochu-sousinzumi_ICON_01") = 0xC8C546
         ```

         Independently confirmed outside the ELF: `0x8847CF` occurs exactly once in the decrypted
         lobby UI package `cache.dar.dec` (offset `0x248BDC`) and `0xC8C546` once at `0x249ED8` —
         the elements exist in the shipped layout under those names.

         So the table above is a **show/hide plus state** decision on that icon. `0x245000` and
         `0x245028` are the show/hide pair (`r0 &= ~0x30` and `r0 |= 0x30` on `node[176]+16`); the
         last row of the table **hides** the icon, and `container+320` is **not** a second element
         array — it is a parallel array holding each row's *previously applied* state hash, which
         `0x8E3D64` cancels with `0x995D20` before hiding. Corroboration that this is show/hide:
         rows past the end of the list bind the same ICON element and take the identical hide path
         at `0x8E3624`-`0x8E3690` — empty rows have no icon, which is what one would see.

         Net rule: **the icon appears when the letter is unread, OR when this byte is non-zero**,
         and a non-zero value picks a distinct graphic. It never affects the Sent tab — the
         送信済み layout path (`0x8E3A10`-`0x8E3C74`) contains no icon block at all, and the
         sousinzumi hashes copied alongside are never read.

         **No other reader, with a control.** A sweep of `.text` for `lbz`/`stb` at displacement
         `0x111` returns 9 and 11 sites; the control found the three known ones (`0x8E3934`,
         `0xD347B0`, `0xD34288`), and every remainder is in a range that can never hold a mail
         record, because the mail arena is only ever handed out by `0xD54134`/`0xD5410C`/
         `0xD5415C`/`0xD542A8`/`0xD347E4`/`0xD34728`, whose complete caller sets contain no
         address in those ranges. **The row icon is this byte's only effect anywhere in the
         game.**

         **What the player sees.** Every row in a received-mail list carries a small marker.
         Normally it is the "you have not read this yet" marker and it disappears the moment you
         open the letter. This byte is the server's switch to **keep a marker on a letter you have
         already read**, in its own distinct graphic. It is entirely server-authoritative: nothing
         in the client ever writes `+273` except the wholesale record copy and the clear-to-zero,
         so a player cannot flag their own mail. That is the shape of a server-side "this one
         matters" flag — which is what the inherited name *important* claims.

         **Verdict: the behaviour is proven; the word "important" remains an interpretation of the
         behaviour.** The three state names stay unrecovered — they are real entries in
         `cache.dar`'s 56-state directory but stored as hashes on both sides, and both a short-name
         exhaustive search and a ~10^7 structured-vocabulary search came back empty (the same
         machinery recovered `ICON`, so the method works). The behaviour is fully determined
         without them.

         **Server:** we send 0 for every entry, so a read letter shows no icon and an unread one
         shows the standard marker — normal behaviour, nothing broken. Recorded as operator
         policy: the announcement letter in category 3 is the natural candidate for 1 if we ever
         want its marker to persist after reading. That is a product decision, not a bug.
      2. "It IS echoed back to the server in the 0x4800 send (struct+0x110)" — right in substance,
         **wrong by one byte**: `0x110` is 272, which is `message_type`/`destination`. This field
         is `0x111` = 273, and it is echoed at `0x4800` wire offset `0x3c6` (see that file's
         `echoed_flag_273`). The path is `MailRecordCopy` `0xd347b0`/`0xd347c0`.

      No code anywhere in the binary writes record+273 except the clear (`0xd34288`, to 0) and the
      copy, so it is entirely server-authoritative and its only effect is the row's display state.
      We send 0.
  - id: read
    type: u1
    doc: |
      [ELF 0xD537EC] -> record+274. Last byte of the 266. **Tier-4 name "read" is now CONFIRMED**:
      every unread tally in the UI counts records whose value here is 0 (0x8E5298, 0x8F0638,
      0x8F08E8, stride 280 from list+274), and opening a letter sets it to 1 at 0x8E2CD8.
      So 0 = unread, nonzero = read. This is the ONLY per-record state byte the client acts on —
      note it is a read flag, not a deletion flag; see the header.
