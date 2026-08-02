meta:
  id: mgo2_cmd_4e11_s2c
  title: "MGO2 0x4e11 — Survival Match List: entrant-table rows, 31 or 47 bytes each (server -> client)"
  endian: be
doc: |
  Decrypted payload after the 24-byte transport header (dev/docs/CRYPTO.md). NOT capture-proven —
  every field below comes from the client parser only, so tags are [ELF] at best.

  **SURVIVAL MATCH LIST.** The 0x4Exx block is the Survival Match List browser; the identification
  is in mgo2_cmd_4e00_c2s.ksy. `0x4E11` carries the rows of the list — the **entrant table of the
  Tournament/Survival event record**, the 128-row, 52-byte-stride array at `session+0xDBD0 +0x0F0`.

  TIER. Post-launch content; no available client build exercises this command, so **everything
  here is tier 1 and cannot be raised to tier 2.** Not served in v1.

  ## Destination proven, and it is 0x4A11's table

  The parser takes `0xD4EA60(session)` = **`session+0xDBD0`** (0xD5AB24), steps to the list header
  at **+0x0E8** (`lwzu r0,232(r28)`, 0xD5AB4C), requires the magic there to be non-zero — i.e.
  `0x4E10` must have opened the list — and writes each row at `header + 8 + 52*index`
  (0xD5ACD8-0xD5ACFC) = `session+0xDCC0 + 52*index` = **event record +0x0F0 + 52*index**.

  `mgo2_cmd_4a11_s2c.ksy` reaches the *same address* by the same arithmetic and calls it the
  entrant table. That is a struct-offset bijection — same base, same stride, same offsets, same
  widths — so **every field name below transfers from 0x4A11** except the two slots 0x4A11 does not
  have (see `unknown_0x16` and `win_streak`).

  ### 0x4A11 vs 0x4E11: same table, two fillers, two extra bytes

  | mem offset | 0x4A11 | 0x4E11 |
  | --- | --- | --- |
  | rec+0x00 u4  | `entrant_id`   | `entrant_id` |
  | rec+0x04 [16]| `entrant_name` | `entrant_name` |
  | rec+0x15 u1  | `status`       | `status` |
  | rec+0x16 u1  | — (not on its wire) | **`unknown_0x16`** |
  | rec+0x18 [16]| `name2` (conditional) | `name2` (conditional) |
  | rec+0x29 u1  | `unknown_0x28` (declared readerless) | **`row_flags` — readers found here** |
  | rec+0x2C u4  | `unknown_0x29` (declared readerless) | **`detail_number` — reader found here** |
  | rec+0x31 u1  | — (0x4A11 says +0x30..0x33 is memset and never touched by the wire) | **`win_streak`** |

  So `0x4E11` is the richer filler of the two: 47 bytes to `0x4A11`'s 45, and the two extra bytes
  are the ones the Survival Match List screen actually renders.

  **Reported, not edited (outside this batch's file list): `mgo2_cmd_4a11_s2c.ksy` declares
  rec+0x29 and rec+0x2C readerless. That negative is now stale** — readers exist at 0x930334 /
  0x9303B0 / 0x932024 / 0x9320A0 and at 0x93101C / 0x930910 respectively, all inside the Survival
  Match List module, which reaches the table through `0xD5A8B4` rather than through `0xD51CF4`.
  A displacement sweep that only followed `0xD51CF4`'s eight call sites could not have seen them.

  ## The row accessor, and where the count comes from

  `0xD5A8B4(session, index)` is this subsystem's row getter: it bounds `index` by the **u16 at
  event record +0x0DA** (`lhz r0,218(r28)`, 0xD5A90C) — `0x4E10`'s `entrant_count` — and returns
  `table + 52*index + 8`. `0xD5A810` exposes the same u16 as the list length. Note the running
  count this parser bumps lives at **+0x0EC** and is a *different* number; the accessor never
  consults it. A server that lets the two disagree will produce rows the UI cannot reach.

  Items for the 0x4e10 / 0x4e11 / 0x4e12 exchange (slot 90).

  **Count source: size-driven, no count field** (0xD5CEB0 at 0xD5AB88, loop back at 0xD5AD10) —
  BUT unlike the 0x4b54/0x4b75/0x4b92 lists, records are **not appended**: the leading u2 of each
  record is used as the array INDEX (0xD5ACCC-0xD5ACF4: `cmplwi 127; bgt -> stop`, then
  `mulli x,52`), while the count at list+4 is merely incremented. So the server controls
  placement, records may arrive out of order, an index > 127 aborts the loop, and a repeated
  index silently overwrites while still bumping the count. That is a genuinely different
  count/placement model from the clan lists and is exactly the kind of thing that has bitten this
  project before — worth a server-side WARN if index >= 128 or a duplicate index appears.

  Wire record = **31 or 47 bytes** (`name2` is conditional — see `name2_present`); client struct =
  52. The `lswi`/`stswi` pair at 0xD5ACF8-0xD5AD08 is one contiguous 52-byte copy split in two only
  because `lswi` maxes out at 32 bytes: scratch[0..31] -> row+0, scratch[32..51] -> row+32.

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
    doc: "[ELF] Size-driven; each record self-addresses via its `index` field."
types:
  record:
    doc: |
      **31 or 47 wire bytes** -> 52-byte client struct, placed at list+8+index*52.

      **CORRECTED 2026-08-02 from a flat "47 wire bytes".** `name_2` is conditional. This file
      was not in the correction batch's list at all -- a third independent ELF pass found it by
      sweeping for the *cause* of a known error class rather than for its symptoms, which is the
      only reason it was caught.
    seq:
      - id: slot_index
        type: u2
        doc: |
          [ELF 2026-08-02, renamed from `index`] Read FIRST, at 0xD5ABA4 -> r1+114, i.e. **outside**
          the 52-byte scratch record at r1+116 — it is the destination row, not part of the stored
          data. `0xD5ACCC`-`0xD5ACF4` reloads it, rejects `> 127` (`cmplwi 127; bgt` — aborts the
          whole loop, it does not skip the row), multiplies by 52 and writes at `header + 8 + 52*n`.

          So the **server chooses where each row lands**, rows may arrive out of order, and a
          repeated index silently overwrites while still bumping the running count at +0x0EC.
          Bijection with mgo2_cmd_4a11_s2c.ksy's `slot_index`, same role and the same 127 ceiling.
      - id: entrant_id
        type: u4
        doc: |
          [ELF 2026-08-02, renamed from `unknown_02`] Read at 0xD5ABBC -> row **+0x00**. **The
          entrant's (team's) id.**

          Bijection with mgo2_cmd_4a11_s2c.ksy's `entrant_id`, and independently corroborated by
          this subsystem's own readers, which are the stronger evidence:
            * `0x930F44` and `0x930130` treat **`+0x00 == 0` as "row empty"** and substitute lobby
              string 18 (`----`) for the whole row.
            * `0x930454` compares it against `*(0xD491F8(session) + 0x00)` — the **player's own
              team id** (`session+0xD928+0`, the slot mgo2_cmd_491b_c2s.ksy already names) — and
              highlights the row when they match. That is a team id being compared to a team id.
            * `0x8CC41C` / `0x8CDA30` scan the same table for the row whose +0x00 equals the event
              record's `+0x1C40`, and print that row's name as the winner.

          It is the same id space as `0x4E20`'s `participant_a_id` / `participant_b_id`.
      - id: entrant_name
        size: 16
        type: str
        encoding: ASCII
        doc: |
          [ELF 2026-08-02, renamed from `name`] 16-byte raw read at 0xD5ABD8 -> row **+0x04**, with
          the reader's NUL landing on row +0x14. **The team name, and the row's own label**:
          `0x93015C`-`0x93016C` hands row+0x04 to the string copier `0xAF70F0` and then to
          `0xCA5A68` (set-widget-text) for the two list-row widgets; when `entrant_id` is 0 it
          substitutes lobby string 18 (`----`) instead.

          Bijection with mgo2_cmd_4a11_s2c.ksy's `entrant_name`, which reaches the same slot and
          renders it as the `%s` of lobby strings 776/777 (*"Team %s has won the match."*).
      - id: status
        type: u1
        doc: |
          [ELF 2026-08-02, renamed from `unknown_17`] Read at 0xD5ABF8 -> row **+0x15**.
          **Per-entrant status byte.**

          Bijection with mgo2_cmd_4a11_s2c.ksy's `status`, which is itself named by bijection: the
          `0x4A01` parser (0xD509F8-0xD50A3C) and the `0x4A20` parser (0xD51C5C-0xD51CA0) each
          carry a byte array one byte per entrant and write it to `table + 261 + 52*i`, and
          261 = 0xF0 + 0x15 — exactly this slot for every row. So this is the per-row value those
          two bulk-update commands overwrite wholesale. [UNKNOWN] what the codes mean; nothing
          enumerates them and no capture can reach them.

          Storage quirk carried over from 0x4A11: row+0x14..0x17 is a u32 the client also uses as a
          bitfield (see `name2_present`), so this byte occupies bits 16..23 of that word.
      - id: unknown_0x16
        type: u1
        doc: |
          [ELF 2026-08-02, renamed from `unknown_18` to name its destination] Read at 0xD5AC14 ->
          row **+0x16**. [UNKNOWN].

          **This slot does not exist on 0x4A11's wire** — it is one of the two extra bytes 0x4E11
          carries — so no name transfers and none is invented here. It sits in bits 8..15 of the
          same u32 as `status`.

          **No reader.** Swept the window where every reader of this table lives — the 22 `bl
          0xD4EA60` sites, the 8 `bl 0xD51CF4` sites and the 18 `bl 0xD5A8B4`/`0xD4EAAC` sites, all
          of which fall inside 0x8CC000-0x933000 — for `lbz/lhz/lwz` at displacement 22 off a row
          pointer. Nothing in that window resolves to this table (the 0x8F6164/0x8F6D84/0x8F85A8
          hits are `lhz` on an unrelated struct, and 0x9292F4 is a field-copy loop over a different
          record at r31+312). Controls that DID come back from the identical sweep: displacement 41
          (0x930334, 0x9303B0, 0x932024, 0x9320A0), 44 (0x93101C, 0x930910) and 49 (0x930220,
          0x93023C, 0x930240, 0x931F10, 0x931F2C, 0x931F30) — the three fields named below. So the
          sweep works and this negative is real.
      - id: name2_present
        type: u1
        doc: |
          [ELF] Read at 0xD5AC40 into stack scratch (r1+112, below the 52-byte record at r1+116) and
          **never stored** -- which is exactly why the old doc noted it was "read into the low end
          of the element buffer, out of order relative to its neighbours". That oddity was the tell:
          it is a presence bitmask, not a data field.

          **Bit 1 (value 0x02) decides whether `name2` is on the wire at all**: `lbz r0,112(r1)` /
          `rldicl. r9,r0,63,63` / `beq 0xd5ac78` at 0xD5AC40-0xD5AC48 skips the 16-byte read at
          0xD5AC68 when the bit is clear. When it is set, 0xD5AC4C-0xD5AC64 also OR `0x40` into the
          u32 at row+0x14, which is the flag the renderer at 0x930F50 tests.

          **CORRECTED AGAIN 2026-08-02: the bit is 0x02, not 0x01.** The 2026-08-02 pass that made
          this field conditional got the *condition right and the bit wrong*, and `& 0x01` would
          have desynced exactly the packets `& 0x02` decodes. Two independent proofs:
            * `rldicl rA,rS,63,63` rotates left 63 (= right 1) and keeps one bit, so it extracts
              **bit 1**. The calibration ladder is inside `0x4E10`'s own parser, which expands a
              flags byte bit by bit: `clrldi. r9,r0,63` (bit 0) at 0xD5AE50, `rldicl. r9,r0,63,63`
              (bit 1) at 0xD5AE68, `rldicl. r9,r0,62,63` (bit 2) at 0xD5AE80, down to
              `rldicl. r9,r0,58,63` (bit 6) and `extsb`/`bge` (bit 7). Bit 0 has a *different*
              instruction, and it is not the one used here.
            * mgo2_cmd_4a11_s2c.ksy's `name2_present` carries the identical instruction sequence at
              0xD52070-0xD52078 and already declares `if: (name2_present & 0x02) != 0`. Two
              schemas over one instruction pattern now agree.

          The other six bits are read and discarded. Renamed from `unknown_19` -> `name_2_present`
          -> `name2_present` to match the sibling schema.
      - id: name2
        size: 16
        type: str
        encoding: ASCII
        if: (name2_present & 0x02) != 0
        doc: |
          [ELF 2026-08-02, renamed from `name_2`] 16-byte raw read at 0xD5AC68 -> row **+0x18**,
          NUL at row+0x28. **Conditional on `name2_present` bit 1** — see that field for the bit
          correction. This is what makes the record 47 bytes with the bit and 31 without.

          [UNKNOWN] whose name, and this subsystem does have a reader for it where 0x4A11 does not:
          0x930F5C-0x930FA4 copies 32 bytes from row+0x18 with `0xAF70F0` and sets it on two
          detail widgets, falling back to lobby string 18 (`----`) when the bit is clear. That
          tells us it is *displayed*, not whose it is. A team leader's handle beside the team name
          is the shape that fits, but it is still not evidenced.
      - id: row_flags
        type: u1
        doc: |
          [ELF 2026-08-02, renamed from `unknown_2b`] Read at 0xD5AC84 -> row **+0x29**. **A
          per-row 2-bit display flag field**, and this is a *new* reader — mgo2_cmd_4a11_s2c.ksy
          declares the same slot (`unknown_0x28`) readerless, because its sweep followed the
          `0x4Axx` accessor `0xD51CF4` and this subsystem reaches the table through `0xD5A8B4`.

          Both low bits are tested, each gating one widget's enabled/highlight state through the
          `oris 16448` / `rlwinm`+`rotlwi`+`oris 16384` idiom that this module uses everywhere for
          show/hide:
            * **bit 0** (`clrldi. r9,r0,63` at 0x930338) -> the widget looked up at 0x930324.
            * **bit 1** (`rldicl. r9,r0,63,63`, 0x9303B0-0x9303B4) -> the widget looked up at
              0x9303A0.
          Repeated verbatim in the sibling row renderer at 0x932024 and 0x9320A0. Bit-position
          reading calibrated against `0x4E10`'s flags ladder (see `name2_present`).

          [UNKNOWN] what the two bits mean. The widget names are 24-bit GCX name hashes
          (`0xCA5B40(obj, hash)`) that do not resolve against dev/tools/gcx/dictionary.txt, so the
          labels cannot be read out; bits 2..7 are never tested.
      - id: detail_number
        type: s4
        doc: |
          [ELF 2026-08-02, renamed from `unknown_2c`] Read at 0xD5ACA0 -> row **+0x2C**. **A number
          rendered as decimal on the row's two detail widgets.** New reader, same story as
          `row_flags`: 0x93101C does `lwa r5,44(r4)` off the row pointer and passes it with the
          format string at 0xE2E3F0 — literally `"%d"` — to `0xDD0688` (sprintf), then to
          `0xCA5A68` for the widgets fetched at 0x930DDC and 0x930DF4. Gated on `entrant_id != 0`
          (0x931010); when the row is empty it prints lobby string 18, `----` instead. Second site
          at 0x930910.

          The `s4` declaration is **evidenced here and stays**: the reader is `lwa`, a
          sign-extending load, which per this file's CORRECTION section is exactly the kind of
          caller-side evidence that does establish signedness (the primitive 0xD5CC64 does not).
          [UNKNOWN] what the number counts — `"%d"` carries no units and the widget names do not
          resolve.
      - id: win_streak
        type: u1
        doc: |
          [ELF 2026-08-02, renamed from `unknown_30`] Read at 0xD5ACBC -> row **+0x31**, last byte
          of the record. **The team's consecutive-win count in the Survival ladder** — the best-named
          field in this packet, because the client prints it in words.

          0x930220-0x930288: the renderer loads `row[i] + 49`, then fetches **row `i+1`** through
          `0xD5A8B4` and takes `max(row[i][49], row[i+1][49])`, then formats that byte into disc
          "lobby" string **808** = `"%d wins in a row"` via 0xDD0688 and sets it on two widgets.
          Repeated verbatim at 0x931F10-0x931F30.

          Two consequences worth writing down:
            * **Rows are consumed in pairs.** Taking the max over `i` and `i+1`, together with the
              `andi. r22,r24,1` / `srawi r29,r24,1` parity split at 0x930204/0x93050C and the
              screen's own header string 810 `"DEFENDER / CHALLENGER"`, says even/odd rows are the
              two sides of one match and the streak label belongs to the match. A server that fills
              rows singly will label matches wrongly.
            * **This slot is 0x4E11-only.** mgo2_cmd_4a11_s2c.ksy states that row+0x30..0x33 is
              memset to zero and never touched by 0x4A11's wire, so nothing transfers and nothing
              overwrites it — `0x4E11` is the only source of a team's streak in this table.

          It is a u8, so streaks cap at 255; the same counter reaches 0x4E20 as a pair of separate
          u8 fields on the Survival ladder record.
