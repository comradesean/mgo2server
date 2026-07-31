meta:
  id: mgo2_cmd_4103_s2c
  title: "MGO2 0x4103 — personal-stats character info (reply 1/4 of the 0x4102 burst)"
  endian: be
  encoding: ISO-8859-1
doc: |
  First reply to 0x4102 {u32 chara_id}. Fixed 648-byte (0x288) grid on success; a 4-byte
  error form (nonzero status, no body) makes the client error-complete wait slot 0x16 and
  skip the body (parser 0xd3e9ac, branch 0xd3ea38).

  Layout READ from the client parser (full trace 2026-07-23, loop trip counts from
  disassembly, total emulator-verified). Field LABELS are marked per-field:
  [CONFIRMED] = live capture-proven via the fingerprint sessions (OBSERVED.md),
  [INFERRED]  = offset-mirror of the 0x4101 record or structural reasoning,
  [UNKNOWN]   = position exact, meaning unestablished; fingerprint value & outcome noted.
  "T+0x..." is the client-side struct destination (T = *(obj+0x11904)).

  2026-07-27: the block at the head of the tail — T+0x1AA0 / T+0x1AA4 / T+0x1AB5, previously
  three separate unknowns carrying fingerprint values — is the **clan record**, the same
  `{u32 id, char name[16], u8 state}` triple this protocol uses for a clan in the session record
  at +0x1AA0, in `0x4122`'s block, in `0x4b47`, in `0x4b21`'s head and in `0x4221` at wire 0xa7.
  It is followed by the twelve u16s of the clan privilege/notification word. See those fields for
  why the earlier "NOT the clan field" elimination did not hold.
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats"
seq:
  - id: status
    type: u4
    doc: "0 = success. Nonzero: packet is 4 bytes total, client error-completes. [CONFIRMED]"
  - id: body
    type: stats_info_body
    if: status == 0
