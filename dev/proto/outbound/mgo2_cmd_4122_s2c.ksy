meta:
  id: mgo2_cmd_4122_s2c
  title: "MGO2 0x4122 — personal info, packet 5/9 of the connect burst (server -> client)"
  endian: be
doc: |
  Parser **0xd3d02c** (GAME dispatcher 0xd38804, trampoline 0xd39050). **0xf5 = 245 bytes**,
  fully traced 0xd3d0a0 .. 0xd3d630, field by field with no opaque regions.

  Two client struct bases: `r26 = ctx+29304` (0x7278, the clan / personal block) and
  `r28 = ctx+30136` (0x75B8, the appearance-and-skills block). The appearance block is the same
  struct `0x4131` writes into, which is how the two specs cross-check each other.

  ### Correction to PROTOCOL.md: there are FIVE skill slots, not four

  PROTOCOL.md's table reads wire 0x4c..0x6a as `4 x u8 skills`, `u8 zero`, `4 x u8 levels`,
  `u8 zero`, `4 x u32 experience`, `5 bytes zero`. The parser reads the same 31 bytes as three
  loops of **five**:

      0xd3d500  loop x5: u8  -> r28+30 + i     (bound `cmpdi cr6,r31,5`)
      0xd3d530  loop x5: u8  -> r28+35 + i     (bound 5)
      0xd3d560  loop x5: u32 -> r28+40 + i*4   (bound 5)
      0xd3d5a0  u8           -> r28+60

  So PROTOCOL.md's "zero at 0x50" is the **fifth skill id**, "zero at 0x55" is the **fifth skill
  level**, and its "5 bytes zero at 0x66" is the **fifth experience u32** (4 bytes) plus the lone
  u8 at wire 0x6a. Byte counts agree exactly; only the interpretation differs. `0x4131`'s parser
  (0xd3c3dc) has the identical 5/5/5 shape into the same struct offsets, and both agree with
  `0x4103`'s traced tail ("9 x u8 · u32 · 14 x u8 · 10 x u8 · 5 x u32 · u8 · u32 · 128-byte
  comment", PROTOCOL.md) — three independent parsers, all five-wide. Serving zeros in the fifth
  slot is what we already do, so nothing is broken; the field names were wrong.
