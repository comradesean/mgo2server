meta:
  id: mgo2_cmd_4101_s2c
  title: "MGO2 0x4101 — character info, packet 1/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Reply 1 of the `0x4100` burst. Parser **0xd3c120** (GAME dispatcher 0xd38804, trampoline
  0xd39020). Consumes a fixed **0x142 = 322-byte** grid and never reads past it — fully traced
  0xd3c18c .. 0xd3c380, sixteen read-primitive calls, no loops except the two 32-iteration id
  arrays.

  Client struct base `r27 = ctx+22488` (0x57D8). All destinations below are relative to it except
  the 16-byte block at wire 0x12d, which goes to `ctx+0x10000+6096`.

  **There is no result field.** PROTOCOL.md flags this (item 4): the error path sends 4 bytes into
  a 322-byte grid, putting an error code where the character id goes, and the read primitives do
  **not** compare consumed bytes against the payload length — verified here, the primitives only
  bound the cursor against the 1024-byte receive buffer (`cmpwi r9,1020` etc.), never against the
  packet length. So a short `0x4101` reads the remaining 318 bytes out of stale buffer. Still
  unchecked what the client then does.

  The `0x142` size is a deliberate divergence from the reference servers' `0x243`; the parser
  confirms 322 is right — the friend and blocked arrays are **32 entries each**
  (`cmpdi cr6,r31,32` at 0xd3c2d0 and 0xd3c308), not 64.
