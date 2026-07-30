meta:
  id: mgo2_cmd_4b54_s2c
  title: "MGO2 0x4b54 — clan ROSTER rows, 68-byte records (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md).

  **The clan roster.** Middle packet of the 0x4b53 / 0x4b54 / 0x4b55 triple answering 0x4b52.
  [CONFIRMED LIVE 2026-07-27] for the head of the record; the trailing game-location fields are
  still [UNKNOWN] and go out as zeros.

  **Members and applicants are ONE batch, flagged per row.** Two live experiments settled this, and
  both are worth keeping because each one looks like the obvious answer:

    * Sending them as **two separate 0x4b54 packets** — members then applicants, which is how the
      list is built upstream — put both on the wire and the client rendered only the FIRST. The
      applicant simply vanished. The client appends into one array, but the screen consumes one
      packet's worth.
    * Mixing applicants into the members query but setting `is_member` **per batch** rather than
      per row made the applicants appear as full members.

  One packet, with `is_member` set honestly per row, is the combination that works.

  Routing: GAME dispatcher 0xD387C8, compare tree at 0xD38804 -> thunk -> parser
  **0xD57E10**, which re-checks the id (`cmpwi r0,19284`) before reading anything.

  Middle packet of the 0x4b53 / 0x4b54 / 0x4b55 triple (see mgo2_cmd_4b53.ksy). Sends NO request
  slot update at all — it only appends records, which is why the start and end packets exist.

  **Count source: size-driven, no count field.** The loop (0xD57E7C-0xD5800C) calls 0xD5CEB0
  before each record and stops when the read cursor reaches the payload length. Records are
  APPENDED at list+8+n*76 with the running count at list+4; the client refuses at n > 63, so at
  most **64** records fit — a 65th record is a hard parse failure (-71), not a truncation.
  List object: session[+0x10000+6404] + 0x20000 + 16360.

  Wire record = 68 bytes; client struct = 76 bytes (8 bytes of padding/derived fields never on
  the wire). A payload whose length is not 4 + a multiple of 68 will desync — the readers
  bound-check the 1023-byte receive buffer, not the payload (PROTOCOL.md).

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
    doc: "[ELF] Size-driven; see the top-level doc. No leading count."