doc-ref: dev/docs/PROTOCOL.md "0x4122 — personal info, 0xf5 = 245 bytes"
seq:
  - id: clan_id
    type: u4
    doc: "[ELF] Wire 0x00 -> ctx+29304. Always 0 — clans are not modelled. Also rewritten by 0x4129's tail."
  - id: clan_name
    size: 16
    type: str
    encoding: ISO-8859-1
    doc: "[ELF] Wire 0x04 -> ctx+29308, fixed 16, NUL at +16. Always empty."
  - id: clan_state
    type: u1
    doc: |
      [PROVED 2026-07-26] Wire 0x14 -> ctx+29325 = **profile+6837** (`0xd3a094` returns ctx+22488,
      which is what maps every ctx offset in this parser onto a profile displacement). Clan
      membership state, and the client writes it itself, so the enum is readable from its handlers:
      **0** affiliation pending (`0xD58740`, the 0x4B42 request builder), **1** member
      (`0xD56B68`, 0x4B41 status -1201), **2** leader (`0xD56B84` status -1212; `0xD56E90` for
      0x4B01), **99** not in a clan (`0xD56B44`, `0xD56C7C`, `0xD56D68` — each `li r0,99;
      stb r0,6837(r3)` with the base from `bl 0xd3a094`, and each zeroes the clan id alongside).
      Every reader tests membership with the same idiom `addi r9,r9,-1; cmplwi cr7,r9,1; bgt`,
      i.e. in a clan iff the value is 1 or 2; the client never distinguishes 1 from 2.
      Written by four commands — 0x4103 (`0xD3EC34`), 0x4122 (`0xD3D0D0`), 0x4129 (`0xD3CBE4`),
      0x4B47 (`0xD5849C`) — so it is live server-owned state, not padding.
      We sent `01` (in a clan) with a clan id of 0; harmless only because nearly every reader
      checks the id first. Now `0x63`.
  - id: clan_privileges
    type: u2
    repeat: expr
    repeat-expr: 12
    doc: |
      [PROVED for element 0; elements 1-11 PROVED unread] Wire 0x15 -> ctx+29326 + i*2 =
      **profile+6838 + i*2**. Twelve separate 2-byte reads (0xd5cc14).

      **Element 0 is the clan privilege bitmask**, part of the same clan block: 0x4B47's parser
      writes clan id, clan name, +6837, +6838 and the emblem flag in one run
      (`0xD58490`-`0xD584B0`), and 0x4129 writes clan id + 6838 + 6837 + emblem
      (`0xD3CBAC`-`0xD3CC0C`). Bits are tested individually — bit 0 at `0x8F9944`
      (`lhz r0,6838(r3); clrldi. r9,r0,63`), bit 8 at `0xAB3480` — and the whole value is OR'd
      into a UI flags word at `0xAB0118` and passed as a mask to `0xCFD0A0` (`0xACF188`,
      `0xAD26A8`). Every one of those bases comes from a `bl 0xd3a094` within a few instructions.

      **Elements 1-11 (profile+6840..+6860) have no reader in the binary.** Checked exhaustively:
      no lhz/lha/sth/lbz at any of those 22 displacements, and no `addi` producing a pointer into
      the array; the only `addi ...,6838` sites are the two parsers themselves (`0xD3CBC8`,
      `0xD3EC50`). The one apparent array walk, `0x950480`-`0x9505CC`, was rejected on provenance:
      its base is a per-player results record striding 200 bytes, and it writes rather than reads.

      The original's transcribed values (`0000 000C 0001 0000 ...`) were one captured character's
      clan record. We send zero throughout: no clan, no privileges.
  - id: current_time
    type: u4
    doc: "[ELF] Wire 0x2d. Read as u32, widened and stored as u64 at ctx+29352. PROTOCOL.md: current time, Unix seconds."
  - id: appearance_a
    size: 9
    doc: "[CONFIRMED] (order per PROTOCOL.md) Wire 0x31 -> ctx+30136..30144, nine separate u8 reads. Appearance bytes 0-8 (gender … pitch), same order as 0x3049."
  - id: unknown_3a
    type: u4
    doc: |
      [UNKNOWN meaning; PROVED inert] Wire 0x3a -> ctx+30148 = **profile+7660** = appearance
      struct +12. Written only by 0x4122 (`0xD3D358`) and 0x4103 (`0xD3EEB8`); **read by nothing**.
      Eliminations actually run: no instruction uses displacement 7660-7663 off any
      profile-provenanced base (the one hit, `0x412D88`, is a 16-byte-record table init whose
      sibling does `lfs`/`stfs` — a float struct, rejected on provenance); the appearance struct is
      reached as a pointer via `addi rX,rY,7648` at `0x8DF554`, `0x929280`, `0x93DF9C`, `0x93E9C8`,
      `0x9CB4E8`, `0x9D0F28`, `0x9D102C`, of which four are 200-byte memcpys and two feed
      `0xD3BB28`, the **0x4130 request builder**, which serialises +2..+6, +16..+29, +30..+34,
      +35..+39, +60 and +68..+195 and **omits +12**; 0x4131's parser (`0xD3C3DC`) likewise skips
      the +12 slot; and the character-edit screen's copy at `r29+26660` has **no instruction
      anywhere using displacement 26672**. The confirming observation would have been a load at
      profile+7660 or at +12 of any provable copy. None exists. Send 0 (we do).
  - id: appearance_b
    size: 14
    doc: "[CONFIRMED] (order per PROTOCOL.md) Wire 0x3e -> ctx+30152..30165, fourteen separate u8 reads. Appearance head … accessory-2 colour."
  - id: skills
    type: u1
    repeat: expr
    repeat-expr: 5
    doc: "[ELF] Wire 0x4c -> ctx+30166 + i. **Five** equipped-skill ids; see the correction in the top-level doc. We fill 4 and leave the fifth zero."
  - id: skill_levels
    type: u1
    repeat: expr
    repeat-expr: 5
    doc: "[ELF] Wire 0x51 -> ctx+30171 + i. Five levels, paired with `skills`."
  - id: skill_experience
    type: u4
    repeat: expr
    repeat-expr: 5
    doc: |
      [ELF] Wire 0x56 -> ctx+30176 + i*4. **Five** u32s, 20 bytes, not four. PROTOCOL.md: fixed
      `0x600000` each — skill progression does not exist.
  - id: unknown_6a
    type: u1
    doc: |
      [UNKNOWN meaning; PROVED round-tripped] Wire 0x6a -> ctx+30196 = **profile+7708** =
      appearance struct +60. Unlike the +12 slot this one is on the wire in both directions: the
      **0x4130 request builder reads it** (`0xD3BD88 addi r4,r31,60` -> `bl 0xd5c8a0`, r31's
      provenance `0x9CB4D8 bl 0xd3a094; 0x9CB4E8 addi r4,r3,7648`) and **0x4131's reply parser
      reads it back** (`0xD3C6AC addi r4,r1,176`, `0xD3C6C0` u8 reader) before memcpying the struct
      over profile+7648. In the 0x4130 request it sits between the skill levels (+35..+39) and the
      128-byte comment (+68); the skill-experience array is not sent, so the client's notion of
      "the loadout I own" includes this byte. No other reader: nothing uses displacement 7708 off a
      profile-provenanced base, and nothing uses 26720 (the edit-screen copy's +60), so no UI reads
      or writes it — the client is a pure conduit. Send 0 (we do), but note the consequence: our
      0x4130 handler must preserve whatever we sent, or it is lost on the first appearance change.
  - id: chara_id
    type: u4
    doc: "[ELF] Wire 0x6b -> ctx+30200. PROTOCOL.md: \"the original sends the character id here; its purpose is not documented\"."
  - id: comment
    size: 128
    type: str
    encoding: ISO-8859-1
    doc: "[CONFIRMED] Wire 0x6f -> ctx+30204, fixed 128. The player's profile comment."
  - id: rank
    type: u1
    doc: "[ELF] Wire 0xef -> ctx+30333. Also rewritten by 0x4129 (its wire +4 u8), which is consistent with a post-game rank update."
  - id: emblem_flag
    type: u1
    doc: "[ELF] Wire 0xf0 -> ctx+29360. PROTOCOL.md: 3 when the clan has an emblem; always 0 here. Also rewritten by 0x4129."
  - id: saved_instructor
    type: u4
    doc: |
      [CONFIRMED 2026-07-26] Wire 0xf1. The character's **saved instructor** marker; 0 = none.
      Read at `0xD3D624` (`addi r4,r25,13048` -> the u32 reader `0xD5CCD8`) into `profile+0x32F8`,
      **unguarded** — unlike the `0x43c9` path (`0xD3FF6C`), which stores only a nonzero value, this
      one stores whatever we send, every time. From there: join-announcement packer `0x8842AC` ->
      P2P message 36 -> `G+0x1C0` (sole writer `0x9D17C8`, sole reader `0x9CD5D0`) -> gate
      `0xA359A4`, where nonzero suppresses the "Save current instructor, %s, as the instructor for
      your personal data?" prompt (stage `n002a` string resource 3099; the rating prompt we do get
      is 3105).

      PROTOCOL.md long reproduced this as a fixed suffix `00 A7 00 0D` = 0x00A7000D copied from
      another server. That is not a constant — it was one captured character's saved instructor,
      and echoing it made every character on this server announce "I already have an instructor",
      which suppressed the prompt for everyone.

      **Now populated (2026-07-27).** Zero when the character has no saved instructor; otherwise the
      instructor's **character id**, from `chara_instructor`. A character who answered yes to the
      recognition prompt (`0x43c8` answer byte `0x01`) therefore keeps their instructor across a
      login, which is what "Instructor name cannot be erased once saved" requires — the client's own
      copy at `profile+0x32F8` is RAM only and is never sent back to us.

      **[CONFIRMED 2026-07-27] The value is the instructor's character id, in our id namespace.**
      Live in a team deathmatch: a student carrying saved instructor id 1 saw the instructor badge
      drawn next to that player's name and nobody else's, so the receiving client resolves the
      announced id against the players present. Route: stored verbatim at `profile+0x32F8`, copied
      into the join announcement at `0x8842AC`, broadcast as P2P message 36 — which is why the badge
      shows in ordinary matches and not only in training lobbies.

      This retires the last open question on the field, and explains the captured `0x00A7000D`: it
      was a retail character id belonging to whoever's session that fixture came from — which is
      also why echoing it as a constant made every character claim an instructor.
