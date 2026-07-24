meta:
  id: mgo2_cmd_4390
  title: "MGO2 0x4390 — host's end-of-round stat report (client -> server)"
  endian: be
doc: |
  The host's per-player round report, one packet per player, sent at round end and on kick
  teardown (and immediately for a mid-round quitter). The server STORES the decoded frame
  (round_report table, one row per report); every stats/history surface derives from it.
  Long form 167 B; a short ~51 B form omits struct B (detail_present 0) and moves the
  trailing word up. Nomad-era builds had a longer form with an aborted byte at 0xB7 — this
  client's 167 B frame never reaches it.

  DELTA SEMANTICS (ELF-traced, live-confirmed): every counter is the per-round DELTA of a
  profile-blob store (live snapshot minus baseline; baseline rewritten after each report;
  round aborts roll live back to baseline). For plain counters delta == the round's count.
  Three slots are STREAK RECORDS (store-if-greater, zeroed on stage rotation — DM rotates
  every round, observed TDM every 2): b00/b01/b02 wire the record's increase, so an equal-
  or-worse round wires 0. The score is the delta of a store that CLAMPS AT 0 (a −10 round
  on a +7 bank wires −7); whether that store resets per game or per stage is deliberately
  unresolved — no consumer for the answer.

  SCORE FORMULA (client-side, settled 2026-07-24 by wire-exact decompositions):
    kills*3 − deaths*2 + (headshots_lethal + headshots_stun)*2 + hacks(b19)*5
    + assists(b37)*3 + knockouts_dealt*M + wakes(b35)*2 + combo(b36)*1
  where M = 2 in TDM, 3 in DM (mode-specific). Suicide-class deaths deduct like any death.
  Friendly kills/stuns are score-neutral. kill_1st_place (b39) pays *5 in DM. The screen's
  OTHER row = b36 + a knockout-received component whose wire effect is unproven (only ever
  seen under the clamp).

  STRUCT B <-> 0x4107: B-index = personal-stats slot − 1, exact for all 19 tested pairs.
  0x4107 slots ≥ 59 (e.g. 64 Knife Kills) exceed B's 58 slots and are fed elsewhere
  (weapon lines from the 0x43a2 tallies). [PREDICTED] labels below are this rule's untested
  predictions, tier-inference only; the rule provably bends at b35 (wakes) vs slot 36
  (Soldiers Trained), so treat each prediction as a hypothesis for its gesture round.