types:
  stats_info_body:
    seq:
      - id: chara_id
        type: u4
        doc: "[CONFIRMED]"
      - id: name
        type: str
        size: 16
        doc: "NUL-padded character name. [CONFIRMED]"
      - id: const_block
        type: u2
        repeat: expr
        repeat-expr: 4
        doc: |
          Always 0x16AE, 0x0338, 0x013E, 0x0150 — same constants as 0x4101 offset 0x14,
          reproduced byte-for-byte from the original server. Meaning [UNKNOWN].
      - id: experience
        type: u4
        doc: |
          [INFERRED] from the 0x4101 offset mirror — the raw number never renders on this
          screen. The header showed "Level 22" while this carried 1234; the level is
          presumably client-derived from experience, but that mapping is unverified.
      - id: login_previous
        type: u4
        doc: "Unix seconds. [INFERRED] from the 0x4101 mirror; never seen rendered on this screen."
      - id: login_current
        type: u4
        doc: "Unix seconds. [INFERRED], as login_previous."
      - id: unk_flag
        type: u1
        doc: "T+0x3328. [UNKNOWN]"
      - id: friend_ids
        type: u4
        repeat: expr
        repeat-expr: 32
        doc: |
          T+0x20..0x9C. Flat id array [CONFIRMED structurally] (32-trip parser loop; v4
          fingerprint 8001-8032 changed nothing on the stats screen — not stats).
      - id: blocked_ids
        type: u4
        repeat: expr
        repeat-expr: 32
        doc: "T+0xA0..0x11C. As friend_ids (v4 fingerprint 8501-8532). [CONFIRMED structurally]"
      # ---- tail: flat packed field sequence, wire offsets 301..647 ----
      - id: unk_u8_a
        type: u1
        doc: "wire 301, T+0x3329. [UNKNOWN] (fp v5: 42, never surfaced)"
      - id: clan_id
        type: u4
        doc: |
          wire 302, T+0x1AA0. **The clan id**, first member of the `{u32 id, char name[16],
          u8 state}` clan record. [CONFIRMED 2026-07-27.] It is the gate: readers check the id
          first and treat 0 as "no clan" whatever the name says. (fp 4001 — see the elimination
          note on `clan_name`.)
      - id: clan_name
        type: str
        size: 16
        doc: |
          wire 306, T+0x1AA4. **The clan name**, second member of the clan record.
          [CONFIRMED 2026-07-27.]

          CORRECTS A FALSE ELIMINATION. This field previously read: `[UNKNOWN] (fp "FP-STR-A",
          never surfaced; NOT the clan field — clan stayed blank)`. The observation was real and
          the conclusion was invalid. The fingerprint pass put a string here with **fp 4001 — a
          made-up number, not a real clan — in `clan_id` before it**, and a zero-or-nonsense id
          means the client renders no clan no matter what the name holds. So "clan stayed blank"
          was the expected outcome under BOTH hypotheses and could not distinguish them.

          Per CLAUDE.md: an elimination is only valid if you can state the observation that would
          have confirmed it and check the experiment actually produced that observation. This one
          could not have. Nothing had ever put a real clan — a non-zero id with a matching name
          and state — into these three fields until 2026-07-27, and when something did, the clan
          rendered. Same triple, same failure mode, as `0x4221` wire 0xa7/0xab/0xbb.
      - id: clan_state
        type: u1
        doc: |
          wire 322, T+0x1AB5. **Clan membership state**, third member of the clan record.
          [CONFIRMED 2026-07-27.] Constants the client writes for itself: 0 affiliation pending
          (0xD58740), 1 member (0xD56B68), 2 leader (0xD56B84), 99 not in a clan (0xD56B44 /
          0xD56C7C / 0xD56D68). Readers test membership as `state - 1 <= 1`. (fp 43.)
      - id: clan_privilege_block
        type: u2
        repeat: expr
        repeat-expr: 12
        doc: |
          wire 323, T+0x1AB6..0x1ACC. **The clan privilege/notification word and its eleven unread
          siblings.** [CONFIRMED 2026-07-27] for element 0; elements 1-11 [UNKNOWN] and have no
          reader anywhere in the binary. Previously logged as an undifferentiated unknown block
          (fp 5101-5112, "never surfaced") — for the same reason as `clan_name` above: with no
          real clan in the record before it, there was nothing for a privilege word to apply to.

          **Element 0 must be sent as ZERO.** Two experiments, both live 2026-07-27:
            * All 16 bits set produced a saluting-soldier "!" badge and a hard poll loop at
              roughly 73 ms — the clan screen coroutine at `0xAB0074` ands the word with `-1`, or
              with `-257` when the player is the leader (`0xAB004C`), and returns without
              advancing its state machine if anything survives, so the screen re-entered and
              re-sent its request forever.
            * Bit 8 alone (`-257` = `~0x0100`, the one bit a leader may hold without stalling)
              did not stall, but produced only the "!" badge and no new menu row anywhere; emblem
              loading worked with and without it. So bit 8 is a **pending-notification** bit and
              gates nothing.

          The whole word is therefore a notification mask the client drains to zero, not a
          permission mask. No privilege bit gates applying an emblem: the commit gate at
          `0xAD409C` reads membership state 2 (`clan_state` above) and nothing else.
      - id: unk_u32_b
        type: u4
        doc: "wire 347, T+0x1AD0. [UNKNOWN] (fp 4002)"
      - id: unk_u8_block_a
        type: u1
        repeat: expr
        repeat-expr: 9
        doc: "wire 351, T+0x1DE0..0x1DE8. [UNKNOWN] (fp 61-69)"
      - id: unk_u32_c
        type: u4
        doc: "wire 360, T+0x1DEC. [UNKNOWN] (fp 4003)"
      - id: unk_u8_block_b
        type: u1
        repeat: expr
        repeat-expr: 14
        doc: "wire 364, T+0x1DF0..0x1DFD. [UNKNOWN] (fp 71-84)"
      - id: unk_u8_block_c
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: "wire 378, T+0x1DFE..0x1E02. [UNKNOWN] (fp 91-95)"
      - id: unk_u8_block_d
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: "wire 383, T+0x1E03..0x1E07. [UNKNOWN] (fp 96-100)"
      - id: unk_u32_block
        type: u4
        repeat: expr
        repeat-expr: 5
        doc: "wire 388, T+0x1E08..0x1E18. [UNKNOWN] (fp 4011-4015)"
      - id: unk_u8_c
        type: u1
        doc: "wire 408, T+0x1E1C. [UNKNOWN] (fp 44)"
      - id: unk_u32_d
        type: u4
        doc: "wire 409, T+0x1E20. [UNKNOWN] (fp 4016)"
      - id: comment
        type: str
        size: 128
        doc: |
          wire 413, T+0x1E24. The 128-byte player comment. [CONFIRMED] — located by the v3
          fingerprint leak ({|}~ from misaligned u16s) and verified end-to-end in v5 with the
          real database comment.
      - id: equipped_title
        type: u1
        doc: |
          [CONFIRMED 2026-07-28] The title the character is wearing, **1-based** — 0 for none.
          Previously `unk_u8_d`, sent as the fingerprint 45, which is out of range for the
          22-title table.
          **This is not the only place the worn title goes.** 0x4103 writes its copy into a SCRATCH
          block (`*(ctx+0x11904)`), which the Personal Stats screen renders from and which is never
          published to peers. The in-game scorecard's animal-rank badge reads a different byte
          entirely — 0x4122 wire 0xef — which lands in the LOCAL character record at
          charBlock+0x1EA5 and is replicated over P2P as record slot+1 key 358.

          So both must carry the same value. Until 2026-07-28 this one was correct and 0x4122 sent
          `chara.rank` (dead, always 0), which is why the badge showed on the stats screen and
          nowhere else. See PROTOCOL.md's 0x4122 section.

      - id: unk_u8_block_e
        type: u1
        repeat: expr
        repeat-expr: 9
        doc: "wire 542, T+0x32B8..0x32C0. [UNKNOWN] (fp 101-109)"
      - id: rating_block
        type: u4
        repeat: expr
        repeat-expr: 9
        doc: |
          wire 551, T+0x32C4..0x32E4. Nine u32s, **three of them identified 2026-07-28**:

          - **entry 3 (wire 563) — the TITLE unlock bitmask, 22 bits, LSB-first.** This is what
            made every character wear eight titles: the fingerprint 4024 set bits 3..11, which is
            exactly the "titles 3-11" OBSERVED recorded and attributed to the stats changing.
            **NEVER set bit 22 or above** — the client's popcount loop runs 23 iterations over a
            22-entry table and reads past the end.
          - **entry 5 (wire 571) — Host Rating star NUMERATOR.**
          - **entry 6 (wire 575) — Host Rating star DENOMINATOR**, the "/ N votes" on screen.

          The gauge is `clamp(ceil(2 * num / den), 0, 10)` half-stars (`0x94258C`), so the rating
          SUM over the vote COUNT renders the average. Both halves are fed from `host_review`,
          filled by `0x43c4` — before that command was identified nothing stored a host vote and
          this gauge could only read zero.

          Entries 0, 1, 2, 4, 7, 8 remain [UNKNOWN]. Entry 4 is read by the stats screen
          (`0x91b338`) but what it renders was never established.
      - id: unk_u32_session
        type: u4
        doc: "wire 587. Stored to obj+0x30, not the character struct. [UNKNOWN] (fp 4030)"
      - id: instructor_name
        type: str
        size: 16
        doc: "wire 591, T+0x32FC. [CONFIRMED] — rendered as \"Instructor:\" (showed FP-STR-B)."
      - id: unk_u32_e
        type: u4
        doc: "wire 607, T+0x3310. [UNKNOWN] (fp 4031; candidate for the v2 'generation' u32)"
      - id: beta_award_bits
        type: u4
        doc: |
          [CONFIRMED 2026-07-28] Award bits outside the main bitfield; **bit 0 is the "Beta test
          participant" award**. Previously `unk_u32_f`. Higher bits unexamined.
      - id: medal_bitfield
        type: str
        size: 16
        doc: |
          [CONFIRMED 2026-07-28] **The medal bitfield — 16 bytes, and the ONLY thing that decides
          which awards the player has.** Not a string; the ksy called it `unk_str_c` and this
          server sent the literal text "FP-STR-C" into it for weeks.

          The gate at `0x916E20` reads a medal row's id, tests the matching bit through
          `0xD5C2A8`, and skips the row when it is clear. **No stat is loaded anywhere in
          `0x916E20`..`0x916FD0`** — which is what proves medals are server-driven. The
          `threshold` word in the 39-row table at `0xE139C0` is loaded *after* the gate and
          sprintf'd into the description as its `%d`, so "500 Mk.II destructions" is display text,
          not a condition the player met.

          Layout is **medal-id-keyed, not row-indexed**: a hand-written switch with a byte and bit
          per id, LSB-first. Bits 3 and 7 of each byte and bytes 13-15 are unused.

          How it was caught: a live character showed "500 Mk.II destructions" against zero Mk.II
          kills, and kept the award after every stat was zeroed. "FP-STR-C" byte 4 is 'T' = 0x54,
          bit 6 set = medal id 65 = that award. The whole string lit 17 medals.
      - id: unk_u8_e
        type: u1
        doc: "wire 631, T+0x1AD8. [UNKNOWN] (fp 46)"
      - id: instructor_score_numerator
        type: u4
        doc: |
          [CONFIRMED 2026-07-28] The **Instructor Score star numerator**, paired with the
          denominator that follows. The client draws
          `clamp(ceil(2 * numerator / denominator), 0, 10)` half-stars (`0x94258C`, 11-entry icon
          table), so sending the rating SUM over the vote COUNT puts the true average on the gauge.
          Previously `unk_u32_g`.
      - id: instructor_score_denominator
        type: u4
        doc: "wire 636, T+0x32F4. [CONFIRMED] (fp 4034 rendered as \"1 star / 4034\"); numerator not located."
      - id: unk_u32_h
        type: u4
        doc: "wire 640, T+0x32F8. [UNKNOWN] (fp 4035)"
      - id: unk_u32_i
        type: u4
        doc: "wire 644, T+0x124. [UNKNOWN] (fp 4036)"
