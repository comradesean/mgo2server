meta:
  id: mgo2_cmd_4313_s2c
  title: "MGO2 0x4313 — server -> client: game details (reply to 0x4312)"
  endian: be
doc: |
  Evidence: GAME dispatcher `0xD387C8` (compare tree at `0xD38804`) matches `cmpwi 0x4313` at `0xD38954` -> stub `0xD391F0` ->
  parser **`0xD44388`**, whose settings sub-structure is read by the shared helper
  **`0xD4364C`**. Request-status slot **36**.

  This spec transcribes the layout PROTOCOL.md already establishes from this binary, and adds
  two things the ELF settles:

  - **The settings block is exactly 204 bytes and its reader is shared.** `0xD4364C` reads a
    self-contained 204-byte structure. From block+0x30 onward its destination offsets equal its
    wire offsets; **the leading 48 bytes are the exception** — they are read as 16 interleaved
    triples and scattered into three 16-byte arrays, so wire byte 3i+1 lands at block+0x10+i,
    not at block+3i+1 (see `rotation` below, and `mgo2_cmd_4909_s2c.ksy`'s note on the same
    loop). Total wire consumed is 204 either way, which closes PROTOCOL.md's fixed-size
    arithmetic: `0xA8` header + `204` = `0x174` = **372**, the documented figure, with no slack.
    The same helper is called by the `0x43F1` in-match push, which afterwards memcpy's **204**
    bytes out of it — an independent confirmation of the size. `0x4305` reads a *subset* of the
    same structure (see `mgo2_cmd_4305_s2c.ksy`). `0xD4364C` has **nine** call sites in all:
    0xD445A4 (here), 0xD48440 (0x4905), 0xD48964 (0x4909), 0xD4B244 (0x4987), 0xD4CB08 (0x4950),
    0xD5006C (0x4A24/0x4A31), 0xD51014 (0x4A00), 0xD5AF38 (0x4E10), 0xD5B78C (0x43F1). **This
    file's `game_settings` is the canonical model of that block**; the copies in 0x4909 and the
    0x4Axx files are byte-accounting mirrors and defer to it.
  - **A precondition.** Before reading anything the parser calls `0xD32E3C(ctx, 36)` and
    requires the request-status slot to read **1** (request outstanding). An unsolicited
    `0x4313` is discarded.

  Parse order and error behaviour, from `0xD44388`: verify `hdr.command == 0x4313` (else
  `-70`); open payload; read `result`; **on nonzero, stop** — the remaining fields are never
  read and the transaction completes as failed; else read `game_id` and, if a game is
  currently selected, require it to match the stored id; zero a 968-byte destination region;
  read the fixed part, the 204-byte settings block, then player entries while payload remains
  (`0xD5CEB0`). A truncated entry is `-71`, never a shorter list — the client keeps waiting.

  The read primitives bound-check only against the **1023-byte receive buffer**, not the
  payload length, so a short payload does not error where PROTOCOL.md suggests it would: it
  reads stale buffer bytes into real fields. Sending the full 372 is therefore required for
  correctness, not merely for parse success.

  DISPATCHER ADDRESSING (corrected 2026-07-26). The address long cited as "the dispatcher" is
  the head of its **compare tree**, not the function entry. GAME: function 0xD387C8, tree head
  0xD38804. GATE: function 0xD361A4, tree head 0xD361E8. ACCOUNT: function 0xD37024, tree head
  0xD37074. It is also not a "literal compare chain": each tree head is immediately followed by
  a `bgt` (0xD3880C / 0xD361F0 / 0xD3707C) that splits the id space, i.e. a binary search, so
  ids are not tested in listed order and a "chain position" carries no meaning.
