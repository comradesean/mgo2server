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

  ## [ELF 2026-08-02] THE "READ BY NOTHING" NEGATIVE, INDEPENDENTLY REPRODUCED AND WIDENED

  Eight slots below (`T+0x30`, `T+0x34`, `T+0x48`, `T+0x5C`, `T+0x60`, `T+0x64`, `T+0x68`,
  `T+0x6C`) plus `T+0x70`/`T+0x74` carry the 2026-07-30 "written by the parser, read by nothing"
  finding. That sweep was re-run from scratch and **reproduces exactly**: 108 `bl 0xD54404` call
  sites, taint-propagated through `mr`/`clrldi`/`extsw`/`addi` to the end of each enclosing
  function, killing `r0`-`r12` at every call, gives the displacement set
  `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
  0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34` and the same four pointer escapes (`0xA8A418`
  `stw r3,96(r31)`; `0xABCC24` / `0xABD82C` `stw r3,84(rN)`; `0xAE2C04` `T+0x67A` into `+176`).
  Controls inside the sweep succeed — `T+0x58` (`member_count`), `T+0x1B2C`, `T+0x1B30` and
  `T+0x1B34` are all found, and they are the slots we already know have readers.

  **Two addressing forms the 2026-07-30 sweep did not cover were then swept as well**, because a
  reader can reach `T` without ever calling the accessor:

  1. **`addis rX,rY,1` then a load/store at a NEGATIVE displacement** — i.e. addressing the struct
     straight off the session as `session+0x10000-1968+off`, which is the form the parsers
     themselves use to *build* the pointer. Over the whole image, at any of
     `-1968, -1920, -1916, -1896, -1880, -1876, -1872, -1868, -1864, -1860, -1856, -1852`:
     **zero hits**. Control: the identical matcher run at `+6404` (the session's own clan-context
     pointer, `lwz r3,6404(r9)` at `0xD5886C`) fires **208** times, so the form is in live use and
     the negative is not a matcher artefact.
  2. **`addis rX,rY,1` then `addi rZ,rX,-19xx`** — a pointer taken to one *field* rather than to
     `T`. Over `-2000..-1800` the only sites are the parsers' own per-field `addi`s and **five**
     producers of `T` itself: `0xD344B8` (the reset, and note it memsets only 296 bytes),
     `0xD54414` (the accessor `GetClanProfile`), `0xD58898` (`0x4b21` parser), `0xD58CF8`
     (`0x4b81` parser) and **`0xD599E0` — the `0x4b71` parser, a fifth writer the 2026-07-30 note
     did not list** (it fills `T+0x91C + rec*72 + mode*864`, which is where `T+0x1730`-`0x1750`
     come from). The `-1856` / `-1848` clusters around `0xA66C88` are **not** this struct: their
     base is `slwi rN,rN,3` index arithmetic added to `r21`, an unrelated table.

  So the negative now rests on three independent sweeps rather than one, and it is a statement
  about **this build**: every one of those slots is **inert**, and the server sends zero into all
  of them, which is safe precisely because nothing reads them. That inertness is the part that can
  change, so it is recorded per field rather than assumed.

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
    doc: |
      [ELF] T+0x30, read at `0xD58930`. [UNKNOWN]

      **Structural note, which is all that can be said about the meaning.** `T+0x30` (u4) followed
      immediately by `T+0x34` (16-byte name) is the *same {id, name[16]} shape* as
      `leader_chara_id` at `T+0x18` / `leader_name` at `T+0x1C` — a second character-id-and-name
      pair. That is a shape, not a name, and there is no reader to settle whose pair it is.
      `0x4b81` reads neither slot (its parser `0xD58C74` goes `T+0x18` -> `T+0x1C` -> `T+0x378`),
      so whatever it is, it is own-clan-only.

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: name_c
    size: 16
    type: str
    encoding: ASCII
    doc: |
      [ELF] T+0x34, 16 bytes fixed, read at `0xD5894C` with the block primitive `0xD5D018`
      (`li r5,16`). [UNKNOWN] which name — the id is inherited, and nothing in the binary says this
      is a name at all beyond its 16-byte width and the `{u4, char[16]}` pairing with
      `unknown_30`; see that field's structural note. `0x4b81` does not carry this slot.

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: unknown_48
    type: u4
    doc: |
      [ELF] Read as u4 into a stack slot (`0xD5896C`, primitive `0xD5CCD8`) then stored with `std`
      into T+0x48 as a 64-bit word (`0xD5899C`). Only 4 bytes are on the wire. Meaning still
      [UNKNOWN].

      **[ELF 2026-08-02] That `std` is the ONLY 64-bit widening in this parser**, and it is the
      same u32-read/`std`-store shape this binary uses for `time_t` elsewhere — `0x4822`'s `time`
      (`0xD537B8`, record+264) and `0x4902`'s open/close times. So the *client-side type* is
      64-bit and timestamp-shaped; that is structural evidence about the slot's width, and it is
      not evidence about the meaning, which the 2026-07-27 live elimination below already put
      beyond the emblem cooldown.

      **[ELIMINATED LIVE 2026-07-27] It is NOT the emblem re-display cooldown.** It was the obvious
      candidate — the only timestamp-shaped slot the server sends that the client never renders,
      and the plausible feed for the countdown behind lobby string 17247 ("You must wait another %d
      hours %d minutes"). The experiment sent the real emblem display time here and fetched a fresh
      0x4b21. The confirming observation would have been the countdown appearing; it did not, and
      the emblem could still be re-displayed immediately. Back to zero.

      The emblem cooldown is therefore **operator policy**, enforced by refusing 0x4b50 with -1216,
      not by any field in this packet. **The cooldown the client renders comes from `T+0x1B30`, not
      from here** — see `emblem_display_cooldown_s` below, traced in the binary 2026-07-30. That is
      the positive result the 2026-07-27 experiment was missing.

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: member_count
    type: u4
    doc: |
      [CONFIRMED 2026-07-27] T+0x58, how many members the clan has. Same slot and meaning as
      0x4b81's T+0x58; swapping it with the founding date there produced the 1785129141-members
      rendering.
  - id: unknown_5c
    type: u4
    doc: |
      [ELF] T+0x5c. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: unknown_60
    type: u4
    doc: |
      [ELF] T+0x60. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: unknown_64
    type: u4
    doc: |
      [ELF] T+0x64. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: unknown_68
    type: u4
    doc: |
      [ELF] T+0x68. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: unknown_6c
    type: u4
    doc: |
      [ELF] T+0x6c. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: flags_word
    type: u4
    doc: |
      [ELF] T+0x70. A bitfield: the `flags_byte` below is merged into this same word, so the server
      must not treat the two as independent. [UNKNOWN] bit meanings.

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

      Because `T+0x70` has no reader, the three bits `flags_byte` ORs into it are dead as well.

  - id: unknown_74
    type: u1
    doc: |
      [ELF] T+0x74. [UNKNOWN]

      **[ELF — PRECISE NEGATIVE 2026-07-30] Written by the parser, read by nothing.** Method, so
      it can be re-run: the only producer of a pointer to this struct is the accessor
      **`0xD54404`** — `GetClanProfile(session)`, body `addis r3,r3,1; addi r0,r3,-1968` at
      `0xD5440C`-`0xD54414`, i.e. `T = session + 0x10000 - 1968` — plus the two parsers
      (`0xD587AC`, `0xD58C74`) and the reset at `0xD344B8`. All **108** `bl 0xD54404` sites were
      taint-scanned across their whole enclosing function, propagating through `mr` / `clrldi` /
      `extsw` / `addi` and killing r0-r12 at every call. The complete set of `T+` displacements
      touched anywhere in the image is
      `0x00, 0x18, 0x58, 0x77, 0x378, 0x6FC, 0x904, 0xC68, 0x1730, 0x1734, 0x1738, 0x173C, 0x1744,
      0x1748, 0x174C, 0x1B2C, 0x1B30, 0x1B34`, plus pointers handed to other functions at `T+0x04`,
      `T+0x1C`, `T+0x77`, `T+0x379`, `T+0x67A`, `T+0x700` and `T+0x908`. Exactly four sites let a
      `T`-derived pointer escape into memory — `0xA8A418` (`stw r3,96(r31)`), `0xABCC24` /
      `0xABD82C` (`stw r3,84(rN)`) and `0xAE2C04` (`T+0x67A` into `+176`); every reload of those
      slots was followed and they reach only `+0x04`, `+0x67A`, `+0xC68` and `+0x1B34`. The only two
      functions handed plain `T` (`0x9C2918`, `0x2810E0`) ignore the argument entirely. What would
      overturn this: a reader that reaches the struct through a base other than `0xD54404`'s return.

      **[ELF 2026-08-02] Reproduced, and widened to two addressing forms the original sweep did
      not cover — still no reader.** See "THE 'READ BY NOTHING' NEGATIVE" in the header for the
      three sweeps, their controls and the fifth writer of the struct. The field is **inert** on
      this build. **What we send: zero** (`ClanGameController.clanProfile`), which is correct
      while nothing reads it; the hazard is that inertness is a property of this client build, not
      of the protocol.

  - id: flags_byte
    size: 1
    doc: |
      [ELF] Read as a 1-byte block (0xD58A80), then three bits are OR-ed into the 64-bit word at
      T+0x70 (0xD58A90-0xD58AD8): bit0 -> 0x00800000, bit1 -> 0x00400000, bit2 -> 0x00010000.
      Bits 3..7 are read and discarded. [UNKNOWN] meanings.

      **[ELF 2026-07-30] The three surviving bits are dead too**, because their destination
      `T+0x70` has no reader anywhere in the image — see `flags_word` above for the scan that
      establishes it. Every bit of this byte is therefore inert on this client.
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
  - id: disband_cooldown_s
    type: u4
    doc: |
      [ELF — NAMED 2026-07-30] T+0x1B2C. **Seconds remaining before this clan may be DISBANDED.**
      Send 0 when there is no wait.

      The whole chain, in order:

      1. `0xAB5D7C` `bl 0xD54404` then `0xAB5D84` `lwz r4,6956(r3)` — this field, read straight off
         the clan profile. Duplicated on the second clan screen at `0xABA138`/`0xABA140`.
      2. `0xAAA7A0` converts it `fcfid`/`frsp` and stores it as a **float at screen+832**
         (`stfs f0,832(r3)`, `0xAAA7BC`); a zero value is stored as integer 0 instead
         (`0xAAA7CC`). The per-frame updater `0xAAAE88` then subtracts the frame delta from
         screen+828 and screen+832 and clamps both at zero (`fsubs`/`fsel`, `0xAAAEC0`-`0xAAAEDC`),
         which is what makes this a live countdown rather than a plain number.
      3. `0xAB5568` reads it back — `lfs f0,832(r9)`, `fctidz`, then `mulhwu 0x88888889` + `srwi 5`
         twice (`0xAB5588`, `0xAB55AC`) to get minutes and hours, rounding minutes UP on a nonzero
         remainder (`0xAB55A0`).
      4. The message is chosen on the screen's state word (`lwz r0,4(r27)` at `0xAB548C`): state 16
         is this one. With hours != 0 it formats **clan string ordinal 101** (`li r4,101` at
         `0xAB55E0`) with (hours, minutes); with hours == 0, **ordinal 102** (`0xAB5674`) with
         minutes alone. Both go through `GetString(hash("clan"), n)` = `0x240708` after
         `0xD25D0` hashes the literal `clan`.

      The disc gives the sentences verbatim (set `[642318]`, headers 16524..16738, group hash
      `0x333C8E` = `"clan"`, strings from 16739):
        * **101** — `You cannot disband this clan for\nanother %d hours %d minutes.`
        * **102** — `You cannot disband this clan for\nanother %d minutes.`

      So this is a server-side cooldown the client only *displays*; the refusal itself must still
      come from us. Units are seconds because the value is decremented by the frame delta and
      divided by 60 twice.

      **[BUG 2026-08-02 — WRONG AND REACHABLE. The server sends 0 while enforcing the cooldown.]**
      `ClanGameController.clanProfile` writes `buffer.writeZero(4 + 4 + 4)` over
      `T+0x1B2C`..`T+0x1B34`, so this field is always 0. But `disband()` **does** enforce a
      cooldown — `clanService.secondsUntilDisbandable(membership.id())`, default
      `ClanService.DISBAND_COOLDOWN` = one week — and refuses `0x4b05` with `-1205`. A leader
      inside the cooldown therefore sees the bare refusal *"A fixed amount of time must pass in
      order to disband the clan."* with **no number**, because the countdown the client would have
      drawn is fed from here and we told it there is no wait.
      **Correct value: `clanService.secondsUntilDisbandable(clan.id())`**, clamped at 0. The two
      must agree; sending 0 while refusing is the server contradicting itself.
      Note this is the same class of miss as the ones `CLAUDE.md` lists: the field was *named*
      correctly on 2026-07-30 and what we send was never checked against the new meaning.
  - id: emblem_display_cooldown_s
    type: u4
    doc: |
      [ELF — NAMED 2026-07-30] T+0x1B30. **Seconds remaining before this clan's emblem may be put
      on display again.** Send 0 when there is no wait. This is the countdown `unknown_48`'s
      2026-07-27 experiment went looking for and did not find — it was in the wrong slot.

      The chain, which is closed end to end:

      1. `0xAB5D5C` `bl 0xD54404` then `0xAB5D64` `lwz r4,6960(r3)`. Duplicated at
         `0xABA118`/`0xABA120` on the sibling clan screen.
      2. `0xAAA768` stores it as a **float at screen+828** (`stfs f0,828(r3)`, `0xAAA784`), decayed
         per frame by `0xAAAE88` exactly like `disband_cooldown_s`.
      3. The **only** value-reader of screen+828 in the whole image is the clan screen's message
         handler `0xAABC88`, case **16**: `lfs f0,828(r11)` / `fctidz` / `stw r0,0(r9)` at
         `0xAABD34`-`0xAABD48`, writing the integer into the caller's out-parameter.
      4. `0xA98A90` is the only sender of that message, and it has exactly **four** call sites in
         the image — `0xAA51E8`, `0xAA5254`, `0xAA6954`, `0xAA69DC` — all inside the EMBLEM EDIT
         screen. Two of them use code 16 (`li r4,16` at `0xAA5248` and `0xAA69C8`); the other two
         use code 11, and `0xAABC88` handles exactly codes 11 and 16 (`cmpwi r4,11` at `0xAABD18`,
         `cmpwi r4,16` at `0xAABD20`) — which is what identifies the object being messaged.
      5. A non-zero result puts the emblem screen into state **8** carrying the value
         (`stw r0,8(r9); li r0,8; stw r0,4(r9)` at `0xAA526C`-`0xAA5274`, and `0xAA69F0`).
      6. State 8 (`cmpwi r0,8; beq 0xAA5098` at `0xAA4FF8`) runs the same /60 arithmetic
         (`mulhwu 0x88888889` at `0xAA50A4`) and formats **clan string ordinal 90** with
         (hours, minutes) at `0xAA50FC`, or **ordinal 91** with minutes alone at `0xAA5190`. The
         second copy of the screen does the same at `0xAA6BDC` / `0xAA6C4C`.

      Disc text (same set as `disband_cooldown_s`):
        * **90** — `You must wait another %d hours %d minutes\nbefore you can put this emblem on display.`
        * **91** — `You must wait another %d minutes\nbefore you can put this emblem on display.`

      Note this only draws the countdown. Refusing the action is still ours — `0x4b50` answered
      with `-1216` — so the two must be kept consistent by the server.

      **[BUG 2026-08-02 — WRONG AND REACHABLE. The server sends 0 while enforcing the cooldown.]**
      Same single `buffer.writeZero(4 + 4 + 4)` in `ClanGameController.clanProfile` covers this
      slot. Meanwhile `EMBLEM_COOLDOWN_SECONDS` (`Policy.current().clanEmblemCooldown()`, default
      one week) is enforced and `0x4b50` is refused with `EMBLEM_REFUSED = -1216`. So Emblem Edit
      refuses the display and the countdown never appears — and the javadoc on
      `EMBLEM_COOLDOWN_SECONDS` still says the countdown is "unreachable" and that nothing feeds
      it, which was true only until `T+0x1B30` was traced on 2026-07-30.
      **Correct value: the seconds remaining of `EMBLEM_COOLDOWN_SECONDS` for this clan**, 0 when
      none. Sending 0 here is what makes the refusal look arbitrary.
  - id: unknown_1b34
    type: u4
    doc: |
      [ELF] T+0x1B34, last 4 bytes of the payload. Meaning still [UNKNOWN] — and it is a stated
      **open question**, not an unsearched slot: the two readers are known and traced, and neither
      can name the cell because the caption is bound in the layout file rather than the ELF. The
      render path is tier 1 and this field is **not** dead like its neighbours.

      **What we send: zero** (`ClanGameController.clanProfile`'s
      `buffer.writeZero(4 + 4 + 4)`), and unlike its neighbours this one **is drawn** — a `0`
      appears in `infoC_st-3` of the clan-info popup and in `STRING_0_3` of the CLAN RECORD
      header. That is not a wrong value, because we have no candidate to put there; it is the
      reason the deciding experiment below is worth running.

      Two readers, both drawing it as a plain number through the formatter `0xCFD018(buf, 20, v)`:
        * `0xA7D32C` `lwz r5,6964(r22)` -> element **`infoC_st-3`** of the clan-info popup
          (element name resolved from the TOC at `0xA7D348`; the popup's other rows are
          `infoC_st-1` = clan name at `0xA7D794`, `infoC_st-2` = leader name at `0xA7D7FC`,
          `infoC_st-5` = `T+0xC68`).
        * `0xA8A970` `lwz r5,6964(r9)` -> element **`STRING_0_3`** in the header of the CLAN RECORD
          screen (`l_shib_y13_02_bg_clan_senseki`, named at `0xA8A414`), where `STRING_0_1` is the
          clan name (`T+0x04`, copied at `0xA8A890`) and `STRING_0_2` is `T+0xC68` clamped to
          9,999,999 at `0xA8A900`-`0xA8A91C`.

      Both slots sit in a *clan record* header, so it is a clan-wide statistic rather than anything
      about the viewer. Which one is [UNKNOWN]: the surrounding labels on that screen are
      `STRING_s_TOTALre`, `STRING_s_TOURNAMENT`, `STRING_s_1st`, `STRING_s_2nd`, `STRING_s_BEST4`,
      `STRING_s_SURVIVAL`, `STRING_s_WIN`, `STRING_s_WINS`, `STRING_s_WINZ`, `STRING_s_GRADE`, and
      the binding of a header cell to one of those labels is in the layout file, not the ELF.
      **0x4b81 sends the same slot** (mgo2_cmd_4b81_s2c.ksy), so a clan reached from search or the
      clan list needs it too.

      ## [ELF 2026-08-01] The clan-info popup, mapped element by element

      The popup renderer (`0xA7CD98`-`0xA7D820`, module mini-TOC `r30 = 0xFF4AF8` via
      `lwz r30,-28004(r2)`, `r2 = 0x10353A8`) keeps the clan record in **r22** for the whole draw
      and sets one element per block, each `format -> 0xD25D0(name) -> 0x244340 -> 0x2452A0 ->
      0x246EC0`. Resolving every TOC slot it touches gives the complete popup:

      | element | source | note |
      | --- | --- | --- |
      | `infoC_st-1` | clan name | `0xA7D794` |
      | `infoC_st-2` | leader name | `0xA7D7FC` |
      | `infoC_st-5` | `T+0xC68` | clamped to **9,999,999** at `0xA7D2C4`-`0xA7D2E0` |
      | **`infoC_st-3`** | **`T+0x1B34`** | `0xA7D32C`, no clamp |
      | `infoC_st-4` | `T+0x58` | `0xA7D398` — **`member_count`**, [CONFIRMED] elsewhere in this file |
      | `infoC_st-6` .. `infoC_st-12` | `T+0x1730, 0x1738, 0x173C, 0x1740, 0x1748, 0x174C, 0x1750` | `r25 = r22+5788` (`0xA7D188`), reads at `+148, +152, +156, +160, +168, +172, +176` |
      | `infoC_st-13` | derived from `T+0x1748` and `T+0x174C` | `0xA7D654`/`0xA7D65C` load both — a ratio cell |

      Three things follow, and none of them names the field, which is why it keeps its name:

      1. **It is drawn immediately before `member_count` and immediately after `T+0xC68`.** Both
         neighbours are clan-wide totals, which is consistent with the existing "clan-wide
         statistic" reading and adds a second, independent screen saying so.
      2. **The popup's other numeric rows are not ours to send.** `infoC_st-6`..`-13` all come out
         of `T+0x1730`-`0x1750`, and `0x4b21` writes none of that range. So of the popup's ten
         numbers, `0x4b21` supplies exactly three — `T+0x58`, `T+0xC68` and this one.
      3. **A tempting second writer is a decoy.** `stw r0,6964(r11)` at `0x4129F8` looks like a
         client-side writer of this exact offset, and it is not: it sits in a `stw` run at
         `6844..7012` with a **16-byte stride** (`6944/6948/6952/6956`, `6960/6964/6968/6972`,
         `6976/6980/6984/6988`, …), i.e. a table of 16-byte records in an engine struct. On the
         clan record `+6956` and `+6960` are the two cooldowns, which that run would trample. The
         only writers of `T+0x1B34` remain the `0x4b21` and `0x4b81` parsers.


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

      ## [ELF 2026-08-02] 0x4b21 and 0x4b81 write the SAME field — bijection, not resemblance

      Asked as a struct-offset bijection rather than a shape match, because "same layout,
      different instance" is the standing trap in this protocol. It is the same **absolute
      address**, not merely the same displacement into two structs:

      * `0x4b21` parser `0xD587AC`: `addis r29,r27,1` (`0xD58890`) makes `r29 = session+0x10000`,
        and `T = r29-1968` (`0xD58898`). The field is read at `0xD58BE8`
        `addi r4,r29,4996` -> `session+0x10000+4996` = `T+6964` = `T+0x1B34`.
      * `0x4b81` parser `0xD58C74`: `addis r31,r31,1` makes `r31 = session+0x10000`, and the same
        `T = r31-1968` (`0xD58CF8`). The field is read at `0xD58DA8` `addi r4,r31,4996` —
        **byte-for-byte the same expression**, off the same session argument.

      Both parsers take the session as their argument and neither indexes an instance, so the two
      packets address one object at one address. The three other slots the two share resolve the
      same way (`T+0x00`, `T+0x04`, `T+0x18`, `T+0x1C`, `T+0x378`, `T+0x67A`, `T+0x58`), which is
      the control: a bijection that only worked for the field under test would be suspect.
      **Consequence: whatever this is, it must be filled for a foreign clan too, and one fix
      covers both packets.** (`0x4b71`'s parser `0xD5992C` computes the identical `T` at
      `0xD599E0` — a third writer of the struct, and it writes `T+0x91C` upward, not this slot.)

      **What would decide it.** Nothing static — both renderers only format the number, and the
      caption is bound in the layout file. The experiment is cheap and we control both inputs:
      serve `T+0x1B34` and `T+0xC68` distinct, recognisable sentinels (they are the only two
      unclamped/clamped numbers on the CLAN RECORD header) and read the two header cells against
      their printed captions. Send `T+0x1B34` above 9,999,999 in one run as well — `T+0xC68` is
      clamped there and this field is not, which distinguishes the two cells even if the captions
      are ambiguous.
