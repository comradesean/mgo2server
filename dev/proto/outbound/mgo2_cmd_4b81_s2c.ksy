meta:
  id: mgo2_cmd_4b81_s2c
  title: "MGO2 0x4b81 — Clan Info for a clan you are NOT in, 217 bytes (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). Seven slots are
  [CONFIRMED LIVE 2026-07-27]; the rest of the 217 bytes is still unmapped and goes out as zeros.

  **Clan Info for a clan the player is NOT in.** The reply to 0x4b80, a u32 clan id, sent when a
  row is picked out of the clan list (0x4b12) or the search results (0x4b92).

  This is the counterpart to 0x4b20 / 0x4b21, which **cannot** serve a non-member: that reply's id
  is cross-checked against the client's own clan id and the packet is dropped on a mismatch. This
  one's `subject_id` is explicitly **NOT** cross-checked, which is exactly what makes it the "look
  at someone else's clan" path.

  **It also unblocks joining.** 0x4b42's sender refuses to transmit unless the session clan record
  at session_ctx+0x1AA0 holds a non-zero id, returning -24 (0xFFFFFFE8) having sent nothing at all.
  That record comes from this reply, so answering 0x4b80 with 217 zero bytes makes Apply to join
  fail with -24 and no packet on the wire — which is precisely what was observed before this reply
  carried a real id.

  Slot meanings are shared with 0x4b21 (mgo2_cmd_4b21_s2c.ksy), which writes the same struct:
  T+0x00 id, T+0x04 clan name, T+0x18 LEADER CHARA ID, T+0x1c leader name, T+0x58 member count,
  T+0x378 emblem-present flag, T+0x67A clan comment.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD58C74**, which re-checks the id (`cmpwi r0,19329`) before reading anything.

  Closes pending-request slot **113**. Writes into the SAME struct as 0x4b21
  (T = session + 0x10000 - 1968) but does NOT memset it first and touches only a subset of the
  fields — so this is an update, and any field 0x4b21 set that this packet omits keeps its old
  value. Overlapping destinations with mgo2_cmd_4b21.ksy: T+0x00, +0x04, +0x18, +0x1c, +0x378,
  +0x67A, +0x58, +0x1B34.

  Wire size on success: **217 bytes**; on error (result != 0) 4.

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
    doc: "[ELF] 0 = success, body follows. Published to request slot 113."
  - id: clan_id
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x00, the viewed clan's id — same slot as 0x4b21's, but **NOT
      cross-checked here**, which is what lets this reply describe a clan the client has never
      heard of.

      It must be non-zero and real: this is the value that lands in the session clan record, and
      0x4b42 (Apply to join) refuses to transmit at all without it. See the top-level doc.
  - id: clan_name
    size: 16
    type: str
    encoding: ASCII
    doc: "[CONFIRMED 2026-07-27] T+0x04, the clan's name, 16 bytes. Same slot as 0x4b21's clan_name."
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
    doc: "[CONFIRMED 2026-07-27] T+0x1c, the clan LEADER's name, 16 bytes. Same slot as 0x4b21's leader_name."
  - id: emblem_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-27] T+0x378 — **3 when the clan has a published emblem**, 0 when it does
      not. Same slot and meaning as 0x4b21's.

      The client will not fetch an emblem (0x4b4a) while this is 0, so a clan reached from search or
      the clan list rendered with an empty emblem even when the server had one stored.
  - id: clan_comment
    size: 128
    type: str
    encoding: ASCII
    doc: "[CONFIRMED 2026-07-27] T+0x67A, the clan comment / description, 128 bytes. Same slot as 0x4b21's clan_comment, and the same field 0x4b64 writes."
  - id: unknown_1b34
    type: u4
    doc: |

      ## UNOBSERVABLE — established by live test 2026-08-02

      **This slot cannot be read back from any screen on release-day content, so the value we send
      is unfalsifiable operator policy and zero is final rather than pending.** A probe sent
      `12345678` here from **both** `0x4b21` and `0x4b81`; the server logs confirm both packets went
      out (777 and 217 bytes) and **nothing rendered**.

      The non-zero probe is what makes this conclusive rather than ambiguous — it rules out the
      obvious alternative, that a zero was simply being suppressed by the renderer.

      Both readers are independently unreachable:

      * **CLAN RECORD / "Clan Stats"** (`0xA8A970` -> `STRING_0_3`) never opens. It refuses with
        *"The clan's records are currently unavailable. Please wait until an official match is
        held."* An official match is an **Official Tournament**, lobby subtype 5 — Ver. 1.20
        content this server deliberately does not serve, so the gate sits upstream of the field and
        rejects the whole screen.
      * **The Clan Info popup** (`0xA7D32C` -> `infoC_st-3`) does not draw the element. The renderer
        sets **thirteen** elements; this build's layout binds **three** — clan name (`infoC_st-1`),
        leader name (`infoC_st-2`) and member count (`infoC_st-4`). Every other element it sets,
        `infoC_st-3` and `T+0xC68`'s `infoC_st-5` included, is absent from the layout.

      That second observation is the more useful one, and it generalises: the popup's ten numeric
      rows are the clan-statistics feature, and this build renders none of them. It is consistent
      with Clan Stats being gated on tournament data — the whole feature set is post-launch.

      **Consequence for the campaign:** this field can never reach tier 2, for the same reason
      `host_stance` cannot (see `dev/docs/BACKLOG.md`). Do not re-open it as "needs a live test";
      the live test was run and its result was that no observation exists.
      [ELF 2026-07-30] T+0x1B34 — the **same slot 0x4b21 sends**, and it is genuinely rendered, so
      "sent as zero" is a choice we are making rather than a property of the packet.

      Readers: `0xA7D32C` (`lwz r5,6964(r22)`) draws it into element `infoC_st-3` of the clan-info
      popup, and `0xA8A970` (`lwz r5,6964(r9)`) into `STRING_0_3` in the CLAN RECORD header; both
      via the number formatter `0xCFD018(buf, 20, v)`. Full trace and the reason its *meaning* is
      still [UNKNOWN] are in mgo2_cmd_4b21_s2c.ksy under the same field name.

      [ELF 2026-08-01] The clan-info popup is now mapped element by element in
      `mgo2_cmd_4b21_s2c.ksy` — this slot is `infoC_st-3`, drawn between `T+0xC68` (`infoC_st-5`,
      clamped to 9,999,999) and `member_count` (`infoC_st-4`), and it is one of only **three**
      numbers on that popup that either clan packet supplies; the other seven come from
      `T+0x1730`-`0x1750`, which neither `0x4b21` nor `0x4b81` writes. The apparent second writer
      at `0x4129F8` is a stride-16 engine table and is ruled out there. Meaning still [UNKNOWN];
      the deciding experiment is also recorded there.

      Note this contradicts the top-level doc's overlap list only in emphasis: `T+0x1B34` was
      already listed as shared with 0x4b21. It is the one shared trailing slot that has a reader —
      `T+0x1B2C` and `T+0x1B30`, the two cooldowns, are 0x4b21-only.
  - id: member_count
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x58, how many members the clan has. Same slot as 0x4b21's. Note it
      comes AFTER the comment on the wire even though it sits far earlier in the struct — see
      `leader_chara_id` for what swapping the two looks like on screen, and for why that
      experiment constrained this slot rather than that one.
  - id: unknown_1328
    type: u4
    doc: |
      [ELF] T+0x1328 — outside anything 0x4b21 writes. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,4904(rY)` in the
      disassembly was listed. The only non-stack hits are `0x411FB4`
      (`stw r0,4904(r9)`, an unrelated initialiser in the `0x41xxxx` block that never calls the
      clan accessor) and `0xD81CCC` (`stw r15,4904(r29)`); neither base can be `T`.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_1978
    type: u4
    doc: |
      [ELF] T+0x1978. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6520(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6520(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_197c
    type: u4
    doc: |
      [ELF] T+0x197C. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6524(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6524(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_1980
    type: u4
    doc: |
      [ELF] T+0x1980. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6528(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6528(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_1984
    type: u4
    doc: |
      [ELF] T+0x1984. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6532(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6532(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_1988
    type: u4
    doc: |
      [ELF] T+0x1988. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6536(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6536(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_198c
    type: u4
    doc: |
      [ELF] T+0x198C. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6540(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6540(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_1990
    type: u4
    doc: |
      [ELF] T+0x1990. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6544(rY)` in the
      disassembly was listed. The only hits are stores in the unrelated `0x4127xx` initialiser block (`stw ...,6544(r11)`) plus one or two `stb`/`sth` in `0xDFCxxx` / `0x536xxx` / `0xEFBxxx`; none of those functions can hold `T`, and there is **no load at all** at this displacement anywhere.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

  - id: unknown_1994
    type: u4
    doc: |
      [ELF] T+0x1994, last 4 bytes of the payload. The eight u4 at T+0x1978..0x1994 are consecutive
      and read in order — a small counter/stat array. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] No reader anywhere in the image.** Two independent
      scans agree.

      (a) Whole-image displacement scan. This offset can only be reached as a displacement off a
      pointer to `T`, so every `lwz/lbz/lhz/ld/lwa/stw/stb/sth/std rX,6548(rY)` in the
      disassembly was listed. The only hits are `stw r0,6548(r11)` in the unrelated
      `0x4127xx` initialiser and `sth r14,6548(r7)` at `0xEFB1D4`; there is no load at this
      displacement anywhere in the image.

      (b) Taint scan from the accessor. `T` is only ever produced by `0xD54404`
      (`GetClanProfile(session)` = `session + 0x10000 - 1968`, `0xD5440C`-`0xD54414`) and by the
      two parsers. All 108 `bl 0xD54404` sites were followed across their enclosing functions
      through `mr`/`clrldi`/`extsw`/`addi`, killing r0-r12 at each call, and the four sites that
      spill a `T`-derived pointer to memory (`0xA8A418`, `0xABCC24`, `0xABD82C`, `0xAE2C04`) were
      followed on reload. The complete set of offsets reached is
      `0x00, 0x04, 0x18, 0x1C, 0x58, 0x77, 0x378, 0x379, 0x67A, 0x6FC, 0x700, 0x904, 0x908, 0xC68,
      0x1730-0x174C, 0x1B2C, 0x1B30, 0x1B34`. This one is not in it.

      All eight words of this block share that negative, so the whole run is inert on this client.
      Whatever fills it in the retail server, nothing in `BLUS30109` reads it back.
