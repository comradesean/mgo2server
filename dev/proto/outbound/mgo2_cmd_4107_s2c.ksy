meta:
  id: mgo2_cmd_4107_s2c
  title: "MGO2 0x4107 — personal scores (reply 4/4 of the 0x4102 burst, terminal)"
  endian: be
doc: |
  Two 73-slot u32 records with one shared layout: record 1 cumulative, record 2 weekly
  (the stats screen's cumulative/weekly toggle; [CONFIRMED fingerprint v9]). TERMINAL
  packet of the burst — its parser (0xd3db1c) unconditionally completes wait slot 0x16
  (0xd3e4b0), so it must be sent last; without it the client stalls into FFFFFF60.

  ## Where the slots land in memory [ELF 0xd3db1c]

  The parser is a straight-line run of 73 `bl 0xd5ccd8` (read-u32) calls per record into
  `T + 3768 + memIndex*4`, record stride **292** (`addi rN,rN,292` at 0xd3e428-0xd3e494,
  loop bound 2 at 0xd3e430). `T` is `*(session + 0x11904)` (`addis r29,r29,1` +
  `lwz r29,6404(r29)` at 0xd3dba0/0xd3dba4). The whole region is zeroed first —
  `memset(T+3768, 0, 1168)` at 0xd3dbac-0xd3dbbc, i.e. **four** 292-byte records, of which
  the packet writes the first two.

  Wire slot n (1-based) maps to memIndex n−1 for n = 1..63; the tail is permuted
  [0xd3e314 / 0xd3e32c / 0xd3e348]: wire 64 → mem 71, wire 65 → mem 72,
  wire 66..73 → mem 63..70. Everything below quotes the **wire** slot.

  ## Where the slots are read [ELF]

  Exactly two consumers exist image-wide (established by scanning every
  `addi rX,rY,{3768,3856,3872,3888,4000,4016,4032,4056}` in the disassembly — every other
  hit sits on an unrelated base: r1 stack frames, r2/TOC, or objects in 0xe9c/0x11f/0xa5f/
  0xb82 that never touch T):

  - **The DETAIL page** — one big switch at 0x917f34-0x918b80 keyed on a 24-bit resource
    hash pulled from the **36-entry display list at 0xE13BDC** (duplicated verbatim at
    0xE13C6C). 27 of those 36 rows read this packet; the other 9 are 0x4105 grid play-times
    and two 0x4103 star rows.
  - **The per-mode pages** — dispatcher at 0x91722c-0x9174ac; each mode page overlays 0..3
    personal-score slots onto the 0x4105 grid. A second copy of the mode-page renderer lives
    at 0x91a388-0x91a904 and reads the same offsets.

  38 of 73 slots are read. **The other 35 have no reader anywhere in the image** — they are
  not in the display list, not in the mode-page dispatcher, and no other code forms the base.

  ## Naming route [DISC]

  Row labels are disc string resources, group `[1ab3b6]` = `"mgo2_res_myscore"`, set
  `$strres:17779` (headers 17779..17942, strings from 17943; EN is the 2nd of the six
  ordinals). The mode-page labels are addressed **by name** — the ELF holds the literal
  strings `SP_SCORE_TDM01`, `SP_SCORE_BASE01/02`, `SP_SCORE_RES01/02/03`,
  `SP_SCORE_TSNE01/02`, `SP_SCORE_SNE11/16/18` at 0xE13F08-0xE13FA8, hashes them with
  0xd25d0 and resolves against group 0x1AB3B6 (`lis r3,26 / ori r3,r3,46006`). The DETAIL
  rows are addressed by pre-hashed constant, so their names do not appear in the ELF at all;
  they were recovered by matching the constant against the disc header records.

  The six mode-page labels the fingerprint had already established (Consecutive Survivals,
  Bases Conquered, SOP Destabilizer Uses, GA-KO Saved, GA-KO Defended, Fully Defended
  Matches) all came back byte-identical through this route, and so did the three Snake ones,
  which is what licenses trusting it for the two it newly resolved.

  Mode-page placement of some slots (e.g. Bases Conquered on the Base page) is pure UI —
  every slot is a single global value. Several slots feed client-side medal thresholds
  (dev/docs/OBSERVED.md, "Titles and medals").
doc-ref: dev/docs/PROTOCOL.md "0x4102 — get personal stats"
seq:
  - id: status
    type: u4
    doc: "Observed 0."
  - id: cumulative
    type: personal_scores
    doc: "Record 1 — lifetime. Lands at T+3768."
  - id: weekly
    type: personal_scores
    doc: "Record 2 — weekly period; reset cadence is server/operator policy. Lands at T+4060 (record stride 292)."
types:
  personal_scores:
    doc: |
      73 u32 slots, named by 1-based wire slot. `unknown_NN` = position exact, meaning
      unestablished: no ELF reader, and the v5/v9 fingerprint value (1000+NN / 2000+NN)
      surfaced on no screen.

      The 35 unread slots share one negative, stated once here rather than 35 times: the slot
      is absent from the DETAIL display list at 0xE13BDC (all 36 entries are accounted for
      below), absent from the mode-page dispatcher at 0x91722c, and no third consumer forms
      a base into T+3768..T+4936. What would settle any of them is a *new* reader appearing —
      i.e. they are either dead storage, or fields a later client version reads.

      Candidate labels with no code behind them [DISC, group 1ab3b6]: the same string set
      carries 18 stat labels that no ELF path renders — "Kills from Lying on Your Back"
      (0x39b445), "Kills Using Leaning Shots" (0x39b45c), "Kills from Above When Hanging Over
      a Ledge" (0xd17d08), "Powered Suit Uses" (0x39b45d), "Drebin Points Earned" (0x39b45e),
      "Drebin Points Spent" (0x39b45f), "PPK Hits" (0x39b461), "Hold Ups Performed as Snake"
      (0xb4ed28), "Mk.II's Destroyed" (0xb4ed2a), "Times You Spotted Snake" (0xb4ed2b),
      "Times You Were Spotted as Snake" (0xb4ed2c), "Times You Were the First to Spot Snake"
      (0xb4ed2d), "Knock-outs Performed as Mk.II" (0xb4ed2f), "Missions Completed" (0xb4ed09),
      "Consecutive Opponents Spotted" (0xb4ed0a), "Consecutive Missions Completed" (0xb4ed0b).
      **None of those 16 hashes occurs anywhere in the ELF** (searched as big-endian u32 over
      the whole image), so they cannot be tied to a slot from this side. Do NOT assign them
      to unknown slots by plausibility — that is exactly the inference this project bans.
    seq:
      - id: consecutive_kills
        type: u4
        doc: |
          slot 1 → mem 0. [CONFIRMED] DETAIL row hash 0x39b41d, case 0x9181c0 (`lwz r3,0(r9)`
          off base T+3768); disc label "Consecutive Kills". Medal source: 5/10/25.
      - id: consecutive_deaths
        type: u4
        doc: 'slot 2 → mem 1. [CONFIRMED] hash 0x39b41e, case 0x9181cc (+4); label "Consecutive Deaths".'
      - id: unknown_03
        type: u4
        doc: |
          slot 3 → mem 2. [UNKNOWN] No reader: mem 2 is the one gap in the otherwise
          contiguous run mem 0..22 that the DETAIL page consumes, and nothing else reads it.
          The old candidate note "consecutive headshots" rested on the 0x4390 struct-B
          index = slot−1 rule (B2 = consecutive headshots), which is cross-packet inference,
          not evidence about this field — recorded, not adopted. Settling it needs either a
          reader to appear or a live round that moves B2 and then re-reads this slot.
      - id: suicides
        type: u4
        doc: 'slot 4 → mem 3. [CONFIRMED] hash 0x39b41f, case 0x9181d8 (+12); label "Suicides".'
      - id: times_stunned
        type: u4
        doc: 'slot 5 → mem 4. [CONFIRMED] hash 0x39b422, case 0x9181fc (+16); label "Times Stunned".'
      - id: friendly_kills
        type: u4
        doc: 'slot 6 → mem 5. [CONFIRMED] hash 0x39b420, case 0x9181e4 (+20); label "Friendly Kills".'
      - id: friendly_stuns
        type: u4
        doc: 'slot 7 → mem 6. [CONFIRMED] hash 0x39b421, case 0x9181f0 (+24); label "Friendly Stuns".'
      - id: salutes
        type: u4
        doc: 'slot 8 → mem 7. [CONFIRMED] hash 0x39b440, case 0x91825c (+28); label "Salutes".'
      - id: radio_message_uses
        type: u4
        doc: 'slot 9 → mem 8. [CONFIRMED] hash 0x39b423, case 0x918208 (+32); label "Preset Radio Message Uses".'
      - id: text_chat_uses
        type: u4
        doc: |
          slot 10 → mem 9. [CONFIRMED] hash 0x39b424, case 0x918214 (+36).
          Label is "Text Chat Uses" — the earlier "Text Chase Uses — sic" note was a
          transcription error off the screen, corrected here against the disc string
          (group 1ab3b6, header 17873).
      - id: cqc_attacks_given
        type: u4
        doc: 'slot 11 → mem 10. [CONFIRMED] hash 0x39b425, case 0x918220 (+40); label "CQC Attacks Given".'
      - id: cqc_attacks_taken
        type: u4
        doc: 'slot 12 → mem 11. [CONFIRMED] hash 0x39b43c, case 0x91822c (+44); label "CQC Attacks Taken".'
      - id: rolls
        type: u4
        doc: 'slot 13 → mem 12. [CONFIRMED] hash 0x39b43d, case 0x918238 (+48); label "Rolls".'
      - id: envg_seconds
        type: u4
        doc: |
          slot 14 → mem 13. [CONFIRMED] hash 0x39b480, case 0x9182f8 (+52); label
          "Total Time Using ENVG". Seconds — the hash is in the time-formatted pre-check at
          0x917f60, so the value goes through the hh:mm:ss split at 0x9183a0.
      - id: dedicated_host_seconds
        type: u4
        doc: |
          slot 15 → mem 14. [CONFIRMED] hash 0x39b43f, case 0x918250 (+56); label
          "Time as Dedicated Host". Seconds (time pre-check at 0x917f54).
      - id: catapult_uses
        type: u4
        doc: 'slot 16 → mem 15. [CONFIRMED] hash 0x39b441, case 0x918268 (+60); label "Catapult Uses".'
      - id: boosts_given
        type: u4
        doc: 'slot 17 → mem 16. [CONFIRMED] hash 0x39b442, case 0x918274 (+64); label "Number of Boosts Given".'
      - id: falling_deaths
        type: u4
        doc: 'slot 18 → mem 17. [CONFIRMED] hash 0x39b443, case 0x918280 (+68); label "Falling Deaths".'
      - id: trap_catches
        type: u4
        doc: 'slot 19 → mem 18. [CONFIRMED] hash 0x39b444, case 0x91828c (+72); label "Times Caught in Trap".'
      - id: scans_performed
        type: u4
        doc: 'slot 20 → mem 19. [CONFIRMED] hash 0x39b463, case 0x9182b0 (+76); label "Scans Performed".'
      - id: cardboard_box_seconds
        type: u4
        doc: |
          slot 21 → mem 20. [CONFIRMED] hash 0x39b43e, case 0x918244 (+80); label
          "Time in Cardboard Box". Seconds (time pre-check at 0x917f48).
      - id: cardboard_box_uses
        type: u4
        doc: 'slot 22 → mem 21. [CONFIRMED] hash 0x39b462, case 0x9182a4 (+84); label "Cardboard Box Uses".'
      - id: melee_hits
        type: u4
        doc: |
          slot 23 → mem 22. [CONFIRMED] case 0x918298 (+88). The only DETAIL row whose hash
          is not in the 0x39b4xx run — 0x00d19108, tested at 0x9181ac
          (`xoris r0,r10,65326 / cmpwi -28408`); label "Melee Hits".
      - id: unknown_24
        type: u4
        doc: |
          slot 24 → mem 23. [UNKNOWN] No reader. It sits between "Melee Hits" (mem 22, the
          last DETAIL row of the contiguous run) and "Consecutive Survivals" (mem 24, the TDM
          page's only extra), so both consumers step straight over it.
      - id: consecutive_survivals_tdm
        type: u4
        doc: |
          slot 25 → mem 24. [CONFIRMED] Team Deathmatch page only. Dispatcher arm
          `byte[11]` at 0x917248; label string `SP_SCORE_TDM01` (0xE13F08, loaded at
          0x917258); read at 0x9172c0 (`lwz r0,8(r11)` off `period*292 + 3856`).
          Disc label "Consecutive Survivals". Medal source: 2/4/6.
      - id: bases_conquered
        type: u4
        doc: |
          slot 26 → mem 25. [CONFIRMED] Base page. Dispatcher arm `byte[13]` at 0x917368;
          label `SP_SCORE_BASE01` (0xE13F18, loaded 0x917374); read at 0x917404
          (`lwz r0,12(r11)` off +3856). Disc label "Bases Conquered".
      - id: sop_destabilizer_uses
        type: u4
        doc: |
          slot 27 → mem 26. [CONFIRMED] Base page. Label `SP_SCORE_BASE02` (0xE13F28, loaded
          0x9173a8); read at 0x91740c (+16 off +3856). Disc label "SOP Destabilizer Uses".
          Medal source: ~50/100/200.
      - id: gako_saved
        type: u4
        doc: |
          slot 28 → mem 27. [CONFIRMED] Rescue page. Dispatcher arm `byte[14]` at 0x9174a4;
          label `SP_SCORE_RES01` (0xE13F38, loaded 0x9174b4); read at 0x917570 (+20 off
          +3856). Disc label "GA-KO Saved".
      - id: gako_defended
        type: u4
        doc: |
          slot 29 → mem 28. [CONFIRMED] Rescue page. Label `SP_SCORE_RES02` (0xE13F48, loaded
          0x9174e4); read at 0x917578 (`lwz r0,8(r10)` off +3872). Disc label "GA-KO Defended".
      - id: unknown_30
        type: u4
        doc: |
          slot 30 → mem 29. [UNKNOWN] **Provably skipped by the only code that could read it.**
          The Rescue arm reads mem 27, 28 and 30 (offsets 3876, 3880, 3888) at 0x917570 /
          0x917578 / 0x917580 and steps over 3884. So this is not "a Rescue stat we have not
          identified" — the Rescue page has exactly three extras and this is not one of them.
      - id: fully_defended_matches
        type: u4
        doc: |
          slot 31 → mem 30. [CONFIRMED] Rescue page. Label `SP_SCORE_RES03` (0xE13F58, loaded
          0x917508); read at 0x917580 (`lwz r0,16(r10)` off +3872). Disc label
          "Fully Defended Matches".
      - id: unknown_32
        type: u4
        doc: |
          slot 32 → mem 31. [UNKNOWN] No reader. Sits immediately before the Team Sneaking
          pair (mem 32/33), which the dispatcher reaches at +3888 rather than +3884.
      - id: opponents_spotted
        type: u4
        doc: |
          slot 33 → mem 32. [CONFIRMED 2026-07-30, ELF+DISC] **Team Sneaking page.**
          Dispatcher arm `byte[16]` at 0x917618 — the seventh and last mode page. Label
          string `SP_SCORE_TSNE01` at 0xE13F68, loaded at 0x917624 (`lwz r3,-32676(r30)`,
          r30 = *(TOC−28608) = 0xff04e8), hashed by 0xd25d0 and resolved in group 0x1AB3B6 at
          0x91764c. Read at 0x9176b4: `lwz r0,8(r11)` where r11 = T + period*292 + 3888.
          Disc string (group 1ab3b6, name hash 0xf27549, header 17861) EN = **"Opponents
          Spotted"** — the Team Sneaking spotting mechanic, counted from the spotter's side.

          Team Sneaking is rule 7, switched on 2008-07-04, so this row is unreachable on a
          release-day server. Serve 0. See dev/docs/POST_LAUNCH.md.
      - id: self_spotted
        type: u4
        doc: |
          slot 34 → mem 33. [CONFIRMED 2026-07-30, ELF+DISC] Team Sneaking page, second
          extra. Label `SP_SCORE_TSNE02` at 0xE13F78, loaded 0x917658; read at 0x9176bc
          (`lwz r0,12(r11)` off +3888). Disc string (name hash 0xf2754a, header 17862)
          EN = **"Self Spotted"** — the same mechanic from the spotted player's side.
          Post-launch content; serve 0.
      - id: unknown_35
        type: u4
        doc: |
          slot 35 → mem 34. [UNKNOWN] No reader. The Team Sneaking arm reads mem 32 and 33
          only and stops; nothing else forms +3892.
      - id: soldiers_trained
        type: u4
        doc: |
          slot 36 → mem 35. [CONFIRMED] DETAIL row hash 0x39b47d, case 0x9182e0 (+140);
          disc label "Number of Soldiers Trained". Medal source: 10/100/300.
      - id: unknown_37
        type: u4
        doc: "slot 37 → mem 36. [UNKNOWN] No reader (see the type doc for the shared negative)."
      - id: unknown_38
        type: u4
        doc: "slot 38 → mem 37. [UNKNOWN] No reader."
      - id: unknown_39
        type: u4
        doc: "slot 39 → mem 38. [UNKNOWN] No reader."
      - id: unknown_40
        type: u4
        doc: "slot 40 → mem 39. [UNKNOWN] No reader."
      - id: unknown_41
        type: u4
        doc: "slot 41 → mem 40. [UNKNOWN] No reader."
      - id: unknown_42
        type: u4
        doc: "slot 42 → mem 41. [UNKNOWN] No reader."
      - id: unknown_43
        type: u4
        doc: "slot 43 → mem 42. [UNKNOWN] No reader."
      - id: unknown_44
        type: u4
        doc: "slot 44 → mem 43. [UNKNOWN] No reader."
      - id: unknown_45
        type: u4
        doc: |
          slot 45 → mem 44. [UNKNOWN] No reader. Note it is *adjacent* to the three training
          time fields (mem 45/46/47) but is not part of that group: the DETAIL page reads
          +180/+184/+188 and never +176.
      - id: training_seconds
        type: u4
        doc: |
          slot 46 → mem 45. [CONFIRMED] hash 0x39b464, case 0x9182bc (+180); disc label
          "Training Mode Time". Seconds — the hash is caught by the `cmplwi 1` time pre-check
          at 0x917f38-0x917f44 (`r10 − 0x39b464 ≤ 1`, i.e. this slot and the next one).
      - id: instructor_seconds
        type: u4
        doc: |
          slot 47 → mem 46. [CONFIRMED] hash 0x39b465, case 0x9182c8 (+184); disc label
          "Combat Training Time (Instructor)". Seconds (same pre-check).
      - id: student_seconds
        type: u4
        doc: |
          slot 48 → mem 47. [CONFIRMED] hash 0x39b47c, case 0x9182d4 (+188); disc label
          "Combat Training Time (Student)". Seconds (time pre-check at 0x917fc0).
      - id: unknown_49
        type: u4
        doc: |
          slot 49 → mem 48. [UNKNOWN] No reader. First of the longest dark run in the record
          (mem 48..61, wire 49..62): nothing between the training times and the Snake block
          is touched by any code path.
      - id: unknown_50
        type: u4
        doc: "slot 50 → mem 49. [UNKNOWN] No reader."
      - id: unknown_51
        type: u4
        doc: "slot 51 → mem 50. [UNKNOWN] No reader."
      - id: unknown_52
        type: u4
        doc: "slot 52 → mem 51. [UNKNOWN] No reader."
      - id: unknown_53
        type: u4
        doc: "slot 53 → mem 52. [UNKNOWN] No reader."
      - id: unknown_54
        type: u4
        doc: "slot 54 → mem 53. [UNKNOWN] No reader."
      - id: unknown_55
        type: u4
        doc: "slot 55 → mem 54. [UNKNOWN] No reader."
      - id: unknown_56
        type: u4
        doc: "slot 56 → mem 55. [UNKNOWN] No reader."
      - id: unknown_57
        type: u4
        doc: "slot 57 → mem 56. [UNKNOWN] No reader."
      - id: unknown_58
        type: u4
        doc: "slot 58 → mem 57. [UNKNOWN] No reader."
      - id: unknown_59
        type: u4
        doc: "slot 59 → mem 58. [UNKNOWN] No reader."
      - id: unknown_60
        type: u4
        doc: "slot 60 → mem 59. [UNKNOWN] No reader."
      - id: unknown_61
        type: u4
        doc: "slot 61 → mem 60. [UNKNOWN] No reader."
      - id: unknown_62
        type: u4
        doc: "slot 62 → mem 61. [UNKNOWN] No reader."
      - id: snake_victories
        type: u4
        doc: |
          slot 63 → mem 62. [CONFIRMED] Sneaking page. Dispatcher arm `byte[15]` at 0x917758;
          label `SP_SCORE_SNE18` (0xE13F98, loaded 0x917798); read at 0x917838
          (`lwz r0,16(r10)` where r10 = T + period*292 + 4000). Disc label
          "Victories as Snake".
      - id: knife_kills
        type: u4
        doc: |
          slot 64 → **mem 71** (the tail permutation; parsed at 0xd3e314 into `r31+20` =
          +4052). [CONFIRMED] DETAIL row hash 0x39b47f, case 0x9182ec — `lwz r3,284(r9)`,
          and 284/4 = 71, which is what independently proves the permutation. Disc label
          "Knife Kills". Source is the 0x43a2 per-weapon tally, not struct B (struct B has
          only 58 slots).
      - id: unknown_65
        type: u4
        doc: |
          slot 65 → mem 72. [UNKNOWN] No reader. Parsed at 0xd3e32c into the isolated
          `T+4056` register (140/144(r1) spill), the last dword of the 73-slot record.
      - id: unknown_66
        type: u4
        doc: "slot 66 → mem 63. [UNKNOWN] No reader. First slot of the permuted 66..73 → 63..70 run."
      - id: snake_kills
        type: u4
        doc: |
          slot 67 → mem 64. [CONFIRMED] Sneaking page. Label `SP_SCORE_SNE11` (0xE13FA8,
          loaded 0x9177bc); read at 0x917840 (`lwz r0,8(r8)` where r8 = T + period*292 +
          4016; 4016+8 = 4024 = mem 64). Disc label "Snake Kills".
      - id: unknown_68
        type: u4
        doc: "slot 68 → mem 65. [UNKNOWN] No reader."
      - id: unknown_69
        type: u4
        doc: "slot 69 → mem 66. [UNKNOWN] No reader."
      - id: unknown_70
        type: u4
        doc: "slot 70 → mem 67. [UNKNOWN] No reader."
      - id: unknown_71
        type: u4
        doc: "slot 71 → mem 68. [UNKNOWN] No reader."
      - id: snake_seconds
        type: u4
        doc: |
          slot 72 → mem 69. [CONFIRMED] Sneaking page. Label `SP_SCORE_SNE16` (0xE13F88,
          loaded 0x917768); read at 0x91782c (`lwz r0,12(r11)` where r11 = T + period*292 +
          4032; 4032+12 = 4044 = mem 69). Disc label "Total Time Playing as Snake" — seconds.
      - id: unknown_73
        type: u4
        doc: "slot 73 → mem 70. [UNKNOWN] No reader."
