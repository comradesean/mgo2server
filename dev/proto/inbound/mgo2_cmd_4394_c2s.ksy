meta:
  id: mgo2_cmd_4394_c2s
  title: "MGO2 0x4394 — client -> server: game-settings block push (UNREACHABLE in this build)"
  endian: be
doc: |
  Builder function `0xD41C90` = `f(session, void *settingsBlock)`; a null session or a null block
  aborts before anything is written (`0xD41C9C`/`0xD41CD0` -> `0xD42144`, return `-0x18`).
  `bl 0xD5CF40` at `0xD41D20` (`li r4,0x4394` at `0xD41D1C`), seal `0xD5C828` at `0xD42100`,
  flush `0xD34CC0` at `0xD42114`. **Not encrypted** (no `0xD5D124` call), consistent with `0x4394`
  being absent from `DECRYPT_COMMANDS`.

  ## 1. THE HEADLINE: this command cannot be sent by this build [ELF, batch 5, 2026-08-01]

  **`0xD41C90` is never entered.** The full four-part entry test, run over the whole executable
  range `0x10200`..`0xDEBEEC` (sections 1-4, every `AX` section in the image):

  - **zero `bl 0xd41c90`** — a full instruction decode of every word in that range for primary
    opcode 18 with `LK=1`, absolute and relative forms both resolved;
  - **zero `b 0xd41c90`** — the same decode with `LK=0`. This is the test `ADDRESSES.md` added on
    2026-08-01 after `0xA7DC48` turned out to have 20 tail calls; it is run here, and it is empty;
  - **zero `bc`/`bca` to `0xd41c90`** — primary opcode 16 decoded as well, for completeness;
  - **its OPD descriptor `0x10295B0` is referenced by no word anywhere in the file** — a byte-wise
    search for the 4-byte pattern `01 02 95 B0` over the whole 17 MB image, unaligned included,
    returns nothing. The image is `ET_EXEC` with no relocations, so there is no third way in;
  - **no fall-through.** `0xD41C8C` is `blr`, the epilogue of `0xD41AC0`;
  - **the address is never materialised.** No `lis`/`ori` or `addi` pair anywhere builds `0xD41C90`
    or `0x10295B0`, and `li r4,17300` at `0xD41D1C` is the **only** occurrence of the constant
    `0x4394` as an instruction immediate in the entire binary — so nothing else sets this id either.

  **The negative was validated against known-good controls before publication**, per
  `ADDRESSES.md`: the identical scan finds `bl 0xd42178` at `0x27DC48` (the `0x4390` serialiser's
  sole caller, which `ADDRESSES.md` §1 already records) and `bl 0xd44d50` at `0x2753EC` (the
  `0x43B0` builder's sole caller). Both live in the same OPD bank as `0xD41C90`
  (`0x10295A0`-`0x10295B8`) and have equally unreferenced descriptors, which also shows that an
  unreferenced OPD descriptor is the *normal* state in this image and proves nothing on its own —
  the `b`/`bl` decode is what carries the result.

  **Consequence for the server: `0x4394` is not a live `FFFFFF60` risk.** It cannot stall a client
  because no client code path can emit it. `PACKETS_NOT_OBSERVED.md` listed it among the four
  "reachable in ordinary play" unhandled commands; that row is corrected. Implementing a handler is
  optional hardening, not a fix. The reply parser is nonetheless live and is specified in §4 below,
  in case a future build re-enables the sender.

  ## 2. WHAT THE PAYLOAD IS: the 204-byte game-settings block, minus `player_count`

  Every field is copied out of the caller's `settingsBlock` (`r28`) by an unbroken run of 45
  write-primitive calls at `0xD41D28`-`0xD420F8`; there is no branching, so the layout is fixed.
  The write primitives take a **pointer** (`addi r4, r28, N` then `clrldi r4,r4,32`), not a value —
  `0xD5C8A0` does `lbz r0,0(r4)`, `0xD5C918` `lhz`, `0xD5C9BC` a byte-wise u32, `0xD5D0AC` a
  `memcpy` of `r5` bytes — so each `addi` displacement names the source offset directly.

  **That source struct is the shared 204-byte game-settings block**, and the proof is that the
  builder is the exact inverse of the block's canonical reader **`0xD4364C`**:

  | | |
  | --- | --- |
  | `0xD4364C` reads | `+0x00`(16 triples) `+0x30` `+0x31` `+0x32`(16) `+0x42` **`+0x43`** `+0x44` `+0x48` `+0x4C` `+0x50` `+0x52` `+0x54` `+0x58` `+0x5C` `+0x5E` `+0x5F` `+0x60`..`+0xA4` `+0xA8`(2) `+0xAA` `+0xAC` `+0xB0` `+0xB1`(2) `+0xB3` `+0xB4` `+0xB6` `+0xB8` `+0xBC` `+0xBD` `+0xBE`(14) |
  | `0xD41C90` writes | the identical list, **at identical widths, in identical order, with `+0x43` omitted** |

  `0xD4364C` is the block reader `mgo2_cmd_4313_s2c.ksy` already documents and calls "the canonical
  model": nine callers — `0xD445A4` (`0x4313`), `0xD48440` (`0x4905`), `0xD48964` (`0x4909`),
  `0xD4B244` (`0x4987` family), `0xD4CB08` (`0x4950`), `0xD5006C` (`0x4A24`/`0x4A31`), `0xD51014`
  (`0x4A00`), `0xD5AF38` (`0x4E10`), `0xD5B78C` (`0x43F1`). **Every field name below is therefore
  `0x4313`'s `game_settings` name, transferred by destination-offset identity** — the legitimate
  form of the inference rule, not neighbour-name guessing: these are literally the same struct
  offsets, read by one function and written by the other.

  **The omitted byte is `player_count`, and that is corroboration rather than a wrinkle.** Block
  `+0x43` is the only field the reader consumes that the builder skips, and it is the one field in
  the block a *client* has no business asserting — the server counts the players. The wire is
  204 − 1 = **203 bytes (0xCB)**, which is where this file's total comes from.

  **Wire-offset rule:** `wire = block` for `block < 0x43`; `wire = block − 1` for `block > 0x43`.
  Every doc below gives both.

  ## 3. Two corrections to this file's own earlier prose

  1. **"Nothing here has a known meaning" is retired.** All 26 unknowns are named above/below.
  2. **There is exactly one hole in the source struct, at `+0x43`, not two.** The earlier text said
     "`record` has holes (e.g. `+0x43`, `+0x56`)". `+0x56` is not a hole: `+0x54` is a u32 spanning
     `+0x54`..`+0x57`. One hole is also what the byte arithmetic requires — 204 source bytes minus
     one skipped byte is the 203 the frame actually measures.

  ## 4. What a reply would have to look like

  **The client registers a wait slot, so a reply is mandatory whenever the command is sent** — it is
  only the sender being dead that makes this moot today.

  On a successful flush the builder calls `0xD32E08(session, 0x2B, 1)` at `0xD42128`-`0xD42134`,
  i.e. it sets **wait slot `0x2B` (43)** to state 1 = outstanding. (`0xD32E08` is
  `SetWaitSlot(session, slot, state)`: slot table at `session + 0x160 + slot*4`, value at `+8`,
  slot capped at `0x74`, state capped at 2.) A failed flush returns `-0x3D` and opens no slot.

  The completing parser is **`0xD40604`** (dispatcher arm `cmpwi r0,0x4395` at `0xD40638`):

  - `0x4395`, payload **exactly 4 bytes**: one big-endian **s32 result**, read by `0xD5CC64` into
    `r1+0x70` at `0xD40650`, then `READ_END` `0xD5C858`. Nothing else is parsed.
  - It then does `0xD32E08(session, 0x2B, 2)` (state 2 = complete) and
    `0xD32E70(session, 0x2B, result)` with `lwa` — so the result is stored **signed**, and by this
    protocol's convention 0 is success and a negative value surfaces as an error.
  - Header mismatch yields `-0x46`; a short read yields `-0x47`.

  `0x4395`'s parser is reachable from the dispatcher independently of the sender, so a stray
  `0x4395` would be accepted and would complete slot 43 — which is *not* a reason to send one.
doc-ref: dev/proto/outbound/mgo2_cmd_4313_s2c.ksy "game_settings"
seq:
  - id: rotation
    type: slot_triple
    repeat: expr
    repeat-expr: 16
    doc: |
      [ELF] wire 0x00-0x2F = block 0x00-0x2F. **`0x4313`'s `rotation`** — the 16-entry map/rule
      rotation. 16 x 3 bytes, interleaved on the wire and scattered into three 16-byte source
      arrays: pass i emits `block+i`, `block+0x10+i`, `block+0x20+i` (loop `0xD41D28`-`0xD41D7C`,
      bound the literal 16 at `0xD41D78`, not a count field). This is exactly the scatter
      `0xD4364C`'s reader loop at `0xD43678`-`0xD436E4` inverts, and exactly what `0x4310` pushes
      at its own wire 0xA3..0xD2.

      The kaitai type is still named `slot_triple` here; it **is** `mgo2_cmd_4313_s2c.ksy`'s
      `rotation_round`, left renamed only at the `- id:` level so no `type:` line moves.
  - id: unknown_30
    type: u1
    doc: |
      [ELF] wire 0x30 = block 0x30, from `settingsBlock+0x30` (`0xD5C8A0` at `0xD41D8C`).
      `0x4313`'s `unknown_48` — still unnamed **there**, and deliberately not given a name here.
      Batch 4b proved `unknown_48`/`unknown_49` are a **two-element pair** published together as
      property-store key 86 (bytes 1 and 5 of an 8-byte record, rest zeroed) with **no create-game
      widget writing either**; see `mgo2_cmd_4313_s2c.ksy`. Position is exact, meaning is open in
      both directions.
  - id: unknown_31
    type: u1
    doc: |
      [ELF] wire 0x31 = block 0x31, from `settingsBlock+0x31` (`0xD5C8A0` at `0xD41DA0`).
      `0x4313`'s `unknown_49` — the other half of the key-86 pair described just above.
  - id: weapon_restrictions
    size: 16
    doc: |
      [ELF] wire 0x32-0x41 = block 0x32-0x41. Raw 16-byte copy from `settingsBlock+0x32`
      (`0xD5D0AC`, `r5=16`, at `0xD41DB8`). **`0x4313`'s `weapon_restrictions`** — published to the
      client property store as key 1 by `0x8CA2BC`-`0x8CA900`. The earlier note here guessed
      "almost always an ISO-8859-1 NUL-padded name"; it is not a name.
  - id: max_players
    type: u1
    doc: |
      [ELF] wire 0x42 = block 0x42, from `settingsBlock+0x42` (`0xD5C8A0` at `0xD41DCC`).
      **`0x4313`'s `max_players`** (property-store key 65).

      **`settingsBlock+0x43` is skipped — the wire has no hole.** That byte is `0x4313`'s
      `player_count`, the one field of the block a client does not get to assert. Every wire offset
      from here on is `block − 1`.
  - id: briefing_time
    type: u4
    doc: |
      [ELF] wire 0x43 = block 0x44, from `settingsBlock+0x44` (`0xD5C9BC` at `0xD41DE0`).
      **`0x4313`'s `briefing_time`** (property-store key 96). Note the misalignment the skipped
      `player_count` introduces: every u32 from here on sits at an odd wire offset. The primitive
      is byte-wise, so alignment is irrelevant to the parse.
  - id: unknown_47
    type: u4
    doc: "[ELF] wire 0x47 = block 0x48, from `settingsBlock+0x48`. `0x4313`'s `unknown_72` — the property-store key-72 value; still unnamed there, and no name is invented here."
  - id: unknown_4b
    type: u4
    doc: "[ELF] wire 0x4B = block 0x4C, from `settingsBlock+0x4C`. `0x4313`'s `unknown_76` — published as key 76 = idle kick x60 per `0x4313`'s publisher note, which is a unit hint rather than a settled name."
  - id: unknown_4f
    type: u2
    doc: "[ELF] wire 0x4F = block 0x50, from `settingsBlock+0x50` (`0xD5C918` = the u16 writer). `0x4313`'s `unknown_80`."
  - id: unknown_51
    type: u2
    doc: "[ELF] wire 0x51 = block 0x52, from `settingsBlock+0x52`. `0x4313`'s `unknown_82`."
  - id: unknown_53
    type: u4
    doc: "[ELF] wire 0x53 = block 0x54, from `settingsBlock+0x54`. `0x4313`'s `unknown_84`."
  - id: unknown_57
    type: u4
    doc: "[ELF] wire 0x57 = block 0x58, from `settingsBlock+0x58`. `0x4313`'s `unknown_88`."
  - id: unknown_5b
    type: u2
    doc: "[ELF] wire 0x5B = block 0x5C, from `settingsBlock+0x5C`. `0x4313`'s `unknown_92`."
  - id: host_stance
    type: u1
    doc: |
      [ELF] wire 0x5D = block 0x5E, from `settingsBlock+0x5E`. **`0x4313`'s `host_stance`**
      (property-store key 94). Independently anchored twice already: `0x4310` writes it from
      `src+846` and `0x43C0` from `settings+0x34E`, and `846 = 752 + 0x5E` under the
      `block+X = struct+752+X` bijection.
  - id: level_limit_tolerance
    type: u1
    doc: |
      [ELF] wire 0x5E = block 0x5F, from `settingsBlock+0x5F`. **`0x4313`'s
      `level_limit_tolerance`** (property-store key 98), named in batch 2b from `0x4310` wire 0x0F7.
  - id: level_limit_and_timers
    type: u4
    repeat: expr
    repeat-expr: 18
    doc: |
      [ELF] wire 0x5F-0xA6 = block 0x60-0xA7. Eighteen u32s written back to back from
      `settingsBlock+0x60` through `settingsBlock+0xA4` in strict 4-byte source order
      (`0xD41EA8`-`0xD41FFC`).

      **This array is not homogeneous, and the schema models it as one only because the width must
      not move.** Against `0x4313`'s `game_settings` it decomposes as:

      * element 0 = block 0x60 = **`level_limit_base`** (property-store key 99);
      * elements 1..17 = block 0x64..0xA7 = **`rule_timers`**, `0x4313`'s 17-element u32 array
        (property-store keys 100, 122-125, 129-130 carry the same values back out).

      The earlier note called the run "the only fully regular run in the frame … per-something
      tallies, no label established". The regularity was real; the reading was wrong — these are
      **round-timer configuration**, not tallies. **WIDTH FLAGGED, NOT CHANGED:** the honest model
      is `level_limit_base: u4` followed by `rule_timers: u4 repeat-expr 17`, which is byte-for-byte
      identical to what is written here. Splitting it is a separate, argued edit.
  - id: unique_red_blue
    size: 2
    doc: |
      [ELF] wire 0xA7-0xA8 = block 0xA8-0xA9. Raw 2-byte copy from `settingsBlock+0xA8`
      (`0xD5D0AC`, `r5=2`, at `0xD42014`) — deliberately a byte pair, not a u16, and now the reason
      is visible: it is **`0x4313`'s `unique_red` and `unique_blue`**, two independent u8 fields.
      **WIDTH FLAGGED, NOT CHANGED:** the two-field form matches `0xD4364C`, which reads block+0xA8
      and block+0xA9 as one 2-byte `0xD5D018` copy as well, so the `size: 2` here mirrors the
      reader exactly. Splitting it into `unique_red: u1` / `unique_blue: u1` is byte-identical and
      is the better model, but it is an argued edit, not a rename.
  - id: unknown_a9
    type: u2
    doc: "[ELF] wire 0xA9 = block 0xAA, from `settingsBlock+0xAA`. `0x4313`'s `unknown_170`."
  - id: unknown_ab
    type: u4
    doc: "[ELF] wire 0xAB = block 0xAC, from `settingsBlock+0xAC`. `0x4313`'s `unknown_172`."
  - id: common_flags_msb
    type: u1
    doc: |
      [ELF] wire 0xAF = block 0xB0, from `settingsBlock+0xB0`. **`0x4313`'s `common_flags_msb`** —
      the high byte of the Common Settings flag word `0x8CA2BC`-`0x8CA900` expands into the
      per-toggle property-store keys.
  - id: common_a_b
    size: 2
    doc: |
      [ELF] wire 0xB0-0xB1 = block 0xB1-0xB2. Raw 2-byte copy from `settingsBlock+0xB1`
      (`0xD5D0AC`, `r5=2`, at `0xD42068`). **`0x4313`'s `common_a` and `common_b`** — the two
      capture-proven Common Settings toggle bytes (`0x4310` wire `0x142`/`0x143`; see the memory
      note "commonA/B at 0x142/0x143, the 0x4110-header theory was wrong").
      **WIDTH FLAGGED, NOT CHANGED**, same reasoning as `unique_red_blue`: `0xD4364C` also reads
      these two as one 2-byte copy, so the pair form mirrors the reader; splitting is byte-identical
      but is an argued edit.
  - id: common_flags_lsb
    type: u1
    doc: |
      [ELF] wire 0xB2 = block 0xB3, from `settingsBlock+0xB3`. **`0x4313`'s `common_flags_lsb`** —
      renamed from `common_c` in batch 2b on the `0x4310` side.
  - id: idle_kick
    type: u2
    doc: "[ELF] wire 0xB3 = block 0xB4, from `settingsBlock+0xB4`. **`0x4313`'s `idle_kick`**."
  - id: team_kill_kick
    type: u2
    doc: "[ELF] wire 0xB5 = block 0xB6, from `settingsBlock+0xB6`. **`0x4313`'s `team_kill_kick`** (property-store key 69)."
  - id: host_ping
    type: u4
    doc: "[ELF] wire 0xB7 = block 0xB8, from `settingsBlock+0xB8`. **`0x4313`'s `host_ping`**."
  - id: capture_extra_time
    type: u1
    doc: "[ELF] wire 0xBB = block 0xBC, from `settingsBlock+0xBC`. **`0x4313`'s `capture_extra_time`**."
  - id: sneaking_snake_kills
    type: u1
    doc: "[ELF] wire 0xBC = block 0xBD, from `settingsBlock+0xBD`. **`0x4313`'s `sneaking_snake_kills`**."
  - id: unread_tail
    size: 14
    doc: |
      [ELF] wire 0xBD-0xCA = block 0xBE-0xCB. Raw 14-byte copy from `settingsBlock+0xBE`
      (`0xD5D0AC`, `r5=14`, at `0xD420F8`) — the last write before the seal, so the frame ends at
      0xCB = 203 bytes. **`0x4313`'s `unread_tail`**, which closes the 204-byte block at 0xCC.
types:
  slot_triple:
    doc: |
      One interleaved pass of the 16-iteration loop: byte i of each of the three source arrays.
      Identical in shape and meaning to `mgo2_cmd_4313_s2c.ksy`'s `rotation_round`; the type name
      is left as-is only so that no `type:` line in this file changes.
    seq:
      - id: rule
        type: u1
        doc: "[ELF] source `settingsBlock+0x00+i`. `0x4313`'s `rotation_round.rule` — the game rule (mode) id for rotation slot i. `rule == 0 && map == 0` terminates the rotation."
      - id: map
        type: u1
        doc: "[ELF] source `settingsBlock+0x10+i`. `0x4313`'s `rotation_round.map` — the map id for rotation slot i."
      - id: flags
        type: u1
        doc: |
          [ELF] source `settingsBlock+0x20+i`. `0x4313`'s `rotation_round.flags`. For round 0 this
          is the per-round radio `GATES.md` §2 reads at `0x6A9948`: 0 Normal, 2 Drebin Points,
          4 Headshots Only. Individual bit meanings beyond that radio remain [UNKNOWN].