doc-ref: dev/docs/PROTOCOL.md "Reply 0x4313 — 372 bytes plus 28 per player"
seq:
  - id: result
    type: s4
    doc: "[CONFIRMED] wire 0x000. Nonzero aborts the parse and surfaces the error; no field below is read. [ELF 0xD443F4-0xD44424]"
  - id: game_id
    type: u4
    doc: "[CONFIRMED] wire 0x004. If a game is currently selected the client requires this to match it."
  - id: name
    size: 16
    doc: "[CONFIRMED] wire 0x008. ISO-8859-1, NUL-padded. Raw read; the client's slot is 17 bytes (16 + terminator)."
  - id: comment
    size: 128
    doc: "[CONFIRMED] wire 0x018. ISO-8859-1."
  - id: password_enabled
    type: u1
    doc: |
      [ELF, RESOLVED 2026-07-30] wire 0x098 -> details object **+150**. Previously `unknown_098`
      ("PROTOCOL.md folds 0x098-0x099 into 2 bytes zero"). Read by `0xD5CB54` (the duplicate u8
      primitive) at `0xD444E0`, destination `r31-28786`.

      Named by **struct-offset identity with the request builder**, which is the same evidence class
      that named `level_limit_base`. Normalise this parser's destinations against the settings block
      it hands to `0xD4364C` at `0xD445A4` (`r31-28184`), which lands at object `+752`: the object
      base is `r31-28936`, so the reads in `0xD444D4`-`0xD44588` are `+150`, `+167`, `+168`, `+172`,
      `+956`, `+960`, `+964`. Two of those are already pinned independently — `+964` is
      `can_rate_host` and `+752` is the settings block — and `+168` is `lobby_subtype`. The
      `0x4310` request builder writes its password flag from `src+150` and its `dedicated` from
      `src+167` on a struct whose `+168` is likewise the subtype and whose `+752..+955` is likewise
      the settings block, so the two are one layout and these are those fields.

      **The server must send it.** PROTOCOL.md's "2 bytes zero" is wrong: zero here tells the
      browser the game has no password.
  - id: dedicated
    type: u1
    doc: |
      [ELF, RESOLVED 2026-07-30] wire 0x099 -> details object **+167**. Previously `unknown_099`.
      Read at `0xD444FC` (`r31-28769`). Same identification as `password_enabled` above.

      Corroborated on the consumer side: `0xD493CC`, the client's own hosted-game entry
      synthesiser, copies `obj+150` to game-list entry T+0x15 and `obj+167` to T+0x16
      (`0xD494E8`/`0xD494F0`) — the two bits `0x4302`'s `host_options` expands as "password set"
      and "dedicated".
  - id: lobby_subtype
    type: u1
    doc: "[CONFIRMED] wire 0x09a. Lobby subtype — the same byte the game-lobby 0x3003 appends as its trailing flag (LOBBIES.md / PROTOCOL.md 0x4902)."
  - id: average_experience
    type: s4
    doc: "[CONFIRMED] wire 0x09b. Average experience across current players. Note the field is **unaligned** — the parser reads bytewise, so alignment is irrelevant."
  - id: host_score
    type: u4
    doc: |
      [CONFIRMED] wire 0x09f. The host's star **NUMERATOR** — the SUM of ratings received, not an
      average. With `host_votes` as the denominator the client draws
      `clamp(ceil(2 * numerator / denominator), 0, 10)` half-stars, so the ratio is the average and
      the gauge lands on the real star count.

      Filled from `host_review` at query time since 2026-07-29. The `game.host_score` column it
      used to read is dead — V43 kept the votes as history rather than accumulating into a row that
      is deleted at teardown, and nothing reconciled the two, so every host read as unrated however
      many votes they had.
  - id: host_votes
    type: u4
    doc: "[CONFIRMED] wire 0x0a3. The star DENOMINATOR — the COUNT of ratings received. Derived from `host_review` since 2026-07-29; see `host_score`."
  - id: can_rate_host
    type: u1
    doc: |
      [ELF, RESOLVED 2026-07-29] wire 0x0a7. **The host-rating gate**, previously `unknown_0a7`
      ("echo writes 1 verbatim; meaning unknown"). The parser at `0xD44588` stores it to
      `detailsBase + 964`, which is what permits the client's star picker and therefore `0x43C4`.

      **Necessary but NOT sufficient on its own.** `0x4321` wire `0x28` writes the SAME slot
      (`0xD441FC`) and arrives after any pre-join `0x4313`, so a join overwrites whatever this
      packet set. Both must carry the flag. A live capture on 2026-07-29 had this byte = 1 and the
      player still got no prompt, because the join reply had already cleared it back to 0.

      Note the read order downstream: the end-of-game screen snapshots the slot when it is
      CONSTRUCTED (`screen+344`, e.g. `0x9D7F34`), and `0x9DCA34` gates opening the picker on the
      snapshot. The slot itself is only re-read at `0xA31DB0`, after the player has already chosen
      a star rating.
  - id: settings
    type: game_settings
    doc: |
      [ELF 0xD4364C] The 204-byte settings block, wire 0x0a8..0x173. Shared verbatim with
      `0x43F1` and, minus eight fields, with `0x4305`.
  - id: players
    type: player_entry
    repeat: eos
    doc: |
      [CONFIRMED] 28 bytes each, host's entry first, **size-driven** — read while
      `0xD5CEB0` reports payload remaining. No count field. PROTOCOL.md records the client's
      cap as 18, and 372 + 18*28 = 876 fits the transport's 0x400 (1024) payload limit.