types:
  record:
    doc: |
      68 wire bytes -> 76-byte client struct. One clan member, or one pending applicant, told apart
      by `is_member`.
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED 2026-07-27] struct+0x00, the member's CHARACTER id — what 0x4b30 / 0x4b32 / 0x4b36 / 0x4b60 / 0x4b62 name them by."
      - id: name
        size: 16
        type: str
        encoding: ASCII
        doc: "[CONFIRMED 2026-07-27] struct+0x04, the member's character name, 16 bytes fixed. Renders in roster order."
      - id: is_member
        type: u1
        doc: |
          [CONFIRMED 2026-07-27] struct+0x15. **1 for a joined member, 0 for a pending applicant.**

          Set it per ROW, not per batch, and put both kinds in one packet — see the top-level doc
          for the two ways of getting this wrong and what each looked like on screen.
      - id: unknown_18
        type: u4
        doc: |
          [UNKNOWN] struct+0x18. Sent as zero; nothing on screen has moved with it.

          **[ELF — NEGATIVE 2026-07-30] No reader found.** `+0x18` (disp 24) is a very common
          displacement, so this negative is weaker than the ones below: the clan UI band has 70+
          `lwz rX,24(rY)` and each was checked for a roster-row base rather than proven absent
          wholesale. The five at `0xAC8F9C` / `0xACA5B4` / `0xACAA04` / `0xACBA84` / `0xACD9AC` —
          the ones that look like roster reads — are **not**: they read `T+0x18` off the *clan
          profile* (`0xD54404`), i.e. `leader_chara_id`, and compare it against each row's id at
          `+0x00`. See mgo2_cmd_4b21_s2c.ksy.

          Scan that establishes it: rows live at `list+8+n*76` where `list =
          session[+0x10000+6404] + 0x20000 + 16360`. Only four pieces of code reach them — the accessor
          `0xD5A0A8` (`GetRosterRow(session, i)`, `mulli r9,r4,76` at `0xD5A0E0`, three `bl` sites:
          `0x8EC288`, `0x8EC74C`, `0x8ECA88`) and the three stride-76 walkers `0xACB7F0`, `0xACFC7C`,
          `0xAD11F4`, which are the only `addi rX,rY,76` in the whole clan UI band. Both sets were
          taint-scanned across their enclosing functions. Beyond that the selected row's fields are
          read in the jump path at `0xAC7A80`-`0xAC8900` and `0xACCD00`-`0xACCE00`, which were scanned
          by displacement.
      - id: unknown_30
        type: u4
        doc: |
          [UNKNOWN] struct+0x30 — read here, out of struct order (parser `0xD57F2C`, staged at
          `r1+160` then memcpy'd with the rest).

          **[ELF — NEGATIVE 2026-07-30] No reader found.** As with `unknown_18` this rests on a
          displacement sweep rather than a closed dataflow: the four `lwz rX,48(rY)` in the clan UI
          band (`0xACA068`, `0xACA160`, `0xACBD08`, `0xACBD0C`) are all scroll-list bookkeeping on
          UI objects, not roster rows.

          Scan that establishes it: rows live at `list+8+n*76` where `list =
          session[+0x10000+6404] + 0x20000 + 16360`. Only four pieces of code reach them — the accessor
          `0xD5A0A8` (`GetRosterRow(session, i)`, `mulli r9,r4,76` at `0xD5A0E0`, three `bl` sites:
          `0x8EC288`, `0x8EC74C`, `0x8ECA88`) and the three stride-76 walkers `0xACB7F0`, `0xACFC7C`,
          `0xAD11F4`, which are the only `addi rX,rY,76` in the whole clan UI band. Both sets were
          taint-scanned across their enclosing functions. Beyond that the selected row's fields are
          read in the jump path at `0xAC7A80`-`0xAC8900` and `0xACCD00`-`0xACCE00`, which were scanned
          by displacement.
      - id: lobby_id
        type: u2
        doc: |
          [ELF — NAMED 2026-07-30] struct+0x1c. **The id of the lobby this member is in**, and the
          value the "jump to this member" path dials.

          The [INFERRED] guess recorded here previously — "a lobby id" — is now tier 1:

          * `0xAC7CD4` `lhz r4,28(r11)` off the selected roster row, handed to
            `0xD47CE0(session, id)`. That resolves the id through `0xD35C7C`, which walks the
            client's own lobby table with a 52-byte stride and matches on `lhz r0,54(r11)`
            (`cmpw cr7,r0,r28` at `0xD35CF4`) — i.e. it is looked up **as a lobby id in the lobby
            list**, the same list `0x4902` fills (parser `0xD47E18`).
          * The resolved index is then written into the client's own property store:
            `0x27EF90(25)` (RecordBuffer for the local player's settings record) followed by
            `0x27F258(rec, key 254, len 2, &value)` at `0xAC7CE4`-`0xAC7D04`. See CLIENT_STORE.md;
            record 25 is the same record whose key 140 holds the hosted-game name.
          * Two further readers confirm the type: `0xAC7FB4` compares it against the lobby the
            player is already in (`cmpw cr7,r26,r0`, and a mismatch aborts the jump), and
            `0xAC80BC` passes it to `0x884300`, another lobby-table lookup. A fourth at
            `0xACD60C`.

          **A zero here is not neutral** — it will be looked up like any other id. Leave it 0 only
          while `location_kind` is also 0, which is what actually disables the jump.
      - id: unknown_1e
        size: 16
        type: str
        encoding: ASCII
        doc: |
          [UNKNOWN] struct+0x1e, 16 bytes fixed. Sits immediately after `lobby_id`, which is the
          only reason anyone guessed "lobby name"; that guess is still unsupported.

          **[ELF — PRECISE NEGATIVE 2026-07-30] No reader, and this displacement is distinctive
          enough for the negative to be strong.** There is **no** `lwz/lbz/lhz/ld/addi rX,30(rY)`
          anywhere in `0xA70000`-`0xAEFFFF` other than eleven `lbz r8,30(r9)` in the
          `0xA8B`-`0xA9B` band and four more in `0xAEF`, none of which is on a roster row. Nothing
          ever takes the address of `struct+0x1e`.

          Scan that establishes it: rows live at `list+8+n*76` where `list =
          session[+0x10000+6404] + 0x20000 + 16360`. Only four pieces of code reach them — the accessor
          `0xD5A0A8` (`GetRosterRow(session, i)`, `mulli r9,r4,76` at `0xD5A0E0`, three `bl` sites:
          `0x8EC288`, `0x8EC74C`, `0x8ECA88`) and the three stride-76 walkers `0xACB7F0`, `0xACFC7C`,
          `0xAD11F4`, which are the only `addi rX,rY,76` in the whole clan UI band. Both sets were
          taint-scanned across their enclosing functions. Beyond that the selected row's fields are
          read in the jump path at `0xAC7A80`-`0xAC8900` and `0xACCD00`-`0xACCE00`, which were scanned
          by displacement.

          Supporting negative on the presentation side: the clan screens do declare elements named
          `STRING_LOBBY`, `STRING_GAME` and `STRING_HOST` (hashed at `0xAAB858`, `0xAAB868`,
          `0xAAB878`), but each of those three names is referenced **exactly once** in the whole
          image, inside the routine that blanks them. Nothing ever writes text into them.
      - id: unknown_34
        type: u4
        doc: |
          [ELF 2026-07-30] struct+0x34. **It has readers, and it is a gate**, but the identity of
          the value is still [UNKNOWN].

          * `0xAC89B0` `lwz r0,52(r3)` then `cmpwi cr7,r0,0; beq 0xAC8878` — **zero here takes the
            "cannot jump" branch**, so this is the second condition (after `location_kind`) that
            decides whether the roster offers to follow a member.
          * `0xAC7AF4` `lwz r3,52(r9)` -> `bl 0x8B8B50`, which is called from only three places in
            the image (`0x896C9C`, `0x936438`, and here). What `0x8B8B50` does with it is not
            traced, so calling this a "game id" would be inference from position, not evidence.

          What would settle it: naming `0x8B8B50`, or a live session with a member actually in a
          game.
      - id: unknown_38
        size: 16
        type: str
        encoding: ASCII
        doc: |
          [UNKNOWN] struct+0x38, 16 bytes fixed.

          **[ELF — PRECISE NEGATIVE 2026-07-30] No reader.** There is **no** load or `addi` at
          displacement 56 anywhere in `0xA70000`-`0xAEFFFF`, and nothing takes the address of
          `struct+0x38`. Same scan as `unknown_1e`, and the same `STRING_HOST`-is-only-ever-cleared
          observation applies.

          Scan that establishes it: rows live at `list+8+n*76` where `list =
          session[+0x10000+6404] + 0x20000 + 16360`. Only four pieces of code reach them — the accessor
          `0xD5A0A8` (`GetRosterRow(session, i)`, `mulli r9,r4,76` at `0xD5A0E0`, three `bl` sites:
          `0x8EC288`, `0x8EC74C`, `0x8ECA88`) and the three stride-76 walkers `0xACB7F0`, `0xACFC7C`,
          `0xAD11F4`, which are the only `addi rX,rY,76` in the whole clan UI band. Both sets were
          taint-scanned across their enclosing functions. Beyond that the selected row's fields are
          read in the jump path at `0xAC7A80`-`0xAC8900` and `0xACCD00`-`0xACCE00`, which were scanned
          by displacement.
      - id: location_kind
        type: u1
        doc: |
          [ELF — NAMED 2026-07-30] struct+0x49, last byte of the record. **A small enum that gates
          the "jump to this member" path.** The individual values are still [UNKNOWN]; that it is
          the gate is not.

          * `0xAC7E64` `lbz r0,73(r9)` then `cmpwi cr7,r0,0; beq` — **0 disables jumping outright**
            and the whole follow path is skipped.
          * `0xAC8864` `lbz r0,73(r3)` then `cmpwi cr7,r0,1; beq 0xAC89B0` and
            `cmpwi cr7,r0,8; beq 0xAC89B0` — **only the values 1 and 8** reach the game-join arm
            (which then requires `unknown_34` to be non-zero). Anything else falls through to
            `li r25,2` at `0xAC8878`.
          * It is also latched: `0xAC7C90` copies it into the clan-screen context byte `+660`
            (`stb r11,660(r26)`, with `+661` zeroed), and `0xAC7EB8`/`0xAC7EBC` re-read the
            refreshed row and compare against that latch — a change between selecting and jumping
            aborts the jump.

          "Subtype", the old [INFERRED] label, is a plausible reading of a 1/8 enum but is not
          evidenced; the name here says only what the byte does.
