meta:
  id: mgo2_cmd_4390
  title: "MGO2 0x4390 — host's end-of-round stat report (client -> server)"
  endian: be
doc: |
  The host's per-player round report, one packet per player, sent at round end and on kick
  teardown. The first client->server frame specced here: this is what the server STORES
  (round_report table, one row per report) and every stats/history surface derives from it.
  Long form 167 B; a short ~51 B form omits struct B (detail_present 0) and moves the
  trailing word up. Nomad-era builds had a longer form with an aborted byte at 0xB7 — this
  client's 167 B frame never reaches it.

  Labels: capture 2026-07-22 (kills/deaths/score/headshots/stuns vs rendered scoreboard) plus
  the single-variable round experiments 2026-07-23 (OBSERVED.md, "The OTHER-field
  experiment"). [MATCHED n/n] = exact correlation in every observed round, deliberately NOT
  called a duplicate — divergence tests pending. Score formula (client-side, revised
  2026-07-23): kills*3 - deaths*2 + headshots*2 + stun*3 + kill1st*5 + combo*1, clamped at 0.
doc-ref: dev/docs/PROTOCOL.md "0x4390 — update stats"
seq:
  - id: chara_id
    type: u4
    doc: "[CONFIRMED] target character id."
  - id: flag_0x04
    type: u1
    doc: "[INFERRED] flag byte (aborted/result?). 0 in every 2026-07-23 report incl. a suicide round."
  - id: kills
    type: s2
    doc: "[CONFIRMED] kills. Suicides do NOT count."
  - id: deaths
    type: s2
    doc: "[CONFIRMED] deaths, suicides included."
  - id: lockon_kills
    type: s2
    doc: "[CONFIRMED] lock-on kills — single-variable round: 3 in a 3-lock-on round, 0 in five kill rounds without. The personal-stats grid's OTHER operand."
  - id: score
    type: s2
    doc: "[CONFIRMED] round score, clamped at 0 (negative never observed despite categories implying it twice)."
  - id: stuns
    type: s2
    doc: "[CONFIRMED] stun/knockout count — requires an actual faint; non-fainting slams tick B22/B23 instead. Scores *3 (revised from *2)."
  - id: unknown_0x0f
    type: s2
    doc: "[UNKNOWN] loser-side 1 observed twice; 1 once in the 2026-07-22 capture."
  - id: headshots
    type: s2
    doc: "[CONFIRMED] headshots dealt, bullets only (knife head-stabs do not count)."
  - id: headshot_deaths
    type: s2
    doc: "[CONFIRMED-1v1] deaths to headshots (received mirror of headshots)."
  - id: unknown_0x15
    type: s2
    doc: "[UNKNOWN] zero in every observed round."
  - id: unknown_0x17
    type: s2
    doc: "[UNKNOWN] zero in every observed round."
  - id: unknown_0x19
    type: s2
    doc: "[UNKNOWN] zero in every observed round."
  - id: lockon_deaths
    type: s2
    doc: "[CONFIRMED] deaths to lock-on — received mirror of lockon_kills, as headshot_deaths mirrors headshots."
  - id: rounds_played
    type: s2
    doc: "[DOUBTED] capture-era label; never nonzero across 9 live reports 2026-07-23."
  - id: round_completed
    type: s2
    doc: "[INFERRED] 1 for every player of a normally-completed round, 0 in mid-game teardown reports."
  - id: round_won
    type: s2
    doc: "[CONFIRMED] winner-only across seven rounds, then transferred on the reporter's first loss. No score contribution."
  - id: seconds_in_game
    type: u4
    doc: "[CONFIRMED] seconds in game (client splits hi/lo u16)."
  - id: experience_total
    type: u4
    doc: "[CONFIRMED] experience, absolute total (not a delta)."
  - id: detail_present
    type: u4
    doc: "[CONFIRMED] 1 when struct B follows, 0 in the short form."
  - id: detail
    type: struct_b
    if: detail_present != 0
    doc: "58-slot event ledger; see struct_b."
  - id: trailing_word
    type: u4
    doc: "[UNKNOWN] trailing value, 0 in every observed report."
types:
  struct_b:
    doc: |
      58 s16 event counters — an itemised ledger, not the scoreboard categories. Contains
      dealt/received PAIRS (b10<->b11, b22<->b23) matching exactly on both sides of every
      observed round. unknown_NN = never observed nonzero or unresolved.
    seq:
      - id: unknown_b00
        type: s2
        doc: "slot 0. [MATCHED 7/7] kills, incl. every kill type tested; 0 for suicides. Not called a kills duplicate — no divergence test has split it from A-kills yet."
      - id: unknown_b01
        type: s2
        doc: "slot 1. [MATCHED 7/7] deaths, suicides included."
      - id: unknown_b02
        type: s2
        doc: "slot 2. [UNKNOWN] never observed nonzero."
      - id: suicides
        type: s2
        doc: "slot 3. [CONFIRMED] 3 in a 3-grenade-suicide round, 0 elsewhere."
      - id: unknown_b04
        type: s2
        doc: "slot 4. [UNKNOWN] never observed nonzero."
      - id: unknown_b05
        type: s2
        doc: "slot 5. [UNKNOWN] never observed nonzero."
      - id: unknown_b06
        type: s2
        doc: "slot 6. [UNKNOWN] never observed nonzero."
      - id: unknown_b07
        type: s2
        doc: "slot 7. [UNKNOWN] never observed nonzero."
      - id: unknown_b08
        type: s2
        doc: "slot 8. [OPEN] one-off 1 in the plain-rifle round; NOT lock-on and NOT the rifle itself (both retested 0)."
      - id: unknown_b09
        type: s2
        doc: "slot 9. [UNKNOWN] never observed nonzero."
      - id: unknown_b10
        type: s2
        doc: "slot 10. [PAIR-DEALT with b11] CQC-contact-flavoured: CQC round 4, barrels 3; 0 for grenades/knife/rifle kills."
      - id: unknown_b11
        type: s2
        doc: "slot 11. [PAIR-RECEIVED with b10] 11 during grab practice with zero deaths/stuns."
      - id: unknown_b12
        type: s2
        doc: "slot 12. [OPEN] 3 in each explosive-kill round; stray 1 in knife/rifle/CQC rounds; 0 in lock-on round and practice. Explosions caused? The stray 1 is unexplained."
      - id: unknown_b13
        type: s2
        doc: "slot 13. [UNKNOWN] never observed nonzero."
      - id: unknown_b14
        type: s2
        doc: "slot 14. [UNKNOWN] never observed nonzero."
      - id: unknown_b15
        type: s2
        doc: "slot 15. [UNKNOWN] never observed nonzero."
      - id: unknown_b16
        type: s2
        doc: "slot 16. [UNKNOWN] never observed nonzero."
      - id: unknown_b17
        type: s2
        doc: "slot 17. [UNKNOWN] never observed nonzero."
      - id: unknown_b18
        type: s2
        doc: "slot 18. [UNKNOWN] never observed nonzero."
      - id: unknown_b19
        type: s2
        doc: "slot 19. [UNKNOWN] never observed nonzero."
      - id: unknown_b20
        type: s2
        doc: "slot 20. [UNKNOWN] never observed nonzero."
      - id: unknown_b21
        type: s2
        doc: "slot 21. [OPEN] 1 alongside the one slam-faint; stun-adjacent."
      - id: unknown_b22
        type: s2
        doc: "slot 22. [PAIR-DEALT with b23] slam/knockdown-flavoured; ticks without a faint (unlike A stuns)."
      - id: unknown_b23
        type: s2
        doc: "slot 23. [PAIR-RECEIVED with b22] 8 during grab practice."
      - id: unknown_b24
        type: s2
        doc: "slot 24. [UNKNOWN] never observed nonzero."
      - id: unknown_b25
        type: s2
        doc: "slot 25. [UNKNOWN] never observed nonzero."
      - id: unknown_b26
        type: s2
        doc: "slot 26. [UNKNOWN] never observed nonzero."
      - id: unknown_b27
        type: s2
        doc: "slot 27. [UNKNOWN] never observed nonzero."
      - id: unknown_b28
        type: s2
        doc: "slot 28. [UNKNOWN] never observed nonzero."
      - id: unknown_b29
        type: s2
        doc: "slot 29. [UNKNOWN] never observed nonzero."
      - id: unknown_b30
        type: s2
        doc: "slot 30. [UNKNOWN] never observed nonzero."
      - id: unknown_b31
        type: s2
        doc: "slot 31. [UNKNOWN] never observed nonzero."
      - id: unknown_b32
        type: s2
        doc: "slot 32. [UNKNOWN] never observed nonzero."
      - id: unknown_b33
        type: s2
        doc: "slot 33. [UNKNOWN] never observed nonzero."
      - id: unknown_b34
        type: s2
        doc: "slot 34. [UNKNOWN] never observed nonzero."
      - id: unknown_b35
        type: s2
        doc: "slot 35. [UNKNOWN] never observed nonzero."
      - id: unknown_b36
        type: s2
        doc: "slot 36. [MATCHED 7/7] kills incl. plain-bullet rounds; 0 for suicides. NOT special-kills; the capture-era '~Other' coincidence is dead."
      - id: unknown_b37
        type: s2
        doc: "slot 37. [UNKNOWN] never observed nonzero."
      - id: unknown_b38
        type: s2
        doc: "slot 38. [UNKNOWN] never observed nonzero."
      - id: kill_1st_place
        type: s2
        doc: "slot 39. [CONFIRMED] kills of the current first-place player; matches the KILL 1ST PC screen line 4/4 (incl. a 0). Scores *5."
      - id: unknown_b40
        type: s2
        doc: "slot 40. [UNKNOWN] never observed nonzero."
      - id: unknown_b41
        type: s2
        doc: "slot 41. [UNKNOWN] never observed nonzero."
      - id: unknown_b42
        type: s2
        doc: "slot 42. [UNKNOWN] never observed nonzero."
      - id: unknown_b43
        type: s2
        doc: "slot 43. [UNKNOWN] never observed nonzero."
      - id: unknown_b44
        type: s2
        doc: "slot 44. [UNKNOWN] never observed nonzero."
      - id: unknown_b45
        type: s2
        doc: "slot 45. [UNKNOWN] never observed nonzero."
      - id: unknown_b46
        type: s2
        doc: "slot 46. [UNKNOWN] never observed nonzero."
      - id: unknown_b47
        type: s2
        doc: "slot 47. [UNKNOWN] never observed nonzero."
      - id: unknown_b48
        type: s2
        doc: "slot 48. [UNKNOWN] never observed nonzero."
      - id: unknown_b49
        type: s2
        doc: "slot 49. [UNKNOWN] never observed nonzero."
      - id: unknown_b50
        type: s2
        doc: "slot 50. [UNKNOWN] never observed nonzero."
      - id: unknown_b51
        type: s2
        doc: "slot 51. [UNKNOWN] never observed nonzero."
      - id: unknown_b52
        type: s2
        doc: "slot 52. [UNKNOWN] never observed nonzero."
      - id: unknown_b53
        type: s2
        doc: "slot 53. [UNKNOWN] never observed nonzero."
      - id: unknown_b54
        type: s2
        doc: "slot 54. [UNKNOWN] never observed nonzero."
      - id: unknown_b55
        type: s2
        doc: "slot 55. [UNKNOWN] never observed nonzero."
      - id: unknown_b56
        type: s2
        doc: "slot 56. [UNKNOWN] never observed nonzero."
      - id: unknown_b57
        type: s2
        doc: "slot 57. [UNKNOWN] never observed nonzero."