doc-ref: dev/docs/PROTOCOL.md "0x4390 — update stats"
seq:
  - id: chara_id
    type: u4
    doc: "[CONFIRMED] target character id."
  - id: flag_0x04
    type: u1
    doc: "[FIRST-LIGHT] flag byte: 1 on the Snake's report in the first Sneaking round (2026-07-24), 0 in every other report ever (suicides, teardowns, FF included). Snake-role marker vs SNE-win marker — the observed Snake also won; a losing-Snake round discriminates. If role: time/kills/wins-as-Snake all derive from this + A seconds/kills."
  - id: kills
    type: s2
    doc: "[CONFIRMED] kills. Suicides and friendly kills do NOT count."
  - id: deaths
    type: s2
    doc: "[CONFIRMED] deaths — all causes: enemy, friendly, suicide, falls."
  - id: lockon_kills
    type: s2
    doc: "[CONFIRMED] lock-on kills — single-variable round: 3 in a 3-lock-on round, 0 in five kill rounds without."
  - id: score
    type: s2
    doc: |
      [CONFIRMED] round score as the DELTA of a clamp-at-0 store — NOT raw round points.
      Wires 0 for a losing round with nothing banked, a true negative when banked score
      absorbs the loss (−7 observed = bank 7 → 0 on raw −10). See formula in the header.
  - id: knockouts_dealt
    type: s2
    doc: "[CONFIRMED] knockouts dealt, all types (slam/tranq/sleep) — requires an actual faint; non-fainting melee ticks b22/b23 instead. Friendly stuns do NOT count. Scores *2 TDM / *3 DM."
  - id: knockouts_received
    type: s2
    doc: "[CONFIRMED] knockouts received, all types incl. friendly — mirror of knockouts_dealt. Feeds Personal Stats 'Times Stunned' (slot 5; b04 never ticks)."
  - id: headshots_lethal
    type: s2
    doc: "[CONFIRMED] lethal headshots dealt, bullets only (knife head-stabs and tranq darts do not count). Scores *2. The screen HEADSHOTS row shows this + headshots_stun."
  - id: headshot_deaths
    type: s2
    doc: "[CONFIRMED] deaths to headshots (received mirror of headshots_lethal)."
  - id: headshots_stun
    type: s2
    doc: "[CONFIRMED] stun headshots dealt (non-lethal headshots — tranq darts to the head). Hit-location, not weapon-class: 3 body-dart stuns wired 0 here. Scores *2 alongside headshots_lethal."
  - id: headshots_stun_received
    type: s2
    doc: "[CONFIRMED] stun headshots received — mirror of headshots_stun. The sleep-stab round's 1 suggests the neck syringe counts (unverified)."
  - id: unknown_0x19
    type: s2
    doc: "[UNKNOWN] zero in every observed round."
  - id: lockon_deaths
    type: s2
    doc: "[CONFIRMED] deaths to lock-on — received mirror of lockon_kills."
  - id: unknown_0x1d
    type: s2
    doc: "[DOUBTED] capture-era 'rounds played' label; never nonzero across all live reports."
  - id: round_completed
    type: s2
    doc: "[CONFIRMED] 1 for a player present at normal round end, 0 in quit/teardown reports (twice also 0 with full seconds, unexplained but benign)."
  - id: flawless_win
    type: s2
    doc: |
      [CONFIRMED] 1 iff the player WON the round AND died zero times (settled 2026-07-24:
      a won-but-died-twice round wired 0; refits every prior anomaly incl. the all-zero
      round where no winner survived). NOT 'round won'. No score contribution. Counted per
      stage by b24.
  - id: team_slot
    type: u2
    doc: "[CONFIRMED] team slot index: constant per player per game, 0 for everyone in DM. NOT the team color (index-to-color varies per game)."
  - id: seconds_in_game
    type: u2
    doc: "[CONFIRMED] seconds in game/round — equal for co-present players of a full round; short for mid-round quitters."
  - id: experience_total
    type: u4
    doc: "[CONFIRMED] experience, absolute total (not a delta)."
  - id: detail_present
    type: u4
    doc: "[CONFIRMED] 1 when struct B follows, 0 in the short form."
  - id: detail
    type: struct_b
    if: detail_present != 0
    doc: "58-slot Personal Stats delta ledger; see struct_b."
  - id: trailing_word
    type: u4
    doc: "[UNKNOWN] trailing value, 0 in every observed report. The server WARNs if nonzero."
