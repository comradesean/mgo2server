meta:
  id: mgo2_cmd_4b21_s2c
  title: "MGO2 0x4b21 — clan profile for YOUR OWN clan, 777 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md).

  **The clan profile.** The reply to 0x4b20, one u32 clan id (builder 0xD567F0), sent from Clan
  Affiliation. Several slots are [CONFIRMED LIVE 2026-07-27]; the rest of the 777 bytes is still
  unmapped and stays zero. This is the "your own clan" path — the id is cross-checked against the
  one the client already holds, so it CANNOT serve a clan the player is not in. That is what
  0x4b80 / 0x4b81 is for (mgo2_cmd_4b81_s2c.ksy), and the two share this destination struct.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD587AC**, which re-checks the id (`cmpwi r0,19233`) before reading anything.

  Preconditions the parser enforces before it will parse: pending-request slot **99** must be in
  state 1 (getter 0xD32E3C at 0xD587F8-0xD58818) and, if the session already holds a clan
  context, the `subject_id` field below must equal the stored one at
  session[+0x10000+6404]+0x20000+27904, else the packet is dropped with no error.

  Destination struct: T = session + 0x10000 - 1968, memset to 0 over 6968 (0x1B38) bytes before
  the reads (0xD588A8). Destination offsets are given per field as T+0x...; they are NOT wire
  offsets. The same struct is partially rewritten by 0x4b81 (parser 0xD58C74) — see
  mgo2_cmd_4b81.ksy.

  Wire size when result == 0: **777 bytes**. When result != 0 the parser jumps straight to
  end-read (0xD58C04), so an error reply is 4 bytes.

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
  - id: result
    type: s4
    doc: "[ELF] 0 = success and the body follows; non-zero = 4-byte reply, body absent. Published to request slot 99."
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x00, the clan's id, and it MUST echo the id the request asked for:
      the client cross-checks it against the id it already holds and **drops the packet with no
      error** on a mismatch. A clan the client does not already know about cannot be delivered
      here at all — that is 0x4b81's job, and 0x4b81's copy of this slot is explicitly not
      cross-checked.
  - id: clan_name
    size: 16
    type: str
    encoding: ASCII
    doc: "[CONFIRMED 2026-07-27] T+0x04, the clan's name, 16 bytes fixed; the client NUL-terminates at T+0x14."
  - id: membership_state
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] T+0x15, the viewer's membership state in this clan:
      **0 pending, 1 member, 2 leader, 99 none** — the same encoding as the session clan record at
      session_ctx+0x1AA0 and as 0x4b47's state byte.

      This is the only thing that gates committing an emblem: 0xAD409C tests ctx+788 & 4, which is
      set purely from state == 2. No privilege bit is involved — see mgo2_cmd_4b47_s2c.ksy.
  - id: leader_chara_id
    type: u4
    doc: |
      [CORRECTED 2026-07-29 — READ from the ELF] T+0x18 is the **clan leader's character id**, not
      a founding date. The parser (`0xD587AC` for `0x4b21`, `0xD58C74` for `0x4b81`) reads it with the
      u32 primitive `0xD5CCD8` into the shared struct at `session+0x10000-1968`.

      **It has exactly five readers, and they are five clones of one routine** — `0xAC8F9C`,
      `0xACA5B4`, `0xACAA04`, `0xACBA84`, `0xACD9AC`. Each walks the roster scroll-list and compares
      this value for **equality against each row's member id**, selecting one row and turning on that
      row's icon (`0xACBA8C` / `0xACBA90`). The very next instruction compares the same row id against
      `T+0x6FC`, which is independently confirmed to be a character id — so this is the same kind of
      value.

      **No date signature at all**: it is never passed to the time formatter `0x8843CC`, never divided
      or modded, never sign-tested. The struct's only timestamp-shaped consumer is `T+0x904`, and that
      is the **notice's** date. There is no founding-date field in this struct.

      **Why the old label was wrong, which is the part worth keeping.** It came from an experiment
      that swapped this slot with `T+0x58` and saw the member count render `1785129141`. That
      observation constrains **`T+0x58` only** — it proves what the member-count renderer reads and
      says nothing about this slot; the epoch value merely happened to be what landed in the other
      one. A real observation with a label layered on top, then mirrored to a sibling packet as "same
      slot, same meaning" — sound about the slot, false about the meaning.
  - id: leader_name
    size: 16
    type: str
    encoding: ASCII
    doc: "[CONFIRMED 2026-07-27] T+0x1c, the clan LEADER's name, 16 bytes fixed."
  - id: unknown_30
    type: u4
    doc: "[ELF] T+0x30. [UNKNOWN]"
  - id: name_c
    size: 16
    type: str
    encoding: ASCII
    doc: "[ELF] T+0x34, 16 bytes fixed. [UNKNOWN] which name."
  - id: unknown_48
    type: u4
    doc: |
      [ELF] Read as u4 into a stack slot then stored with `std` into T+0x48 as a 64-bit word
      (0xD5899C). Only 4 bytes are on the wire. Meaning still [UNKNOWN].

      **[ELIMINATED LIVE 2026-07-27] It is NOT the emblem re-display cooldown.** It was the obvious
      candidate — the only timestamp-shaped slot the server sends that the client never renders,
      and the plausible feed for the countdown behind lobby string 17247 ("You must wait another %d
      hours %d minutes"). The experiment sent the real emblem display time here and fetched a fresh
      0x4b21. The confirming observation would have been the countdown appearing; it did not, and
      the emblem could still be re-displayed immediately. Back to zero.

      The emblem cooldown is therefore **operator policy**, enforced by refusing 0x4b50 with -1216,
      not by any field in this packet.
  - id: member_count
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x58, how many members the clan has. Same slot and meaning as
      0x4b81's T+0x58; swapping it with the founding date there produced the 1785129141-members
      rendering.
  - id: unknown_5c
    type: u4
    doc: "[ELF] T+0x5c. [UNKNOWN]"
  - id: unknown_60
    type: u4
    doc: "[ELF] T+0x60. [UNKNOWN]"
  - id: unknown_64
    type: u4
    doc: "[ELF] T+0x64. [UNKNOWN]"
  - id: unknown_68
    type: u4
    doc: "[ELF] T+0x68. [UNKNOWN]"
  - id: unknown_6c
    type: u4
    doc: "[ELF] T+0x6c. [UNKNOWN]"
  - id: flags_word
    type: u4
    doc: "[ELF] T+0x70. A bitfield: the `flags_byte` below is merged into this same word, so the server must not treat the two as independent. [UNKNOWN] bit meanings."
  - id: unknown_74
    type: u1
    doc: "[ELF] T+0x74. [UNKNOWN]"
  - id: flags_byte
    size: 1
    doc: |
      [ELF] Read as a 1-byte block (0xD58A80), then three bits are OR-ed into the 64-bit word at
      T+0x70 (0xD58A90-0xD58AD8): bit0 -> 0x00800000, bit1 -> 0x00400000, bit2 -> 0x00010000.
      Bits 3..7 are read and discarded. [UNKNOWN] meanings.
  - id: emblem_wip_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] T+0x76 — **2 when a WORK-IN-PROGRESS emblem exists** for this clan,
      i.e. one uploaded but not put on display. The published counterpart is `emblem_flag` below.
  - id: emblem_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] T+0x378 — **3 when a PUBLISHED emblem exists**, 0 when none does.
      (Structurally a long way from its neighbours, so it lands in a different sub-struct.)

      The client **will not fetch or offer an emblem while this is 0**. That is why Emblem Edit had
      nothing to apply for a clan whose emblem the server had stored: the flag, not the emblem
      bytes, is what makes the client ask for it (0x4b4a) at all. Same slot and meaning as 0x4b81's
      T+0x378, so a clan viewed from search or the clan list needs it too.
  - id: clan_comment
    size: 128
    type: str
    encoding: ASCII
    doc: |
      [CONFIRMED 2026-07-27] T+0x67A, the clan comment / description, 128 bytes fixed.

      Settled three ways and they agree: it is the offset 0x4b00's create request reads its own
      description from (arg+0x67A, the identical offset — the client keeps the clan in one struct
      and both commands address the same field); it is what the 128-byte write 0x4b64 sets; and
      setting **Clan Comment** to "bench" on the client put exactly that on the wire.
  - id: emblem_editor_chara_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x6FC, the character id of the member who holds **emblem-editing
      rights** — assigned by 0x4b62. The client compares it against its own character id to decide
      whether to offer "set as the clan's emblem".

      Note it is a character id, not a bit: no privilege bit gates applying an emblem. See
      mgo2_cmd_4b47_s2c.ksy for the experiment that eliminated the privilege word.
  - id: notice
    size: 512
    doc: |
      [CONFIRMED 2026-07-27] T+0x700, **the clan NOTICE**, 512 bytes fixed, read with 0xD5D018 so
      the client NUL-terminates at T+0x900. Largest single field in the packet.

      **CORRECTION.** An earlier revision of this spec called this an [UNKNOWN] blob that "could be
      a long text block or a packed table". It is the notice: setting **Clan Notice** to
      "watching you" on the client sent 0x4b66 carrying exactly 512 bytes, the same size and the
      same struct offset. Its timestamp and author follow immediately below, which is also how the
      screen draws it.
  - id: notice_at
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x904, the **NOTICE's timestamp**, Unix seconds. Read to a stack
      slot then `stw` to T+0x904 (0xD58B9C).

      **IMPORTANT CORRECTION.** This field was previously documented here as the clan's FOUNDING
      date. That was a guess about meaning layered on a real observation: the probe that found it
      sent each candidate slot the date offset by a different number of days and watched which one
      Clan Affiliation displayed, so the FIELD was right and the LABEL was wrong — the date the
      screen draws here is the date the notice was set, and the 16 bytes after it are the name of
      whoever set it. **T+0x18 is the leader's chara id, not a founding date, and this
      struct has no founding-date field** — see `leader_chara_id` (corrected 2026-07-29).

      **When unset, send -1, NEVER 0.** The renderer 0xAAB2D8 has no conditionals at all — it
      always draws the date line, the author and the notice body, so the line cannot be suppressed.
      But the formatter 0x8843CC tests the value at 0x884420 and takes a fallback branch when it is
      NEGATIVE, printing the literal "XXXX-XX-XX XX:XX:XX". Zero is not special-cased: localtime(0)
      succeeds and yields 12-31-1969. -1 is this binary's own convention for an absent timestamp;
      0x91E4C0 tests another one the same way.
  - id: notice_author
    size: 16
    type: str
    encoding: ASCII
    doc: "[CONFIRMED 2026-07-27] T+0x908, 16 bytes fixed: the name of whoever last set the notice. Drawn under the notice beside `notice_at`."
  - id: unknown_1b2c
    type: u4
    doc: "[ELF] T+0x1B2C. [UNKNOWN]"
  - id: unknown_1b30
    type: u4
    doc: "[ELF] T+0x1B30. [UNKNOWN]"
  - id: unknown_1b34
    type: u4
    doc: "[ELF] T+0x1B34, last 4 bytes of the payload. [UNKNOWN]"