doc-ref: dev/docs/PROTOCOL.md "0x4101 — character info, 0x142 = 322 bytes"
seq:
  - id: chara_id
    type: u4
    doc: |
      [CONFIRMED] Wire 0x000 -> +0x00, i.e. `netctx+0x57D8`.

      **This is the id space the rest of the session identifies players by** [ELF 2026-07-26,
      traced for chat]. Two consumers found so far, both outside this parser:

      - **In-game chat attribution.** `0x4401` carries a speaker id which the display consumer
        (`0xC9FFD8`) matches against `roster_entry+0x60` to resolve who spoke. That roster field is
        seeded from this value: the local player's peer descriptor is built at `0x9444BC` with
        `blob[0] = *(netctx+0x57D8)` (verified by disassembly; the descriptor's full 20-byte layout
        is in `dev/docs/STUN.md` "Where the checked address actually goes"), and the peer-join path reads a u32 from the session stream
        and compares it against `netctx+0x57D8` at `0x276694` to recognise itself before storing it
        to `entry+0x60` (`0x27687C`).
      - So a `0x4401` speaker id only renders a name if it equals the `0x4101` chara_id that
        player was sent. Confirmed live 2026-07-26: chat lines render with names.

      Practical consequence: this field is load-bearing beyond the connect burst, and changing what
      we put here would silently break chat attribution rather than failing visibly.
  - id: name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: "[CONFIRMED] Wire 0x004 -> +0x04, fixed 16 (0xd5d018), NUL at +0x14."
  - id: dead_constants
    type: u2
    repeat: expr
    doc: |
      [CONFIRMED DEAD 2026-07-29] Four independent u16 — the parser writes them with four separate
      2-byte reads (`0xD3C1BC`, `0xD3C1D8`, `0xD3C1F4`, `0xD3C210`), so this is not one 8-byte field.

      **Nothing consumes them.** Each has exactly one reader — the bare getters `0x907EC0`,
      `0x907E98`, `0x907E70`, `0x907E48`, every one a plain `return u16;` with no comparison,
      arithmetic or formatting — and **none of those getters is ever called**. Zero `bl` sites, and a
      whole-image scan for any word equal to their OPD descriptors
      (`0x101C308`..`0x101C320`) found nothing, ruling out a vtable slot or TOC pointer. PPC64 emits a
      descriptor for every global function, so their existence is not evidence of use.

      We send the captured `0x16AE, 0x0338, 0x013E, 0x0150` because changing them buys nothing, and
      `MGO2SERVER_EXPERIMENT_ZERO_UNREAD_FIELDS` zeros them for testing. The `0x0150` == 336 ==
      `0x4120` length coincidence has no code behind it and is not a lead.
  - id: experience
    type: u4
    doc: "[ELF] Wire 0x01c -> +0x120. PROTOCOL.md: the account's main exp if this is the main character, else alt exp. Also written by 0x4129's tail."
  - id: previous_login
    type: u4
    doc: "[ELF] Wire 0x020. Read as u32, widened and stored as a **u64** at +0x128 (`std` at 0xd3c274). Unix seconds; we send `now - 1`."
  - id: current_login
    type: u4
    doc: "[ELF] Wire 0x024. Same widening, stored at +0x130. Unix seconds."
  - id: unknown_028
    type: u1
    doc: |
      [PARTIAL 2026-07-30] Wire 0x028 -> +0x3328, i.e. **`profile+13096`** (ctx+35584). Meaning not
      established, but it is live and has two identified readers, both with the base from
      `bl 0xD3A094`:

      - **`0x8842B4`**, in the join-announcement builder: `lbz r29,13096(r11)`, OR'd with bit 5
        derived from `0x9066FC` (settings byte 0 bits 4-5) and stored to **announce +2**
        (`0x8842D8`). Peers land that on record key 350 — the 4-bit field CLIENT_STORE.md §3a
        already records, now with its source instruction.
      - **`0x8BA540`**: `lbz r0,13096(r3); cmpwi cr7,r0,3; beq 0x8BA5D8` — **the value 3 is
        special**, and only 3. That arm checks `0x883F20(...)+660 == 1` and then runs two level
        walks through `0x6F9260`, one on a list entry's `+44` and one on `0x907D98(session)`,
        which is `getLocalProfile(session)->[288]` = this packet's `experience`. So it selects a
        level-comparison display path.

      Rejected on provenance: `0x4148C0 stw r0,13096(r9)` is one store in a dense run of `stw`s at
      12944..13100 stride 4 — a u32 array in an engine struct, and incompatible with `+13097` being
      a separate byte.

      We send zero.

      ## [ELF 2026-08-01] It is a 4-bit enum with a predicate bank, and the in-game HUD reads it

      The `0x8842B4` chain above stops at "record key 350", and CLIENT_STORE.md §3a stops there
      too. It does not stop there in the binary. **Key 350 is a byte offset into the per-slot blob**
      (ADDRESSES.md: "the key IS the byte offset"), which is why searching for `li r4,350` finds
      only the two `RecordSet` writers (`0x276354` own slot, `0x2780CC` peers) and no reader —
      readers address the blob directly. Searching for `lbz rX,350(rY)` instead finds **four
      predicate thunks, and they are the whole readership**:

      | thunk | subject | test |
      | --- | --- | --- |
      | `0x9BEB88` | `f(slot)`, blob via `0x6A95A0` | `(blob[350] & 0xF) == 2` |
      | `0x9BEBE0` | `f(slot)`, same | `(blob[350] & 0xF) == 3` |
      | `0x9BFFF0` | **local player**, `0x26E9A0` then `0x6A95A0` | `(blob[350] & 0xF) == 3` |
      | `0x9C0050` | local player, same | `(blob[350] & 0xF) == 2` |

      Each is the identical five-instruction shape — `bl` for the blob, null check, `lbz r0,350(r3)`,
      `clrlwi r0,r0,28`, `cmpwi` — so the field is **four bits wide on the read side too**, and the
      only values anything distinguishes are **2 and 3**. That matches the write side, where the
      announce byte is `blob[350] = (profile+13096 & 0xF) | (bit from 0x9066FC << 5)`: the client's
      own settings bit lives above the nibble, so bits 4-7 are not ours and bits 0-3 are.

      **18 call sites between them**, all in the in-game HUD/nameplate band: `0x9BEB88` at
      `0x9D4C2C`, `0x9FC6A0`; `0x9BEBE0` at `0x9D0BDC`, `0x9EA5E0`, `0x9EC5E0`, `0x9EC8C4`,
      `0x9FC6B0`, `0xA44984`; `0x9BFFF0` at `0x99CC00`, `0x9D313C`, `0x9EA494`, `0x9EA4D8`,
      `0x9F1674`, `0x9F16B8`, `0x9F1B60`, `0x9F1BA8`, `0xA3BB50`; `0x9C0050` at `0xA2FC94`.
      `0x9FC698`-`0x9FC6BC` calls both slot forms back to back on the same slot and branches to a
      different nameplate construction for `== 3`, which is what shows they are alternatives in one
      enum rather than two independent flags.

      **One consumer is worth naming because of what it is grouped with.** At `0x9EA47C` the code
      reads `if (0x9C0600()) X; else if (0x9BFFF0()) X;` — the same arm for both — and `0x9C0600`
      is `roundMode() == 10 && amHost()`, i.e. *you are the instructor of a Combat Training
      session* (see `mgo2_cmd_3049_s2c.ksy`'s `item_unlock_trailer`, which identifies that
      predicate). So nibble **3** puts a player in the same category as the training instructor for
      at least one HUD decision. That is a strong hint about the family this enum belongs to and it
      is deliberately **not** turned into a name: one shared branch is not an identity, and the
      other seventeen sites have not been read.

      **What would decide it.** Send wire `0x028` = 0, 1, 2, 3 on four successive logins and watch
      the in-game nameplate — `0x9FC6A0`/`0x9FC6B0` guarantees 2 and 3 each produce a visibly
      different construction, and 0/1 the default. Per CLAUDE.md's elimination rule this is a valid
      experiment precisely because the domain being probed (2 and 3) is the domain the readers
      distinguish; a fingerprint outside 0..15 would take the default arm and prove nothing.
  - id: friend_ids
    type: u4
    repeat: expr
    repeat-expr: 32
    doc: |
      [ELF] Wire 0x029 -> +0x20 + i*4. Loop at 0xd3c2b0, bound `cmpdi r31,32`. Flat id array,
      not stats (the same conclusion the `0x4103` trace reached for its identical arrays).
      Always zero here — friends are not modelled.
  - id: blocked_ids
    type: u4
    repeat: expr
    repeat-expr: 32
    doc: "[ELF] Wire 0x0a9 -> +0xa0 + i*4. Loop at 0xd3c2e4, bound 32. Always zero."
  - id: beginner_flag
    type: u1
    doc: |
      [CONFIRMED 2026-07-30] Wire 0x129 -> +0x3329, i.e. **`profile+13097`** (ctx+35585). Also
      written by `0x4129` (wire `+9`), so it is match-mutable.

      **Non-zero means the character may enter a lobby whose list entry is marked "beginners
      only". Zero makes the client refuse the lobby locally**, with error screen `0x933` —
      "You cannot login to this lobby." (ERRORS.md 2355) — and code `-0x194`, one of the two
      codes PROTOCOL.md already maps to that screen.

      Six readers, every one with its base from `bl 0xD3A094`: `0x89224C`, `0x935B34`,
      `0xABCF90`, `0xABDA14`, `0xAC8270`, `0xACCED4`.

      The gate is the same in each of the four dialog sites. `0x935B18`-`0x935B4C` is the clearest:
      `bl 0x884300(lobbyId)`; if that returns non-zero, `bl 0xD3A094`, `lbz r0,13097(r3)`,
      `bne -> skip`; otherwise `li r3,2355; li r4,-404; bl 0x885A08`. `0x8922xx` and `0xAC82xx` are
      the same three instructions with the same two constants.

      **`0x884300` is what makes this a beginner flag.** It walks the client's own lobby list —
      `0xD36BA0` returns the count at `ctx+1876`, `0xD36BB8` indexes `ctx+1872` with
      `mulli r9,r4,52` — and returns 1 only when some entry has `+4 == 2` (a Game lobby),
      `lhz +46 == lobbyId`, and **`rldicl. r9,+48,63,63` — bit 0 of the entry's `restrictions`
      byte**. `mgo2_cmd_2003_s2c.ksy` names that bit `0b1 beginners only`.

      The two non-dialog readers agree: `0xABCF90` and `0xABDA14` compute
      `((value - 1) >>u 31) + 1`, i.e. **2 when zero and 1 when non-zero**, and store it as a
      two-state selector next to a pointer.

      We send zero, which is currently harmless only because we never set the beginners-only
      restriction bit in `0x2003`. Setting that bit without setting this byte would lock every
      character out of the lobby with no server-side trace.
  - id: feature_flags
    size: 16
    doc: |
      [CONFIRMED 2026-07-30] Wire 0x12a, fixed 16 bytes (`0xD3C334` `addis r4,r28,1` +
      `addi r4,r4,6096`, `li r5,16`, `bl 0xD5D018`) -> `ctx+0x10000+6096` = **`ctx+0x117D0`**.

      **This is the feature-flag byte GATES.md §1 documents** — the one holding Team Sneaking
      closed. `featureBit(ctx, n)` at **`0xD382F8`** computes
      `(ctx[0x117D0 + n/8] >> (n & 7)) & 1` and rejects any `n` above 5, so only **bits 0..5 of
      the first byte** are reachable. Bit 0 is Team Sneaking selectable; bits 1..5 are read by the
      same helper and their meanings are unknown. 59 call sites use indices 0, 1, 2, 4 and 5.

      **Correction to the previous note in this file.** It called this "a name-shaped field in a
      far-away structure" and marked it unknown; the address was already indexed in
      ADDRESSES.md, GATES.md and OBSERVED.md as `ctx+0x117D0`, and the connection had simply not
      been made in the schema. It is not name-shaped and it is not far away in the sense implied —
      it is the client's feature-gate byte.

      **Bytes 1..15 have no reader**: `0xD382F8`'s `n <= 5` bound means the accessor can never
      index past byte 0, and nothing else touches `ctx+0x117D1..0x117DF` — the only other
      instruction reaching this region is `0xD35768`, `memset(ctx+0x10000+6096, 0, 17)` in the
      session reset (`r26 = ctx + 0x10000`, `addis r26,r27,1` at `0xD35630`).

      We send zeros, which is the release-day configuration and is deliberate — see
      POST_LAUNCH.md. Sending `0x01` in the first byte turns Team Sneaking on.
  - id: dead_13100
    type: u4
    doc: |
      [NO READER IN THE IMAGE 2026-07-30] Wire 0x13a -> +0x332c = **`profile+13100`** (ctx+35588),
      stored at `0xD3C358` (`addi r4,r27,13100` -> the u32 reader `0xD5CCD8`).

      Exactly three instructions in the image use displacement 13100, and two of them are the
      writers: this one and `0xD3CB58`, the same slot in `0x4129`'s tail (`unknown_b0` there).
      The third, `0x4148C4 stw r0,13100(r9)`, is rejected on provenance — it is one store in an
      uninterrupted run of `stw`s at 12944..13100 stride 4, a u32 array in an engine struct, and
      that reading is incompatible with `profile+13097` being an independently addressed byte.
      Displacements 13098, 13099 and 13101 produce no .text hits at all, so nothing straddles it
      either.

      The confirming observation would be a load at `profile+13100` off a base from `0xD3A094`.
      There is none. The value is nevertheless re-sent after every round by `0x4129`, so it is
      plausibly server-side state the client is expected to store and never use. We send zero.
  - id: grade_points
    type: u4
    doc: |
      [CONFIRMED 2026-07-30] Wire 0x13e -> +0x124 = **`profile+292`**, stored at `0xD3C374`
      (`addi r4,r27,292` -> `0xD5CCD8`).

      **This is the same slot `0x4129` names `grade_points`**, and the reader evidence lives there:
      `0x905E00` and `0x915F64` both run `profile+292` through the level-from-experience walker
      `0x6F9260`, clamp to 1..23, index a 24-entry table and render `"%s (%d)"`. So it is a second
      experience-scale quantity, distinct from Level, and this packet is where it is first set —
      `0x4129` patches it after each round.

      Renamed from `unknown_13e` on that identity alone; the two writes are three instructions
      apart in their respective parsers and hit the same displacement off the same base. We send
      zero here while `0x4129` mirrors `experience` into it, which is an inconsistency worth
      fixing rather than a protocol fact.