types:
  struct_b:
    doc: |
      58 s16 counters — the per-round delta feed for the 0x4107 Personal Stats record
      (B-index = slot − 1). Plain counts unless marked otherwise; b00/b01/b02 are per-stage
      streak records (see top doc). Dealt/received PAIRS: b10<->b11, b22<->b23, and the A
      pairs mirror likewise. [PREDICTED] = untested slot-rule inference.
    seq:
      - id: consecutive_kills
        type: s2
        doc: "slot 1. [CONFIRMED] best consecutive-kills streak this stage (record delta): 2 separated kills wired 1. Slot rule: Personal Stats 'Consecutive Kills'."
      - id: consecutive_deaths
        type: s2
        doc: "slot 2. [CONFIRMED] best consecutive-deaths streak this stage: 2 separated deaths wired 1."
      - id: consecutive_headshots
        type: s2
        doc: "slot 3. [CONFIRMED] best consecutive lethal-headshots streak this stage (bullets only; 2 separated wired 1). Slot 3 never surfaces on the stats screen."
      - id: suicides
        type: s2
        doc: "slot 4. [CONFIRMED] suicides — grenades (3/3), menu-suicides (5/5), and falling deaths (3/3) all count. Deduct −2 from score like any death."
      - id: unknown_b04
        type: s2
        doc: "slot 5 would be 'Times Stunned' but this NEVER ticks (players stunned 5 and 3 times wired 0) — that stat feeds from A knockouts_received instead. Purpose unknown."
      - id: friendly_kills
        type: s2
        doc: "slot 6. [CONFIRMED] friendly kills (FF round: 3/3). Not counted in A kills; score-neutral."
      - id: friendly_stuns
        type: s2
        doc: "slot 7. [CONFIRMED] friendly stuns (FF round: 2/2). Not counted in A knockouts_dealt; score-neutral."
      - id: salutes
        type: s2
        doc: "slot 8. [CONFIRMED] salutes (3/3 in the gesture round; strays refit)."
      - id: preset_radio_uses
        type: s2
        doc: "slot 9. [CONFIRMED] preset radio message uses (2/2; strays refit)."
      - id: text_chat_uses
        type: s2
        doc: "slot 10. [PREDICTED] text chat uses — untestable so far: RPCS3's OSK never commits the buffer (client-side; no server chat-permission field exists)."
      - id: cqc_given
        type: s2
        doc: "slot 11. [CONFIRMED] CQC attacks given — grabs/hold-ups (4 CQC round, 11 hold-up-heavy hack round)."
      - id: cqc_taken
        type: s2
        doc: "slot 12. [CONFIRMED] CQC attacks taken — exact mirror of cqc_given in every observed round."
      - id: rolls
        type: s2
        doc: "slot 13. [CONFIRMED] rolls (4/4 gesture round; entire stray history refits, incl. a 1 in an otherwise all-zero report). Plain count, NOT a streak record."
      - id: envg_time_s
        type: s2
        doc: "slot 14. [CONFIRMED] total time using ENVG, seconds — 28 after wearing a picked-up ENVG ~30 s (2026-07-24)."
      - id: dedicated_host_time_s
        type: s2
        doc: "slot 15. [PREDICTED] time as dedicated host, seconds (untested)."
      - id: catapult_uses
        type: s2
        doc: "slot 16. [CONFIRMED] catapult uses (3/3)."
      - id: boosts_given
        type: s2
        doc: "slot 17. [CONFIRMED] boosts given (4/4)."
      - id: falling_deaths
        type: s2
        doc: "slot 18. [CONFIRMED] falling deaths (3/3) — also tick suicides (b03)."
      - id: trap_catches
        type: s2
        doc: "slot 19. [CONFIRMED] times caught in trap — triggers, not deaths (6 triggers / 2 fatal wired 6). Trap kills credit the owner as ordinary kills."
      - id: scans
        type: s2
        doc: "slot 20. [CONFIRMED] successful SOP scans (hacks). Scores *5 AND credits an assist (b37) each. Requires the Scanning skill (grants the S. PLUG item, ELF 0xddee30)."
      - id: box_time_s
        type: s2
        doc: "slot 21. [CONFIRMED] time in cardboard box, seconds (66 for ~a minute)."
      - id: box_uses
        type: s2
        doc: "slot 22. [CONFIRMED] cardboard box uses (1/1; an earlier stray 1 beside a slam-faint was this, not a stun counter)."
      - id: melee_hits_dealt
        type: s2
        doc: "slot 23. [CONFIRMED] melee hits dealt — slams/knockdowns incl. non-fainting ones (unlike A knockouts_dealt)."
      - id: melee_hits_taken
        type: s2
        doc: "slot 24? [PAIR-RECEIVED with b22] exact mirror in every observed round (8 in knockdown practice). Slot 24 never surfaces on the stats screen."
      - id: tdm_consecutive_survivals
        type: s2
        doc: |
          slot 25. [CONFIRMED] TDM Consecutive Survivals (the screen's own name): the
          LONGEST RUN of back-to-back survival rounds this stage — the maximum number of
          survivals in a row, NOT a count of survival rounds (proven: F,F,death,F,F,F has
          five survival rounds but wires 3, the longest run). A 'survival' is one round
          both won AND completed with zero deaths (the A flawless_win event; surviving a
          lost round and winning while dying both tick nothing). TDM only; absolute
          snapshot each report; resets on stage rotation, so runs cannot span stages.
          Settled by one 6-round stage (F,F,F,death,F,F wired 1,2,3,3,3,3) and predictively
          confirmed by a second (1,2,2,2,2,3 called in advance). Career slot 25 accumulates
          as max(career, this).
      - id: bases_conquered
        type: s2
        doc: "slot 26. [PREDICTED] bases conquered (Base mode; untested)."
      - id: sop_destabilizer_uses
        type: s2
        doc: "slot 27. [PREDICTED] SOP destabilizer uses (Base mode; untested)."
      - id: gako_saved
        type: s2
        doc: "slot 28. [PREDICTED] GA-KO saved (Rescue; untested)."
      - id: gako_defended
        type: s2
        doc: "slot 29. [PREDICTED] GA-KO defended (Rescue; untested)."
      - id: unknown_b29
        type: s2
        doc: "slot 30 unmapped on the stats screen. [UNKNOWN] never observed nonzero."
      - id: fully_defended_matches
        type: s2
        doc: "slot 31. [PREDICTED] fully defended matches (Rescue; untested)."
      - id: unknown_b31
        type: s2
        doc: "slot 32 unmapped. [UNKNOWN] never observed nonzero."
      - id: unknown_b32
        type: s2
        doc: "slot 33 unmapped. [UNKNOWN] never observed nonzero."
      - id: unknown_b33
        type: s2
        doc: "slot 34 unmapped. [UNKNOWN] never observed nonzero."
      - id: unknown_b34
        type: s2
        doc: "slot 35 unmapped. [UNKNOWN] never observed nonzero."
      - id: wakes
        type: s2
        doc: |
          slot 36?? [CONFIRMED as WAKES] waking a stunned teammate; scores *2 (screen WAKE
          row + two exact wire decompositions). CONFLICT with the slot rule: slot 36
          fingerprinted as 'Number of Soldiers Trained' — the n−1 rule provably bends here.
      - id: combo
        type: s2
        doc: |
          slot 37 (unmapped on screen). [CONFIRMED] kill-combo points: sum over each
          unbroken kill run of n*(n−1)/2 — streaks 2,2,1 wired 2; deaths reset the run.
          Feeds the screen OTHER row at *1.
      - id: assists
        type: s2
        doc: "slot 38 (unmapped on screen). [CONFIRMED] assists; scores *3. Earned by stun-setups before a teammate's kill AND by each successful scan (3 in a 1v1 hack round). Damage-only setups earn nothing."
      - id: unknown_b38
        type: s2
        doc: "slot 39. [UNKNOWN] never observed nonzero."
      - id: kill_1st_place
        type: s2
        doc: "slot 40. [CONFIRMED] kills of the current first-place player; matches the KILL 1ST PC screen line 4/4. Scores *5. Only ever nonzero in DM."
      - id: unknown_b40
        type: s2
        doc: "slot 41. [UNKNOWN] never observed nonzero."
      - id: unknown_b41
        type: s2
        doc: "slot 42. [UNKNOWN] never observed nonzero."
      - id: unknown_b42
        type: s2
        doc: "slot 43. [UNKNOWN] never observed nonzero."
      - id: unknown_b43
        type: s2
        doc: "slot 44. [UNKNOWN] never observed nonzero."
      - id: unknown_b44
        type: s2
        doc: "slot 45. [UNKNOWN] never observed nonzero."
      - id: training_mode_time_s
        type: s2
        doc: "slot 46. [PREDICTED] training mode time, seconds (untested)."
      - id: combat_training_instructor_s
        type: s2
        doc: "slot 47. [PREDICTED] combat training time as instructor, seconds (untested)."
      - id: combat_training_student_s
        type: s2
        doc: "slot 48. [PREDICTED-DOUBTED] slot rule says combat training time (student), but the first Sneaking round wired 3 on the Snake player with no training involved — the prediction is doubtful; SNE-specific meaning suspected. Unlabelled."
      - id: unknown_b48
        type: s2
        doc: "slot 49. [SNE-LIT] 3 on the Snake player in the first Sneaking round. Unlabelled."
      - id: unknown_b49
        type: s2
        doc: "slot 50. [SNE-LIT] 1 on the Snake player in the first Sneaking round. Unlabelled."
      - id: unknown_b50
        type: s2
        doc: "slot 51. [SNE-LIT] 4 on the Snake player (= his stuns dealt); suspected dealt half of a pair with b51. Unlabelled."
      - id: unknown_b51
        type: s2
        doc: "slot 52. [SNE-LIT] 4 on the non-Snake player (= his knockouts received); suspected received half of a pair with b50. Unlabelled."
      - id: unknown_b52
        type: s2
        doc: "slot 53. [UNKNOWN] never observed nonzero."
      - id: unknown_b53
        type: s2
        doc: "slot 54. [SNE-LIT] 4 on the non-Snake player in the first Sneaking round. Unlabelled."
      - id: unknown_b54
        type: s2
        doc: "slot 55. [SNE-LIT] 4 on the Snake player; suspected pair with b55. Unlabelled."
      - id: unknown_b55
        type: s2
        doc: "slot 56. [SNE-LIT] 4 on the non-Snake player; suspected pair with b54. Unlabelled."
      - id: unknown_b56
        type: s2
        doc: "slot 57. [SNE-LIT] 1 on the Snake player, who won the round — 'wins as Snake' candidate, single sighting. Unlabelled."
      - id: unknown_b57
        type: s2
        doc: "slot 58. [UNKNOWN] never observed nonzero. 0x4107 slots ≥59 (Victories as Snake 63, Knife Kills 64, Snake Kills 67, Snake Time 72) exceed this block — weapon lines feed from 0x43a2 tallies, snake stats from elsewhere."
