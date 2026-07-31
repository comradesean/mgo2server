meta:
  id: mgo2_cmd_4129_s2c
  title: "MGO2 0x4129 — post-game info result (server -> client)"
  endian: be
doc: |
  **The end-of-round results packet**, the reply to `0x4128`. Variable length: `0x22 + 4*N`
  where `N` is `skill_count`.

  [CONFIRMED 2026-07-29] Every field below was read from the parser, and the parser is
  **`0xD3C9A8`** (ends `0xD3CC88`). It is reached from the command dispatcher `0xD387C8`,
  which loads the id with `lwz r3,0(r3)` and binary-searches: `0xD388B4` tests
  `cmpwi cr7,r3,16681` (= 0x4129), branches to `0xD39080`, and `0xD39084` calls it. Sole
  caller. The parser re-checks the id itself at `0xD3C9F4`.

  ## Why this packet is dangerous

  **It writes thirteen fields of the local profile, and it does not clear them first.** The
  destination base is `r29 = r27 + 22488` (`0xD3CA3C`), which is exactly what
  `getLocalProfile(session)` at `0xD3A094` returns — the same base `0x4b47` and the emblem
  upload write. So every field here lands in the *same* profile slot the connect burst
  (`0x4122`) filled, and **whatever this packet says wins, at the end of every round.**

  That has bitten this server twice, in the same function, three lines apart:

  - the **worn title** at wire `0x04` was sent as `chara.rank`, which reset the scorecard's
    animal-rank badge to nothing after the first match;
  - the **emblem flag** at the last byte was hardcoded to `0`, which cleared the clan emblem
    mid-session — a player started with their emblem and lost it when the first round ended.
    Fixed 2026-07-29.

  The rule to apply: **any field here must agree with what `0x4122` sent**, or the client's
  view is half-updated in a way no later packet corrects.

  ## The escape hatch

  `result` is checked first (`0xD3CA14`) and **a non-zero value skips the entire body**
  (`bne 0xD3CC1C`) — including the emblem flag. So an error reply is genuinely inert and
  cannot corrupt the profile. Only a success reply writes.

  On completion the parser calls the end-read `0xD5C858` at `0xD3CC24` and raises a UI
  notification on event slot 26 (`0xD3CC38` / `0xD3CC4C`).

  ## Reader primitives, for re-verification

  The packet object holds its cursor at `+1108` and its payload at `+64`. Widths are fixed
  by which reader is called: `0xD5CB8C` = u1 (`stb`), `0xD5CC14` = u2 (`sth`),
  `0xD5CC64`/`0xD5CCD8` = u4 (identical bodies), `0xD5D018` = fixed-length block.

  ## One prior finding corrected

  A previous note placed the worn title at wire `0xef`. **That does not survive the
  disassembly**: this parser reads it at wire `0x04`, as the second field, before the
  variable-length array — so no value of `N` can put it at `0xef`. The struct offset
  (`profile+7845`, = `charBlock+0x1EA5`) is sound and unchanged; only the wire offset was
  wrong. The `0xef` figure belongs to **`0x4122`**, which writes the same slot.

  ## Independently corroborated, and what the destinations mean

  This packet was traced twice — 2026-07-26 against the client context base, and 2026-07-29 against
  the local profile base — and **all ten destinations agree exactly**. `profile = ctx + 22488`
  (`0xD3A094`), and every pair maps: `ctx+30333` = `profile+7845`, `ctx+22776` = `+288`,
  `ctx+35585` = `+13097`, `ctx+35588` = `+13100`, `ctx+22780` = `+292`, `ctx+23660` = `+1172`,
  `ctx+29304` = `+6816`, `ctx+29326` = `+6838`, `ctx+29325` = `+6837`, `ctx+29360` = `+6872`.

  **What makes this command legible is where it writes, not what it is called.** Every tail
  destination is a slot some *other* command owns: `+6816` is `0x4122`'s clan id, `+6837`/`+6838`
  open `0x4122`'s unknown prefix, `+6872` is `0x4122`'s emblem flag, `+288`/`+292` are `0x4101`'s
  experience and `grade_points`, and `+13097`/`+13100` are `0x4101`'s `beginner_flag` and
  `dead_13100`.

  So `0x4129` is a **partial re-send of the connect-burst character record after a match** —
  experience, title, skills and the clan block, patched in place. That is also the strongest hint
  available that `0x4101`'s and `0x4122`'s unknown slots at those addresses are **match-mutable**
  values rather than constants.

  **`+1172` is the exception to "partial re-send"** — `play_time_seconds` is not a `0x4101` slot at
  all. It has no connect-burst writer: `0x4129` is the only command in the protocol that sets it,
  which is consistent with it being a cumulative counter the server updates at the end of a round.

  Wait slot **26** (`0x1a`).

  ## The skill loop patches in place

  Unlike `0x4125`, this parser does **not** memset the table first, so it patches records and any id
  it omits keeps whatever `0x4125` established. The 12-byte record is the one documented in
  `mgo2_cmd_4125.ksy`: id at +0, experience widened to u32 at +4, flag at +8.

  **Skill level is derived, never sent** — `0x6FC580` gives `min(exp >> 13, 3)`, so the only
  reachable levels are 0/1/2/3 at experience 0/8192/16384/24576. The flag byte at +8 is what the
  per-skill gates read, including the training check at `0x897320` on skill 17.

  This is where OBSERVED.md's "skill records come from `0x4129`, not `0x4125`" originates: both write
  the same table, but only this one is sent after a round.

  ## A stale claim corrected

  An earlier draft of this spec said the total is "34 + 4*count, which is exactly the 34-byte empty
  readback we send with count 0". The size is right for the **parser** — `0x22 + 4N` is 34 + 4N —
  but wrong about this server, which sends `POST_GAME_INFO_FIXED = 39` plus `4N`. See `trailing`.