types:
  game_settings:
    doc: |
      204 bytes. Offsets below are relative to the block start (wire 0x0a8 in this command).
      From +0x30 onward they also equal the client struct offsets — `0xD4364C` writes each of
      those fields at its own wire offset inside a 204-byte destination. **The first 48 bytes
      are not offset-identical**: the loop at 0xD43678-0xD436E4 reads 16 triples and scatters
      them, wire 3i -> struct+i, 3i+1 -> struct+0x10+i, 3i+2 -> struct+0x20+i. Both statements
      appeared in earlier revisions of this file and contradicted each other; the scatter is the
      correct one.

      **`block+X` is `struct+752+X`, and that is tier 1 in both directions** [ELF 2026-07-30].
      `0xD4364C` writes at `r29+0..203` and the `0x4305` parser inlines the identical sequence
      against the enclosing object, at `r29+752..955` — `0xD45658` writes block+48 to `+800`,
      `0xD456B0` block+66 to `+818`, `0xD45758` block+94 to `+846`, `0xD45790` block+96 to `+848`,
      `0xD459A8` commonA/B to `+929`, `0xD45A38` block+189 to `+941`. Four of those are
      independently anchored (max players, host stance, level-limit base, the capture-proven common
      toggles) and they all satisfy the same `+752` relation, so the whole 204 bytes map with no
      slack. Every `0x4310` finding therefore transfers to this block field-for-field, and vice
      versa; this is **not** neighbour inference, it is the same destination offset.

      **The scan behind the "no reader" verdicts below.** Every displacement access
      (`lbz/lhz/lha/lwz/lwa/ld/stb/sth/stw/std rX,N(rY)`) in the whole text section
      (VA < `0xDE9328`) was enumerated for N in {800, 801, 819, 824, 828, 832, 834, 836, 840, 844,
      846, 847, 848, 922, 924, 928, 931, 936, 940, 941} and for the `N+108` / `N+112` aliases the
      create-game screen introduces. Three decoy families produce most of the noise and are
      excluded by inspection, not by assumption:

      - `0x644FBC`-`0x645240` — the particle loop off `0x644D00` stores a byte at essentially
        every offset in this range against `r29`.
      - a **u32-strided global** loaded from the TOC as `lwz r9,-32768(r30)` and read in long runs
        of `lwz` at 772..956 (`0x9D64B0`, `0x9DC66C`, `0x9DCFD4`, `0x9DDB30`, `0x9E1860`,
        `0xA0A600`, `0xA39DF4`). It cannot be this struct: it reads `+846`/`+847` inside u32s, and
        this struct's `+846`/`+847` are two u8 fields, `+834`/`+844` u16.
      - the lobby/automatch screen object at `0x936964`-`0x93B348`, which has a byte at `+924` and
        words at `+908/+912/+928/+932` — `stw` at `+932` would clobber `+934` here, so it is a
        different object.

      Left over are the **accessor bank** at `0x9070xx`-`0x9078xx` (one `lbz/lhz/lwz rX,N(r3)`
      wrapper per field) and the live users. **The accessor bank is dead**: `bl` counts for
      `0x907784`, `0x90775C`, `0x9074B4`, `0x90748C`, `0x90724C`, `0x907734`, `0x90786C`,
      `0x907844` are all **zero**, the file is `ET_EXEC` with no relocations, and each appears only
      as an OPD descriptor. It pins widths, never liveness.

      **The two live consumers**, worth knowing before re-hunting anything here:

      1. `0x8CA2BC`-`0x8CA900` — the post-create publisher. Expands the `+928` flags word into the
         Common Settings toggles, then pushes ~30 values into the client's 26-record property store
         via `0x27F258(obj, key, len, src)`: key 1 = weapon restrictions, 65 = max players,
         69 = team-kill kick, 72, 76 = idle kick x60, **86 = an 8-byte record carrying block+48 and
         block+49**, 94 = host stance, 96 = briefing time, 98 = tolerance, 99 = level-limit base,
         100 = 22 bytes of timers, 122-125 and 129-130 = the remaining rule timers.
      2. `0xD493CC` — the hosted-game list-entry synthesiser (see `mgo2_cmd_4302_s2c.ksy`).
    seq:
      - id: rotation
        type: rotation_round
        repeat: expr
        repeat-expr: 16
        doc: |
          [CONFIRMED] block +0..+47. **Sixteen** triples, not fifteen: the parser's loop runs
          `i < 16`. Each triple's three bytes land in three *parallel* 16-byte arrays in the
          client, not interleaved — which is why `0x4305`'s destinations look scattered.
          `rule == 0 && map == 0` ends the rotation (PROTOCOL.md 0x4310).
      - id: unknown_48
        type: u1
        doc: |
          [UNKNOWN — meaning; ELF — fate] block +48 (wire 0x0d8), struct **+800**. Parser write at
          `0xD45658` (`0x4305`'s inlined copy) / `0xD436F4` (`0xD4364C` block-relative).

          **It is consumed, and now the consumer is named.** `0x8CA460` (`lbz r0,800(r9)`) copies it
          to `stb r0,125(r1)`, inside an 8-byte scratch the surrounding code has just zeroed
          (`0x8CA444`-`0x8CA450`), and `0x8CA6E4`-`0x8CA6F0` publishes that scratch as
          `0x27F258(obj, key=86, len=8, src=r1+124)` — i.e. **property-store key 86, byte 1**, which
          is exactly where `mgo2_cmd_4310_c2s.ksy`'s `unknown_0d3` said it ended up. So the value
          leaves the ELF into the lobby stage script's namespace; the ELF-side accessor for it
          (`0x90786C`) is dead code, no `bl`, OPD only.

          No meaning is established and none is guessed. echo zeroes it. Note `+800` is a very
          common offset: 771 raw hits image-wide, all but these in unrelated structs.

          [ELF 2026-08-01] **Shape, not meaning, has moved on two counts** — full working in
          `mgo2_cmd_4305_s2c.ksy` under `unknown_0d6`, summarised here because the bijection
          `block+X = struct+752+X` makes it the same byte:

          1. **It is element 0 of a two-element publication.** The key-86 buffer is 8 bytes at
             `r1+124`, zeroed whole at `0x8CA444`-`0x8CA450`, and **only bytes 1 and 5 are ever
             filled** — `+800` -> byte 1, `+801` -> byte 5. Two big-endian u16 slots four bytes
             apart. `unknown_48` and `unknown_49` are two elements of one array, so they are the
             same kind of quantity.
          2. **Nothing in the create-game UI writes either byte.** `+801` has a complete 15-site
             census; the only sites that reach this struct are the two parsers, the `0x4310`
             builder at `0xD44974` (`bl 0xD5C8A0`, put_u8 — it puts them straight back on the
             wire), the publisher `0x8CA468` and the dead accessor `0x907844`. Everything else is
             a different object, and `0x644FBC` is provably so: it writes `+800..+808` as a
             9-byte run, which on this struct would overwrite `weapon_restrictions`.

          So the pair is **server-authoritative and round-trips** with no client control bound to
          it. That rules the obvious experiment out — per CLAUDE.md's elimination rule, moving a
          slider and watching the bytes cannot settle a field the UI has no widget for. The
          remaining route is the lobby stage script that consumes key 86.
      - id: unknown_49
        type: u1
        doc: |
          [UNKNOWN — meaning; ELF — fate] block +49 (wire 0x0d9), struct **+801**. Parser write at
          `0xD45674` / `0xD43710`.

          Same fate as `unknown_48`: `0x8CA468` copies it to `stb r0,129(r1)` = **key 86, byte 5**
          of the same 8-byte property record. Dead accessor `0x907844`. Meaning [UNKNOWN].

          [ELF 2026-08-01] Element **1** of the two-element key-86 publication; its displacement is
          the rare one, so it is the byte whose 15-site census closes the pair. See `unknown_48`
          above and `mgo2_cmd_4305_s2c.ksy`'s `unknown_0d6` for the census itself.
      - id: weapon_restrictions
        size: 16
        doc: |
          [CONFIRMED] block +50 (wire 0x0da). One bit per item, 1 = locked; byte 0 bit 0 is the
          master enable. Per-bit map in PROTOCOL.md, with the bits confirmed weapon-by-weapon
          against this build marked there; the rest are reference-derived and unverifiable here.
      - id: max_players
        type: u1
        doc: "[CONFIRMED] block +66 (wire 0x0ea)."
      - id: player_count
        type: u1
        doc: "[CONFIRMED] block +67 (wire 0x0eb). Current player count. **Absent from 0x4305** — the only live-session field in the block, and the saved-settings reply skips exactly it."
      - id: briefing_time
        type: u4
        doc: "[CONFIRMED] block +68 (wire 0x0ec)."
      - id: unknown_72
        type: u4
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +72 (wire 0x0f0), struct **+824**.
          Parser write `0xD456E8` / `0xD43784`, u32 reader `0xD5CCD8`. First of PROTOCOL.md's "seven
          fields the parser reads and echo zeroes".

          Nothing anywhere loads `+824` off this struct. The scan (see the block doc above) leaves
          only the u32-strided TOC global at `0xA0A638` and the `+108`/`+112` aliases of `+932`
          (idle kick) and `+936`; there is **no accessor-bank wrapper for +824 at all**, unlike its
          neighbours. This reproduces `mgo2_cmd_4310_c2s.ksy`'s independent 2026-07-29 result for
          `src+824` ("no reader and no writer anywhere in the binary") by a different route.

          The `0x02` this reply used to carry at wire 0x0ED was **our own constant** — see
          `mgo2_cmd_4305_s2c.ksy`'s `unread_824`, which shows the round trip was circular. Echoed
          from the request now.
      - id: unknown_76
        type: u4
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +76 (wire 0x0f4), struct **+828**.
          Parser write `0xD437A0`. **Not read by 0x4305, and not sent by 0x4310** — this is one of
          the four fields only this reply and `0x43F1` can set.

          No load of `+828` on this struct anywhere: the in-range hits are all the u32-strided TOC
          global (`0xA0A63C`) or `+108`/`+112` aliases of `+936`/`+940`, and there is **no
          accessor-bank wrapper** for it. So the client stores it and never looks at it again.
      - id: unknown_80
        type: u2
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +80 (wire 0x0f8), struct **+832**.
          Parser write `0xD45704` / `0xD437BC`, u16 reader `0xD5CC14`. Corresponds to `0x4310` wire
          `0x0EE`, whose spec independently reports "no reader anywhere in the binary".

          Every in-range hit at `+832` is the u32-strided TOC global (`0x9D6508`, `0x9DC66C`,
          `0x9DCFD4`, `0x9DDB30`, `0x9E1860`, `0xA0A684`) — which reads `+832` as the first of a
          contiguous `lwz` run through `+888` and so cannot be this struct. **No accessor-bank
          wrapper.**
      - id: unknown_82
        type: u2
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +82 (wire 0x0fa), struct **+834**.
          Parser write `0xD437D8`. **Not read by 0x4305, not sent by 0x4310.**

          Exactly **one** load of `+834` survives the decoy filter, and it is the dead accessor
          `0x907784` (`lhz r3,834(r3)`) — zero `bl` sites, OPD-only, `ET_EXEC` with no relocations.
          The other 180 raw hits are a different struct entirely (a dense `lhz`/`sth` cluster
          through `0x4A3E90`-`0x4D303C`).
      - id: unknown_84
        type: u4
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +84 (wire 0x0fc), struct **+836**.
          Parser write `0xD45720` / `0xD437F4`. Corresponds to `0x4310` wire `0x0F0`, likewise
          reported with no reader.

          All in-range hits are the u32-strided TOC global (`0x9D64C8`, `0x9DC670`, `0x9DCFD8`,
          `0x9DDB48`, `0x9E1878`, `0xA0A68C`). **No accessor-bank wrapper.**
      - id: unknown_88
        type: u4
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +88 (wire 0x100), struct **+840**.
          Parser write `0xD43810`. **Not read by 0x4305, not sent by 0x4310.**

          One survivor, and it is dead: accessor `0x90775C` (`lwz r3,840(r3)`), zero callers. Every
          other in-range hit is the u32-strided TOC global.
      - id: unknown_92
        type: u2
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +92 (wire 0x104), struct **+844**.
          Parser write `0xD4573C` / `0xD4382C`. Last of the seven. Corresponds to `0x4310` wire
          `0x0F4`, likewise reported with no reader.

          All in-range hits are the u32-strided TOC global (`0x9D64D0`, `0x9DC678`, `0x9DCFE0`,
          `0x9DDB50`, `0x9E1880`, `0xA0A698`) or `+112` aliases of `+956` in the create-game screen.
          **No accessor-bank wrapper.**
      - id: host_stance
        type: u1
        doc: |
          [CONFIRMED — corrected 2026-07-30] block +94 (wire 0x106), struct **+846**. Position exact
          (`0xD43854` / `0xD45758`). **The host stance** — the Create Game and in-game "Conditions"
          row, a u8 enum 0..9 named in the client's own developer table at `0xE1BC48`+
          (HOST_STANCE_EASY .. HOST_STANCE_NONE), range-gated `cmplwi 9 / bgt` at `0xA31230`. Full
          table and the disc labels are in `../inbound/mgo2_cmd_4310_c2s.ksy`.

          **This retracts the 2026-07-26 downgrade written above it.** That note said the name was a
          reference-server label, tier 4, "absent from OBSERVED.md's confirmed table", and — the
          arithmetic slip — that block +94 maps to `0x4310` wire `0x101`. It maps to `0x4310` wire
          `0x0F6`, which `mgo2_cmd_4310_c2s.ksy` confirmed outright on 2026-07-29. Two further
          consumers pin it here: `0x8CA580` publishes `+846` as property-store key 94, and
          `0xD49530` copies it into the game-list entry's T+0x24, which `0x4302` also calls stance.
      - id: level_limit_tolerance
        type: u1
        doc: |
          [CONFIRMED] block +95 (wire 0x107), struct **+847**. Position exact
          (`0xD43868` / `0xD45774`).

          [ELF 2026-07-30] Now tier 1 on the consumer side too, which matters because the *request*
          spec had this same byte as `unknown_0f7`: `0x8CA544` publishes `+847` as property-store
          key 98, immediately beside key 99 = `+848` (level-limit base), and `0xD49550` copies it
          into game-list entry T+0x26, which `0x4302` calls `level_limit_tolerance`. The picker at
          `0x93452C`-`0x93455C` then uses entry `+38` as `±tolerance` around entry `+40` (the base)
          when testing a candidate's level — a tolerance in every operational sense.
      - id: level_limit_base
        type: u4
        doc: |
          [CONFIRMED] block +96 (wire 0x108). **Identified 2026-07-26; was `unknown_96`.**
          OBSERVED.md's 2026-07-22 sweep proved "Level-limit base is a u32 at `0x4310` wire
          `0xF8`". `0x4310` carries this same block from wire 0xA3 and omits the same fields
          `0x4305` omits (+67, +76, +82, +88 before this point = 11 bytes), so
          0xA3 + 96 - 11 = 0xF8. The mapping is independently pinned by the neighbouring
          tolerance byte (+95 -> 0xF7, also capture-proven) and by
          `mgo2_cmd_4310_c2s.ksy`'s own note that the request's 0xFC timer block corresponds to
          this reply's 0x10C — a constant +0x10, which puts request 0xF8 at reply 0x108 exactly.
          echo's verbatim `0x16` is 22, matching OBSERVED.md's "50,000 experience renders as
          level 22" and its finding that the base tracks the hosting character's level.
          Structurally it is the first of a run of **eighteen** consecutive u32 reads; the
          1 + 17 split PROTOCOL.md draws is therefore semantic and now justified.
      - id: rule_timers
        type: u4
        repeat: expr
        repeat-expr: 17
        doc: |
          [ELF] block +100..+167 (wire 0x10c..0x14f), struct **+852..+916**. Per-rule timers,
          rounds and tickets, in the order SNE t/r, CAP t/r, RES t/r, TDM t/r/tickets, DM
          t/tickets, BASE t/r, BOMB t/r, TSNE t/r.

          **The ordering is no longer tier 4** — this file's "[INFERRED], echo is the only naming
          available" note is superseded by the three-line corroboration recorded in
          `../inbound/mgo2_cmd_4310_c2s.ksy` (2026-07-28) and reproduced here from the binary:
          `0x8CA470`-`0x8CA4CC` multiplies exactly eight of the seventeen by 60 before publishing
          them, and the eight are struct `+888, +876, +868, +860, +852, +896, +904, +912` = indices
          **9, 6, 4, 2, 0, 11, 13, 15** — precisely the eight time fields under this ordering, with
          no count scaled and no time left unscaled. The other nine are stored
          unscaled, as bytes, at `0x8CA558`-`0x8CA5AC`.

          The Sneaking "kill Snake" figure is **not** in this array — see `sneaking_snake_kills`
          below.
      - id: unique_red
        type: u1
        doc: |
          [ELF] block +168 (wire 0x150), the first byte of a **2-byte raw block** read at
          0xD43A80 (0xD5D018 r5=2) — the parser draws no boundary between +168 and +169.

          **The two-u8 split is no longer [INFERRED]** [ELF 2026-07-30]: `0x8CA5C0` and `0x8CA5C8`
          load struct `+920` and `+921` as two separate `lbz` and publish them to two separate
          property-store keys, so the client itself treats them as independent bytes.

          The names, the "unique character per team" reading
          and the "+0x80 when random" encoding are all tier 4 and **[UNKNOWN] here**:
          OBSERVED.md records that unique characters could not be tested in this build (absent
          from its UI). What the ELF supports is "2 raw bytes at block +168".
      - id: unique_blue
        type: u1
        doc: |
          [ELF] block +169 (wire 0x151), second byte of that same 2-byte raw block. Same caveat
          as unique_red: position [ELF], name and meaning [UNKNOWN], untestable in this build.
      - id: unknown_170
        type: u2
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +170 (wire 0x152), struct **+922**.
          Parser write `0xD43A90`. **Not read by 0x4305, not sent by 0x4310** (its builder note
          records that `src+922..928` exist in the client's struct and are never transmitted).

          Exactly one load of `+922` survives the decoy filter and it is the dead accessor
          `0x9074B4` (`lhz r3,922(r3)`, zero `bl` sites). The only other hits image-wide are the
          particle loop at `0x645214` and two unrelated `0x474350`/`0x475390` sites outside every
          settings, screen and parser range.
      - id: unknown_172
        type: u4
        doc: |
          [UNKNOWN — NO READER IN THE IMAGE, 2026-07-30] block +172 (wire 0x154), struct **+924**.
          Parser write `0xD43AAC`. **Not read by 0x4305, not sent by 0x4310.**

          One survivor, dead: accessor `0x90748C` (`lwz r3,924(r3)`). The `0x936994`-`0x93B348`
          cluster that also touches `+924` belongs to the lobby/automatch screen object, not to
          this struct — it `stw`s `+932`, which here would clobber `+934`.
      - id: common_flags_msb
        type: u1
        doc: |
          [ELF, RESOLVED 2026-07-30] block +176 (wire 0x158), struct **+928** — the **most
          significant byte of the 32-bit Common Settings flags word**, i.e. bits 24..31 of the word
          whose middle bytes are `common_a` and `common_b`. Previously `unknown_176`.
          **Not read by 0x4305, not sent by 0x4310.**

          The parser reads it as its own u8 (`0xD43AD4` via `0xD5CB8C`) into `+928`, and 117 sites
          image-wide then do `lwz rX,928(rB)` and bit-test the result — the toggle expansion at
          `0x8CA2BC`-`0x8CA420` and the create-game rows at `0x8A5D3C`-`0x8A6C74` /
          `0x8A8CC0`-`0x8A9258`.

          **No site tests any bit this byte owns.** `../inbound/mgo2_cmd_4310_c2s.ksy` established
          on 2026-07-29 that every test lands in bits 8-23, i.e. in `+929`/`+930` only; bits 24-31
          are this byte and bits 0-7 are `common_flags_lsb`. The disc's Common Settings list is ~16
          items, matching bits 8-23 exactly, so there is no leftover label for this byte either.
          The name says what the byte *is*; what it would mean if set is [UNKNOWN].
      - id: common_a
        type: u1
        doc: |
          [CONFIRMED] block +177 (wire 0x159), struct **+929**. Same bitfield as the 0x4302 entry.
          Read as a 2-byte raw block with common_b (`0xD43AF4` / `0xD459A8`).

          **Bits 23-16** of the 32-bit flags word based at `common_flags_msb`. *Corrected
          2026-08-02: this said "bits 8-15", and `common_b` said "bits 16-23". The word is
          big-endian, so the byte order is msb, 23-16, 15-8, lsb — the two labels were swapped.*
          The `team_kill_kick` note below already said "commonB bit 7", which is consistent with
          the corrected reading and not with the old one, so the error was in these two range
          labels alone.
      - id: common_b
        type: u1
        doc: |
          [CONFIRMED] block +178 (wire 0x15a), struct **+930**. **Bits 15-8** of that same word —
          corrected 2026-08-02, see `common_a` above for why the two were swapped.
      - id: common_flags_lsb
        type: u1
        doc: |
          [ELF, RESOLVED 2026-07-30] block +179 (wire 0x15b), struct **+931** — the **least
          significant byte** (bits 0-7) of the same 32-bit flags word. Previously `unknown_179`;
          `../inbound/mgo2_cmd_4310_c2s.ksy` carries it as `common_c` at wire `0x144`.

          It has its own u8 read (`0xD43B10` / `0xD459C8`), distinct from the raw-2 covering
          `+929`/`+930`, and the `0x4310` builder splits the same way. **Bits 0-7 are never
          tested** by any of the 117 flag-word sites; the only load of `+931` anywhere is the dead
          accessor `0x9072AC`.

          The `0x20` this reply used to inject at wire 0x147 was our own constant (bit 5, which no
          site consumes) and is echoed from the request now — see
          `mgo2_cmd_4305_s2c.ksy`'s `unread_931`. It is a live *slot*, in that the client stores it
          and replays it; nothing reads it.
      - id: idle_kick
        type: u2
        doc: |
          [CONFIRMED] block +180 (wire 0x15c), struct **+932**. Zeroed by the client when commonA
          bit 0 is clear.

          [ELF 2026-07-30] The unit is **minutes**: `0x8CA424` loads `+932` and `0x8CA458`
          multiplies it by 60 before publishing it as property-store key 76 (`0x8CA63C`).
      - id: team_kill_kick
        type: u2
        doc: |
          [CONFIRMED] block +182 (wire 0x15e), struct **+934**.

          **The claim "zeroed when commonB bit 7 is clear" was too strong and is REFUTED
          (2026-08-02).** It came from the create-game screen, which does keep flags bit 15 in step
          with this value at `0x8A5F90`-`0x8A5FB0` — but that invariant is **local to that one
          screen**. 170 of 214 archived `0x4310` captures carry exactly the pairing the claim says
          cannot exist (`common_b` zero, `team_kill_kick` = 3), and the publisher at `0x8CA534`
          copies the value out with **no bit test**. So the value is live regardless of the bit.

          The parallel claim on `idle_kick`/`commonA` bit 0 is a different matter: it is
          **confirmed 214/214** and stands.
          Published as property-store key 69 at `0x8CA534`/`0x8CA608` — **as a single byte**
          (`stb r0,273(r1)` after an `lhz`), so the client's own downstream copy truncates above 255
          even though the wire field is 16 bits.
      - id: host_ping
        type: u4
        doc: |
          [ELF, RESOLVED 2026-07-30] block +184 (wire 0x160), struct **+936**. Previously
          `unknown_184` ("echo writes 0x2e verbatim — regression guard only"). **Not read by
          0x4305, not sent by 0x4310**, so this reply and `0x43F1` are the only ways to set it.

          The client's hosted-game entry synthesiser `0xD493CC` — which builds a `0x4302` list
          record straight out of a game-details object of exactly this shape — reads it and puts it
          in the entry's ping slot:

          ```
          d49548  lwz r0,936(r31)
          d4954c  stw r0,144(r1)     ; scratch+144 = entry T+0x20
          d49588  lswi/stswi 28      ; scratch -> list element +32
          ```

          `T+0x20` is `0x4302`'s `ping`, independently confirmed by the picker at
          `0x934574`-`0x934590`, which buckets entry `+32` against 20 and 80 and prefers lower.
          echo's verbatim `0x2e` = 46, a plausible millisecond figure, which fits.

          **Caveat kept explicit:** what the ELF proves is the destination slot, not a unit. Nothing
          else in the image reads `+936` — the only other survivor of the scan is the dead accessor
          `0x90724C`.
      - id: capture_extra_time
        type: u1
        doc: |
          [CONFIRMED — corrected 2026-07-30] block +188 (wire 0x164), struct **+940**. Position
          exact (`0xD43B80` / `0xD45A1C`). **Capture Mission "EXTRA TIME"** — extend the round until
          a victor emerges; a plain toggle, handler `0x8A02B4` is `x = x ? 0 : 1`, drawn as disc
          string 33 "ON" / 34 "OFF".

          **The "name is [UNKNOWN], it is a reference-server label" note above is superseded.**
          `../inbound/mgo2_cmd_4310_c2s.ksy` named it from the disc on 2026-07-29 — row label 507
          "EXTRA TIME" under header 498 "Capture Mission", help 541 *"Enabling this adds extra time
          to the end of the round until a victor emerges."* — and its `src+940` is this `+940`.
      - id: sneaking_snake_kills
        type: u1
        doc: |
          [CONFIRMED — corrected 2026-07-30] block +189 (wire 0x165), struct **+941**. Position
          exact (`0xD43B9C` / `0xD45A38`). **Sneaking Mission "SNAKE"** — how many times Snake must
          be defeated for Red and Blue to win.

          **Renamed from `sneaking_snake_side`, which was wrong.** The client renders it as a number
          (`0x89D7B8`) and clamps it to [1,5] in the create-game adjuster (`0x8A1AC8`) — a side index
          would be 0/1/2 and drawn as a name. The disc names it directly: row label 508 "SNAKE",
          units 520 "times", help 542 *"Set the number of times Snake must be defeated (victory
          condition for Red and Blue Teams)."* The `0x4310` and `0x4305` specs corrected this on
          2026-07-28/29; this file had not been updated.
      - id: unread_tail
        size: 14
        doc: |
          [PARTIAL] block +190..+203 (wire 0x166..0x173), struct **+942..+955**. **One 14-byte raw
          read** (`0xD43BBC`), so the parser draws no field boundaries here at all.

          **The client never reads OR WRITES any byte of it** [ELF, per
          `../inbound/mgo2_cmd_4310_c2s.ksy` 2026-07-29, and unchanged by the 2026-07-30 sweep].
          The block has exactly three touch points in the whole binary: the `0x4310` builder
          emitting it (`0xD44C3C`), the `0x4305` parser reading it (`0xD45A54`), and the create-game
          initialiser memsetting it to zero (`0x89B5E8`). Its default is therefore fourteen zero
          bytes, and all 214 archived captures (`dev/proto/samples/4310/`) carry it entirely zero.

          **The old field name `byte_timers_and_tail` encoded a claim that is not true and has been
          removed.** PROTOCOL.md's subdivision — 8 byte-sized timers for Stealth DM, Interval, Solo
          Capture and Race, a zero, an extra-time/non-stat flag, 4 zeros — is echo's, and it names
          modes whose strings **do not exist on this disc at all**: the online-lobby set enumerates
          exactly eight rules (DM, TDM, Rescue, Capture, Sneaking, Base, Bomb, Team Sneaking) and
          the ELF developer table agrees. Splitting this region needs live divergence testing, not
          disassembly.
  rotation_round:
    doc: |
      [CONFIRMED] One rotation entry, 3 wire bytes. Sixteen of them open the 204-byte settings
      block. `rule == 0 && map == 0` terminates the rotation (PROTOCOL.md 0x4310). Note the
      **wire is interleaved**: the parser reads triple i as {rule -> +i, map -> +0x10+i,
      flags -> +0x20+i}, so the three fields of one entry are adjacent on the wire but land in
      three separate 16-byte arrays in the client.
    seq:
      - id: rule
        type: u1
        doc: |
          [CONFIRMED] Game rule (mode) id for this rotation slot -> block+0x00+i. Capture-proven
          as a rotation entry via the 0x4310 push, whose copy of this block starts at wire 0xA3
          and whose 16 triples occupy 0xA3..0xD2 (OBSERVED.md / PROTOCOL.md 0x4310).

          **The rule-id-to-mode mapping is now TIER 1** [2026-08-02] — it was tier 4, inherited
          from a reference server, and it turns out to have been correct. The tournament detail
          panel resolves it from the client's own string table: `strres(0x654515, rule + 22)` at
          `0x9019C8` gives `DM TDM RES CAP SNE BASE BOMB TSNE` for ids 0..7, and the long forms at
          `2*rule` agree. The client bounds the id 0..7 itself (`cmplwi 7` / `bgt` at `0x901A70`).
      - id: map
        type: u1
        doc: |
          [CONFIRMED] Map id for this rotation slot -> block+0x10+i. Position and role as above.

          **The id-to-map-name table is now TIER 1** [2026-08-02], and was also correct as
          inherited. `0x902010` / `0x90205C` call `strres(0x654515, map + 74)`; ids 75..89 give
          `JNGL A.A. U.U. G.G. B.TOWN L.D B.B. UNDER CLOCK N.SILO M.DEPO M.M. SANO S.A SHOP`, with
          the long forms at `map + 59` (ids 60..74).

          **Map ids are 1-based: 1..15, with 0 meaning empty.** Worth stating outright, because an
          off-by-one here silently selects the wrong map rather than failing.
      - id: flags
        type: u1
        doc: |
          [ELF] Third byte of the triple -> block+0x20+i, i.e. struct+784+i, from the client's third
          16-byte array (`src+784` on the 0x4310 write side). Position exact.

          [ELF 2026-07-30] **"flags" is now more than an array-grouping label for index 0.** The
          hosted-game entry synthesiser copies `struct+784` — round 0's byte — straight into the
          `0x4302` game-list entry at T+0x1b (`0xD49520`/`0xD49524`), beside `+752` -> T+0x19
          (`rule`) and `+768` -> T+0x1a (`map`). Combined with GATES.md §2, whose reader `0x6A9948`
          treats the per-round third byte as a three-way radio (`0` Normal, `2` Drebin Points, `4`
          Headshots Only), the identification is consistent end to end. Rounds 1..15 have no such
          consumer traced. Individual bit meanings beyond that radio remain [UNKNOWN], and no
          single-variable sweep in OBSERVED.md has moved the byte.
  player_entry:
    doc: "28 bytes. Host first."
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED] +0x00."
      - id: name
        size: 16
        doc: "[CONFIRMED] +0x04. ISO-8859-1, NUL-padded."
      - id: ping
        type: u4
        doc: "[CONFIRMED] +0x14. Fed from the 0x4398 report."
      - id: experience
        type: u4
        doc: "[CONFIRMED] +0x18. From the account's main/alt pool per character."
