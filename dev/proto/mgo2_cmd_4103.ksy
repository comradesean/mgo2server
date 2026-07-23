meta:
  id: mgo2_cmd_4103
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
      - id: unk_u32_a
        type: u4
        doc: "wire 302, T+0x1AA0. [UNKNOWN] (fp 4001, never surfaced)"
      - id: unk_str_a
        type: str
        size: 16
        doc: "wire 306, T+0x1AA4. String field. [UNKNOWN] (fp \"FP-STR-A\", never surfaced; NOT the clan field — clan stayed blank)"
      - id: unk_u8_b
        type: u1
        doc: "wire 322, T+0x1AB5. [UNKNOWN] (fp 43)"
      - id: unk_u16_block
        type: u2
        repeat: expr
        repeat-expr: 12
        doc: "wire 323, T+0x1AB6..0x1ACC. [UNKNOWN] (fp 5101-5112, never surfaced)"
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
      - id: unk_u8_d
        type: u1
        doc: "wire 541, T+0x1EA5. [UNKNOWN] (fp 45)"
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
          wire 551, T+0x32C4..0x32E4. Entry 7 (T+0x32DC) [CONFIRMED] = Host Rating
          denominator (fp 4027 rendered as "1 star / 4027"). Entry 4 (T+0x32D0) is read by
          the stats screen (trace 0x91b338) but what it renders is [UNKNOWN] (fp 4024 never
          visibly surfaced). Other entries [UNKNOWN] (fp 4021-4029); the star-count
          numerators are NOT located yet.
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
      - id: unk_u32_f
        type: u4
        doc: "wire 611, T+0x3314. [UNKNOWN] (fp 4032)"
      - id: unk_str_c
        type: str
        size: 16
        doc: "wire 615, T+0x3318. String field. [UNKNOWN] (fp \"FP-STR-C\", never surfaced)"
      - id: unk_u8_e
        type: u1
        doc: "wire 631, T+0x1AD8. [UNKNOWN] (fp 46)"
      - id: unk_u32_g
        type: u4
        doc: "wire 632, T+0x32F0. [UNKNOWN] (fp 4033)"
      - id: instructor_score_denominator
        type: u4
        doc: "wire 636, T+0x32F4. [CONFIRMED] (fp 4034 rendered as \"1 star / 4034\"); numerator not located."
      - id: unk_u32_h
        type: u4
        doc: "wire 640, T+0x32F8. [UNKNOWN] (fp 4035)"
      - id: unk_u32_i
        type: u4
        doc: "wire 644, T+0x124. [UNKNOWN] (fp 4036)"