seq:
  - id: result
    type: s4
    doc: |
      [CONFIRMED 2026-07-29] Read at `0xD3CA14`. **Non-zero skips every field below**
      (`bne 0xD3CC1C`), so an error reply is 4 bytes and inert.
  - id: body
    type: body
    if: result == 0
types:
  body:
    seq:
      - id: worn_title
        type: u1
        doc: |
          [CONFIRMED 2026-07-29] wire `0x04` -> `profile+7845` (`0x1EA5`), stored at
          `0xD3CA40`. The **worn title**, the scorecard's animal-rank badge — the same slot
          `0x4122` wire `0xef` writes. Sending `chara.rank` here blanks the badge after the
          first match; the two packets must agree.
      - id: experience
        type: u4
        doc: |
          [CONFIRMED 2026-07-29] wire `0x05` -> `profile+288` (`r27+22776`), stored at
          `0xD3CA5C`.
      - id: beginner_flag
        type: u1
        doc: |
          [CONFIRMED 2026-07-30] wire `0x09` -> `profile+13097`, stored at `0xD3CA78`.

          **The character's beginners-only-lobby eligibility.** Non-zero passes the gate; zero
          makes the client refuse such a lobby locally with error screen `0x933` / code `-0x194`
          — "You cannot login to this lobby." The full derivation (six readers, the
          `0x884300` lobby-list predicate on `restrictions` bit 0, the `0x885A08` dialog call) is
          in `mgo2_cmd_4101_s2c.ksy` under the field of the same name, which writes this same
          slot at connect.

          **Must agree with what `0x4101` sent**, per this file's top-level rule: a round ending
          would otherwise revoke the character's lobby eligibility mid-session. The server sends 0
          in both, so they agree today by accident rather than by construction.
      - id: skill_count
        type: u4
        doc: |
          [CONFIRMED 2026-07-29] wire `0x0a`, read at `0xD3CA94`. Element count for
          `skills`. The loop (`0xD3CAA8`-`0xD3CB50`) stops at this value **or at 128**,
          whichever comes first.
      - id: skills
        type: skill
        repeat: expr
        repeat-expr: skill_count
        doc: |
          [CONFIRMED 2026-07-29] wire `0x0e`, 4 bytes each. Scattered into
          `profile+11444 + index*12` as 12 bytes `{index@0, value@4, flag@8}`. An element
          whose `index` is **not `> 0` when read as signed** is skipped entirely.

          These repeat what the `0x4125` catalogue advertised at connect: the parser writes
          the identical array and does **not** clear it first, so disagreeing between the
          two half-updates the client's view of what the player owns.
      - id: dead_13100
        type: u4
        doc: |
          [NO READER IN THE IMAGE 2026-07-30] `B+0` -> `profile+13100`, stored at `0xD3CB64`,
          where `B = 0x0e + 4*N`.

          Only three instructions in the image use displacement 13100: this store, `0xD3C358`
          (`0x4101`'s field of the same name), and `0x4148C4`, which is rejected on provenance —
          one `stw` inside an uninterrupted run at 12944..13100 stride 4, a u32 array in an engine
          struct. Displacements 13098/13099/13101 have no .text hits, so nothing straddles it.
          The confirming observation would be a load at `profile+13100` off a `0xD3A094` base;
          none exists. The server sends 0.
      - id: grade_points
        type: u4
        doc: |
          [PARTIAL] `B+4` -> `profile+292`, stored at `0xD3CB80`. `profile+292` is read at
          `0x905E00` and `0x915F64`, both of which run it through the
          level-from-experience walker `0x6F9260`, clamp to 1..23, index a 24-entry table
          and render `"%s (%d)"` — a title for its level, then the raw number. So it is a
          **second experience-scale quantity**, distinct from the Level. The server mirrors
          `experience` into it.
      - id: play_time_seconds
        type: u4
        doc: |
          [CONFIRMED 2026-07-30] `B+8` -> `profile+1172`, stored at `0xD3CB9C`.

          **Total MGO play time in seconds, and it drives the MGS4 single-player unlock.** This
          closes CLIENT_STORE.md §6's open question about what MGO writes that the offline game
          reads back: it is not written by MGO at all in the sense that was being looked for — the
          *server* supplies the number and the client converts it straight into the `mgof.sav`
          flag word.

          Two readers, both `lwz r3,1172(r3)` with the base from `bl 0xD3A094` a few instructions
          earlier — `0x8F9850` (base from `0x8F9840`) and `0x8F98F8` (base from `0x8F98E8`) —
          and both immediately `bl 0x7F6F70`, which is inside the `.sav` module
          (`0x7F6000`-`0x7F9300`). Those are its only two call sites.

          `0x7F6F70` is short enough to read whole:

          ```
          7f6f70  lis r0,0x91A2 ; ori r0,r0,0xB3C5
          7f6f84  mulhwu r3,r3,r0 ; srwi r3,r3,11      ; r3 = value / 3600  -> HOURS
          7f6f8c  cmpwi cr7,r3,49 ; cmpwi cr6,r3,19
          7f6f80  li r11,15                            ; > 49 h
          7f6f9c  li r11,7                             ; > 19 h
          7f6fd0  li r11,3                             ; > 9 h
          7f6fd8  li r11,1                             ; otherwise
          7f6fa8  lwz r10,-32768(r30) ; lwz r0,0(r10)
          7f6fb4  oris r0,r0,0x8000 ; or r9,r11,r0
          7f6fc4  stw r9,0(r10)                        ; only when a bit is new
          ```

          The divide is exact: `0x91A2B3C5` with `mulhwu` + `srwi 11` is the standard magic for
          **/3600**, which is what fixes the unit as seconds. The tiers are cumulative bits at
          **0, 10, 20 and 50 hours**, OR'd with `0x80000000`, into the single u32 that
          CLIENT_STORE.md §6 measured `mgof.sav` moving.

          **Fixed 2026-07-31.** The server used to send `0xffffff` — 16,777,215 seconds, 4660 hours —
          which tripped every tier immediately, a policy nobody made on purpose. It now sends
          `CharacterService.displayedPlaySeconds(charaId)`: `sum(round_report.seconds_in_game)`
          across the six playable modes, the same total the personal stats screen and `0x4b48` show.
          That is round time only, not menu or lobby presence — a deliberate choice, argued in that
          method's doc, not an oversight.
      - id: clan_id
        type: u4
        doc: |
          [CONFIRMED 2026-07-29] `B+12` -> `profile+6816`, stored at `0xD3CBB8`. The same
          clan record `0x4122` carries.
      - id: privilege_mask
        type: u2
        doc: |
          [PARTIAL] `B+16` -> `profile+6838`, stored at `0xD3CBD4`. The clan privilege mask.
          The server sends 0; nothing grants privileges yet.
      - id: clan_state
        type: u1
        doc: |
          [CONFIRMED 2026-07-29] `B+18` -> `profile+6837`, stored at `0xD3CBF0`. Clan
          membership state. Note the emblem gate at `0x905A8C` requires this to be **1 or
          2** before it will even look at `emblem_flag`.
      - id: emblem_flag
        type: u1
        doc: |
          [CONFIRMED 2026-07-29] `B+19` -> **`profile+6872`**, destination computed at
          `0xD3CC00` (`addi r4,r29,6872`) and stored by the u1 reader called at `0xD3CC0C`.
          **The last byte of the payload.**

          This is the **clan emblem flag**, and this packet is one of only four writers of
          that slot — the others being the `0x4122` parser, `0x4b47` (`0xD584B0`) and the
          emblem upload commit (`0xAD4724`). `0x4221` writes the same offset at `0xD3DA90`
          but against a *different* base: the viewed other player's record, not the local
          profile.

          `0` is not "no picture", it is **"never ask"** — the in-game manager skips the
          fetch and the emblem is silently absent, with no error dialog, only a 6000-tick
          backoff at `0x9D4A34`. It must therefore carry the same value `0x4122` sent: 3
          when the clan has a published emblem, 0 otherwise.

          The value matters in-game because it is republished **peer-to-peer**: the announce
          builder `0x88407C` copies `profile+6872` verbatim to announce `+4` (`0x88415C`),
          and peers apply it to `slot+92`. Nothing in-game can correct it afterwards.
      - id: trailing
        size-eos: true
        doc: |
          [OUR SERVER ONLY] The parser stops after `emblem_flag` — the payload it expects is
          exactly `0x22 + 4*N` bytes. This server currently emits **five further bytes** (a
          u4 character id and a zero u1) which the client never reads.

          Harmless, because the read is closed at `0xD3CC24` before they would be reached,
          but recorded here so a capture decodes cleanly and so nobody later mistakes them
          for fields. Whether the original server sent them is **unknown** — we have no
          Konami capture of this command.
  skill:
    seq:
      - id: index
        type: u1
        doc: |
          [CONFIRMED 2026-07-29] Selects the destination slot `profile+11444 + index*12`.
          Skipped unless `> 0` read as **signed**, so `0` and anything `>= 0x80` are
          discarded by the client.
      - id: value
        type: u2
        doc: "[CONFIRMED 2026-07-29] Written to the slot at `+4`. The skill experience."
      - id: flag
        type: u1
        doc: "[CONFIRMED 2026-07-29] Written to the slot at `+8`."
