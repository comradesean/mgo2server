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

  SCORE FORMULA (client-side; every mode retunes multipliers over shared categories —
  full per-mode tables in PROTOCOL.md "0x4390"). TDM/DM:
    kills*3 − deaths*2 + (headshots_lethal + headshots_stun)*2 + hacks(b19)*5
    + assists(b37)*3 + knockouts_dealt*M + wakes(b35)*2 + combo(b36)*1
  where M = 2 in TDM, 3 in DM.

  INCOMPLETE — the formula above is missing at least one deduction term for BEING stunned.
  It is wire-exact for every observed round in which the scorer was not knocked out (e.g.
  frame 318: knockouts_dealt 2 + headshots_stun 1 => 2*2 + 1*2 = 6, wire 6), but frame 319
  (knockouts_dealt 2, headshots_stun 2, knockouts_received 1, b04 1) predicts 8 and wires 4.
  A term of − knockouts_received*2 − b04*2 fits 319 exactly and is consistent with every
  other archived round, but it is NOT confirmed: the paired frame 320 (received 2, dealt 0)
  wires −2 where that term predicts a raw −4, reconcilable only by assuming the clamp-at-0
  store absorbed the difference, which was not independently checked. Settle it with a round
  where one player is stunned, self-stuns zero times, and scores nothing else.

  Also mapped exactly: RESCUE (kill*7, teamwin*5, goal(b27)*3,
  target-defence(b28)*3, carry(b42)*1-ish), BASE (kill*3, sop-destab(b26)*10, control(b25)*5,
  teamwin*5, wake*3, capture-time points(b40)*1 -- time spent advancing a capture, NOT the
  number of captures), CAPTURE (kill*5, put(b46)*1, goal(b34)*5, teamwin*5). SNE categories named with multipliers (dogtag*1 varying values, holdup(b50)*2,
  snake-kill(b51) 6/kill, mk2-kill*4, death*-2) but not yet fully decomposed. Suicide-class
  deaths deduct like any death. Friendly kills/stuns are score-neutral. kill_1st_place (b39)
  pays *5 in DM. The screen's OTHER row = b36 + knockouts-received*1 (wire-proven) + mode
  extras (Base b40, Rescue b42-ish, one carrier-less Capture 5-per-goal).

  STRUCT B <-> 0x4107: B-index = personal-stats slot − 1, exact for 25+ tested pairs across
  all six modes. 0x4107 slots ≥ 59 (e.g. 64 Knife Kills) exceed B's 58 slots and are fed
  elsewhere (weapon lines from the 0x43a2 tallies; snake stats from flag_0x04 + A-block +
  b49). Known exceptions where the rule's fingerprint names proved wrong: b35 (wakes, not
  Soldiers Trained), b46 (Capture put count, not training time), b47/b48 (body searches
  that yielded items / dogtags collected from the ground, not the two training-time slots)
  — remaining [PREDICTED] labels are hypotheses, not facts.

  EVIDENCE TAGS. Every field doc opens with one tier tag, optionally followed by a mode
  scope. Tiers:
    [CONFIRMED]   observed against a real client in a round that varied this field alone,
                  or decomposed exactly; carries its counts (e.g. "3/3").
    [CONFIRMED-1] as above but a single sighting — real, not yet replicated.
    [CORRECTED]   confirmed, and supersedes a previously documented reading stated here.
    [PREDICTED]   inferred from the slot rule or a name fingerprint. A hypothesis. Untested.
    [DOUBTED]     a previously asserted reading that live data has since failed to support.
    [UNKNOWN]     never observed nonzero.
  Mode scope, where a reading only holds in some modes, follows the tier: [CONFIRMED, SNE],
  [CONFIRMED, mode-scoped]. Mode-only tags [RES]/[BASE]/[SNE] on their own mean the slot is
  understood only within that mode and has no tier yet.

  DEALT/RECEIVED PAIRS pair CROSS-PLAYER (this player's received == the other player's
  dealt), never within one frame. Same-frame equality is the exception and mostly false.

  EXCLUDE round_completed=0 FRAMES FROM SLOT ANALYSIS. Teardown reports — crash
  disconnects, quits, kicks; 35 of 360 archived frames — carry unreliable role and marker
  fields, and mixing them into a population manufactures fake counterexamples. Concretely:
  every apparent violation of the b53/b54 role split was a round_completed=0 frame (four of
  them), and excluding them takes the split from "four exceptions, possible unmodelled
  Snake-role handoff" to zero exceptions and the b54 sum relation from 22/23 to 22/22.
  flag_0x04 in particular reads 0 on a teardown report even for the Snake (frame 201:
  flag_0x04=0 with b56=1), so role must be taken from b56 or the round's other reports,
  never from a teardown frame's flag.
doc-ref: dev/docs/PROTOCOL.md "0x4390 — update stats"
seq:
  - id: chara_id
    type: u4
    doc: "[CONFIRMED] target character id."
  - id: flag_0x04
    type: u1
    doc: |
      [CONFIRMED] Snake-role marker: 1 on the Snake's report (win-marker reading falsified —
      it is set on losses too), 0 in every non-SNE report ever. Time/kills-as-Snake derive
      from this + A seconds/kills. Other modes/bit values unobserved.

      NOT RELIABLE ON TEARDOWN REPORTS: reads 0 for the Snake when round_completed=0 (frame
      201, flag_0x04=0 alongside b56=1). Take the role from b56, or from the round's other
      reports, whenever round_completed=0.
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
    doc: |
      [CONFIRMED] knockouts received, all types incl. friendly AND self-inflicted. NOT a
      mirror of this player's knockouts_dealt — the relation is cross-player plus own
      self-stuns:
        knockouts_received == (sum of other players' knockouts_dealt) + own b04
      Holds in 18/19 two-player cases across the archive; the single residual (frame 058,
      received 1 with no dealer and no self-stun) is unexplained. Three-player groups are
      not covered by that check. Candidate feed for Personal Stats 'Times Stunned', but not
      separated from b04 on the screen yet — both wire the same value when the only stuns
      are self-inflicted.
  - id: headshots_lethal
    type: s2
    doc: "[CONFIRMED] lethal headshots dealt, bullets only (knife head-stabs and tranq darts do not count). Scores *2. The screen HEADSHOTS row shows this + headshots_stun."
  - id: headshot_deaths
    type: s2
    doc: "[CONFIRMED] deaths to headshots. Assumed to pair cross-player with headshots_lethal by analogy with the other dealt/received pairs; the pairing itself has not been counted out and carries no N."
  - id: headshots_stun
    type: s2
    doc: "[CONFIRMED] stun headshots dealt (non-lethal headshots — tranq darts to the head). Hit-location, not weapon-class: 3 body-dart stuns wired 0 here. Scores *2 alongside headshots_lethal."
  - id: headshots_stun_received
    type: s2
    doc: |
      [CONFIRMED] stun headshots received. Pairs CROSS-PLAYER with headshots_stun, like the
      b10/b11 and b22/b23 pairs — frames 319/320 wired 2 dealt against 2 received, and
      317/318 wired 1 against 1. Not verified as a same-frame mirror and should not be read
      as one. The sleep-stab round's 1 suggests the neck syringe counts (unverified).
  - id: unknown_0x19
    type: s2
    doc: "[UNKNOWN] zero in every observed round."
  - id: lockon_deaths
    type: s2
    doc: "[CONFIRMED] deaths to lock-on. Assumed to pair cross-player with lockon_kills by analogy with the other dealt/received pairs; the pairing itself has not been counted out and carries no N."
  - id: unknown_0x1d
    type: s2
    doc: "[DOUBTED] capture-era 'rounds played' label; never nonzero across all live reports."
  - id: round_completed
    type: s2
    doc: "[CONFIRMED] 1 for a player present at normal round end, 0 in quit/teardown reports (325/360 archived frames wire 1, 35 wire 0; twice also 0 with full seconds, unexplained but benign)."
  - id: flawless_win
    type: s2
    doc: |
      [CONFIRMED, mode-scoped] zero-death round flag whose exact condition varies by mode:
      TDM/DM = did not lose AND died zero times (won-but-died-twice wired 0; survive-but-
      lose wired 0; draws flag both). RESCUE, BASE and CAPTURE = simply died zero times (10/10
      observations, including losing-team survivors). No score contribution. Counted per
      stage by b24 (TDM).
  - id: team_slot
    type: u2
    doc: "[CONFIRMED] team slot index: constant per player per game, 0 for everyone in DM. NOT the team color (index-to-color varies per game)."
  - id: seconds_in_game
    type: u2
    doc: "[CONFIRMED] seconds in game/round — equal for co-present players of a full round; short for mid-round quitters."
  - id: experience_total
    type: u4
    doc: |
      [CONFIRMED] experience, absolute total (not a delta). ANOMALY, unexplained: across
      frames 321/323/317/319 one character wired 49450, 49450, 49400, 49400 — it went DOWN
      by 50 and then held flat over two scoring rounds, while the other character held 214,
      214, 264, 264. The value appears to lag the round it is reported with, and the
      decrease contradicts a monotonic career total. Do not build anything on this field
      until it is retested deliberately.
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
        doc: |
          slot 2. [CORRECTED] delta of a per-stage running max-streak store (not a per-round
          counter). The client keeps `max_consec_deaths_this_stage` and wires the delta
          (`new_max - old_max`), so it only emits when the streak actually grows. First death
          of a stage wires 1; subsequent deaths that don't extend the max wire 0. Zeroed on
          stage rotation (DM every round, TDM every 2). Confirmed: dying twice then three more
          times still wires only 1 (max never exceeded).
      - id: consecutive_headshots
        type: s2
        doc: "slot 3. [CONFIRMED] best consecutive lethal-headshots streak this stage (bullets only; 2 separated wired 1). Slot 3 never surfaces on the stats screen."
      - id: suicides
        type: s2
        doc: "slot 4. [CONFIRMED] suicides — grenades (3/3), menu-suicides (5/5), and falling deaths (3/3) all count. Deduct −2 from score like any death."
      - id: self_stuns
        type: s2
        doc: |
          slot 5. [CONFIRMED] self-inflicted stuns — the player's own stun grenade knocks
          them out. Counts 3/3, 1/1 and 1/1 in three engineered self-stun-only rounds
          (frames rec01, rec03, 319). Separated from A knockouts_received by frame 319, where
          the same player wired b04 1, knockouts_received 1 and knockouts_dealt 2 while the
          only other player dealt 0 — so this slot is self-stuns alone, not total stuns.
          Does NOT tick A knockouts_dealt (0 in every self-stun-only round). Unlabelled.
          Supersedes the earlier reading that slot 5 was a dead 'Times Stunned'.
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
        doc: |
          slot 12. [CONFIRMED] CQC attacks taken. Pairs CROSS-PLAYER, not within a frame:
          this player's b11 equals the OTHER player's b10 in 11/11 two-player cases where
          either is nonzero. Within a single frame b10 == b11 in only 4/29 nonzero frames,
          so reading it as a same-frame mirror is wrong.
      - id: rolls
        type: s2
        doc: "slot 13. [CONFIRMED] rolls (4/4 gesture round; entire stray history refits, incl. a 1 in an otherwise all-zero report). Plain count, NOT a streak record."
      - id: envg_time_s
        type: s2
        doc: "slot 14. [CONFIRMED] total time using ENVG, seconds — 28 after wearing a picked-up ENVG ~30 s (2026-07-24)."
      - id: unknown_b14
        type: s2
        doc: |
          slot 15. [UNKNOWN] never observed nonzero (0/360 archived frames), including the
          ENVG round where the neighbouring b13/b15/b16 all ticked.

          NOT dedicated-host time — FALSIFIED, by the test the label's own doc specified.
          2026-07-24: three dedicated-host games (0x4310 dedicated=0x01) at 17:54/18:05/18:14
          produced no 0x4390 for the hosting character (ch1) at all; only the two participants
          reported. Under delta semantics the accumulated hosting seconds should then have
          flushed in one lump on that character's next played round, since the baseline is
          rewritten only when a report is emitted. Frame 190 IS that round — ch1 at 18:54:46,
          its first report after hosting (previous one #177 at 17:39:41) — and it wired b14=0,
          as have all 61 subsequent ch1 frames. Three stints' worth of hosting seconds went
          nowhere. Dedicated-host time is not this slot, and on this evidence is not anywhere
          in struct B; the remaining candidates are another command or no wire source at all
          (Host Rating and Instructor Score are already in that category).

          Also NOT container time: rounds spent sitting in a TRASH CAN (frame 325) and
          wearing the DRUM CAN both wired 0 here — and 0 in b20/b21 as well. The box slots
          are cardboard-box-specific and neither container feeds them or this slot, so no
          "generic container" counter has been found anywhere in struct B.

          Third slot-rule fingerprint in this region to fall, after b35 (wakes, not Soldiers
          Trained) and b46 (Capture put count, not training time) — treat the remaining
          [PREDICTED] labels around here as weak.
      - id: catapult_uses
        type: s2
        doc: "slot 16. [CONFIRMED] catapult uses (3/3)."
      - id: boosts_given
        type: s2
        doc: "slot 17. [CONFIRMED] boosts given (4/4)."
      - id: falling_deaths
        type: s2
        doc: "slot 18. [CONFIRMED] falling deaths (3/3) — also tick suicides (b03)."
      - id: triggered_trap
        type: s2
        doc: "slot 19. [CONFIRMED] times caught in trap — triggers, not deaths (6 triggers / 2 fatal wired 6). Trap kills credit the owner as ordinary kills."
      - id: sop_scans
        type: s2
        doc: "slot 20. [CONFIRMED] successful SOP scans (hacks). Scores *5 AND credits an assist (b37) each. Requires the Scanning skill (grants the S. PLUG item, ELF 0xddee30)."
      - id: box_time_s
        type: s2
        doc: |
          slot 21. [CONFIRMED] time in the CARDBOARD BOX specifically, seconds (66 for ~a
          minute). Item-specific, not a generic "in a container" timer: a round spent
          wearing the DRUM CAN — a wearable cardboard-box facsimile, the closest possible
          near-miss — wired 0 here, as did a round sitting in a TRASH CAN (2026-07-26).
          Whatever else those two feed, it is not this slot or b21.
      - id: box_uses
        type: s2
        doc: |
          slot 22. [CONFIRMED] CARDBOARD BOX uses (1/1; an earlier stray 1 beside a
          slam-faint was this, not a stun counter). Item-specific like b20 — wearing the
          drum can and sitting in a trash can both wired 0 (2026-07-26).
      - id: melee_hits_dealt
        type: s2
        doc: "slot 23. [CONFIRMED] melee hits dealt — slams/knockdowns incl. non-fainting ones (unlike A knockouts_dealt)."
      - id: melee_hits_taken
        type: s2
        doc: |
          slot 24. [CONFIRMED] melee hits taken. Pairs CROSS-PLAYER like b10/b11: this
          player's b23 equals the OTHER player's b22 in 8/8 two-player cases where either
          is nonzero. Within a frame b22 == b23 in 0/26 nonzero frames — it is not a
          same-frame mirror. Slot 24 never surfaces on the stats screen.
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
        doc: "slot 26. [CONFIRMED] bases conquered: 4 and 2 in the first Base round, matching both screens' CONTROL row exactly (scores *5 in Base)."
      - id: sop_destabilizer_uses
        type: s2
        doc: "slot 27. [CONFIRMED] SOP destabilizer uses: 1 on the single engineered use, score exact with the *10 category (42 = bases 3*5 + this*10 + teamwin 5 + b40 12)."
      - id: gako_saved
        type: s2
        doc: "slot 28. [CONFIRMED] GA-KO saved = goals: 1 on the delivering attacker, screen GOAL=1x3; absent for pickup-without-delivery. Scores *3 in Rescue."
      - id: gako_defended
        type: s2
        doc: "slot 29. [CONFIRMED] GA-KO defended = the screen TARGET DEFENCE category, scoring *3 (defender round decomposed 18 = kill*7 + hs*3 + this*3 + teamwin*5 exact); requires an actual defense event — 0 in the untouched-GA-KO round (B30 fires there instead)."
      - id: gako_pickups
        type: s2
        doc: "slot 30 unmapped on the stats screen. [RES] 1 on the picking-up attacker in both pickup rounds (with and without delivery) — pickups reading holding."
      - id: fully_defended_matches
        type: s2
        doc: "slot 31. [CONFIRMED-1] fully defended: 1 on the defender of a round where the GA-KO was never taken (engineered idle round); fires per ROUND despite the stat name Fully Defended Matches; absent when the GA-KO was picked up. Defender scored exactly 5 that round with zero activity — B30*5 score-category candidate."
      - id: unknown_b31
        type: s2
        doc: "slot 32 unmapped. [UNKNOWN] never observed nonzero."
      - id: unknown_b32
        type: s2
        doc: "slot 33 unmapped. [UNKNOWN] never observed nonzero."
      - id: unknown_b33
        type: s2
        doc: "slot 34 unmapped. [UNKNOWN] never observed nonzero."
      - id: capture_goals
        type: s2
        doc: "slot 35 unmapped. [CONFIRMED] CAPTURE goals: 1 with the round's single goal, screen GOAL=1x5, score exact. Distinct from Rescue goals (b27)."
      - id: wakes
        type: s2
        doc: |
          slot 36. [CORRECTED] waking a stunned teammate; scores *2 (screen WAKE
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
      - id: base_capture_time_points
        type: s2
        doc: |
          slot 41. [CONFIRMED] BASE. Feeds OTHER *1. **Accrues with time spent actively advancing
          a capture** — roughly one point per 4-5 s of capture-bar progress, per player. A solo
          full capture takes ~20 s and pays 4, which is why this read as "captures*4" until
          2026-07-26; that earlier reading came from three sightings (16/8/12 for 4/2/3 captures)
          in which every capture completed, the one case where both models give the same number.
          Falsified and replaced by four controlled observations:
            - three captures interrupted at 90%+ paid **13** — not a multiple of 4, and no capture
              completed;
            - two same-team players capturing together finish in ~10 s and get **2 each**, i.e.
              each player is paid for their own time, not for the capture;
            - ~4-5 s on a point pays 1;
            - contested (one player from each team) and standing on an already-owned point pay
              **nothing** to anyone — in both cases the bar is not advancing.
          So the quantity is the player's own sustained progress time, not captures, not presence,
          and not defending. Progress must be sustained: leaving and returning such that the bar
          resets does not accumulate, while progress held across an interruption does.
      - id: rescue_carry_marker
        type: s2
        doc: "slot 42. [RES] 1 on the GA-KO-carrying attacker in both carry rounds — per-carry-run marker candidate. Unlabelled."
      - id: rescue_carry_magnitude
        type: s2
        doc: "slot 43. [RES] 7 then 21 on the GA-KO-carrying attacker — carry magnitude (seconds?). Feeds the Rescue OTHER row imperfectly: screen OTHER=18 vs this=21, gap unresolved (the no-delivery round decomposes as OTHER=7 minus death*2 exactly). Unlabelled."
      - id: unknown_b43
        type: s2
        doc: "slot 44. [UNKNOWN] never observed nonzero."
      - id: unknown_b44
        type: s2
        doc: "slot 45. [UNKNOWN] never observed nonzero."
      - id: training_mode_time_s
        type: s2
        doc: "slot 46. [PREDICTED] training mode time, seconds (untested)."
      - id: capture_put_count
        type: s2
        doc: "slot 47. [CONFIRMED] CAPTURE PUT COUNT: 30 = the screen PUT COUNT=30x1 row, score exact. (Second training-name slot-rule casualty in this region — the fingerprint said Combat Training Instructor.)"
      - id: sne_bodysearches
        type: s2
        doc: |
          slot 48. [CONFIRMED, SNE] successful body searches on knocked-out characters that
          yielded an item. Searches that yield nothing do not fire.

          SNAKE-SIDE ONLY: appears on the Snake's report and nowhere else — 13/13 completed
          frames carrying it have flag_0x04=1 and b56=1, and no attacker report has ever
          carried it. Do not look for this on a non-Snake report; dogtag collection is the
          Snake's objective.

          See b48 for the b47 >= b48 relation and its counts.
      - id: sne_dogtags_collected
        type: s2
        doc: |
          slot 49. [CONFIRMED, SNE] times the player actually collected a dogtag from the
          ground. Snake-side only, exactly like b47 (13/13 completed frames, flag_0x04=1).

          b47 >= b48 in 13/13 completed frames where either is nonzero — equal in 9, STRICT
          in 4: frames 233 (4/3), 238 (1/0), 266 (1/0), 196 (5/3). Those four rounds are the
          whole reason these are two slots and not one counter: a search can yield an item
          without a tag being collected. Consistent with the search dropping the tag and
          collection being a separate act, so b48 is structurally bounded by b47.
          (Counts are over round_completed=1 only; the rc=0 teardown frame at 070239 is
          excluded per the header rule and would otherwise read 14/14.)

          Feeds the SNE DOGTAG score row, but NEITHER the multiplier NOR which of the pair
          feeds it is resolved: the one decomposed round (~16 points across two tags) had
          b47 == b48, so it cannot distinguish them, and observed tag values vary. Settling
          it wants a round where b47 and b48 differ and the DOGTAG row is read off screen.
      - id: wins_as_snake
        type: s2
        doc: "slot 50. [SNE] wins-as-Snake: 1 on the winning Snake only, absent in BOTH losses (3/3). Feeds 0x4107 slot 63 Victories as Snake."
      - id: holdup_count
        type: s2
        doc: "slot 51. [CONFIRMED] HOLDUP COUNT (SNE screen row, scores *2): 1 in a 3-stun/1-holdup round (breaking the earlier stun confound), 4 in the 4-holdup round."
      - id: snake_kills
        type: s2
        doc: "slot 52. [CONFIRMED] SNAKE KILL (SNE screen row): kills of the Snake, worth 6 points each (screen 2 = wire 2, score 22 exact only at 6/kill)."
      - id: unknown_b52
        type: s2
        doc: "slot 53. [UNKNOWN] never observed nonzero."
      - id: times_spotted_snake
        type: s2
        doc: |
          slot 54. [CONFIRMED, SNE] times THIS player spotted Snake (the alert symbol),
          per-player. Appears on non-Snake reports only — zero exceptions across every
          completed (round_completed=1) report in the archive.

          Evidence: over completed rounds, the Snake's b54 equals the SUM of all other
          players' b53 in 22/22 rounds, 15 of which had three players. The three-player
          rounds are what prove it (1+3=4, 3+7=10, 1+1=2, 1+3=4, ...): in 1v1 the relation
          is a trivial identity, which is exactly why the earlier kills-of-Snake reading
          survived — it was degenerate with b51 whenever only one spotter existed.
          Structural: b53 and b54 are never both nonzero in one frame (0/360).

          WHAT A "SPOT" IS: shooting/hitting Snake, not passively sighting him — the alert
          symbol is the reveal that a hit causes. This is the key to the whole b51/b53/b55
          cluster: a one-shot kill fires all three exactly once in the same life, which is
          why the three read as duplicates for so long (sum(b53) == sum(b51) in 11 of 22
          completed rounds). Any test intended to separate them must hit Snake WITHOUT
          killing him.

          The name is snake-specific because the MECHANIC is: Snake is the only character
          who triggers the alert/spotted state at all, in any mode. There is no generic
          "spotted a player" counter for this to be a special case of, which is why b53/b54
          are 0 in every non-SNE report across all 360 archived frames.
      - id: times_spotted_as_snake
        type: s2
        doc: |
          slot 55. [CONFIRMED, SNE] times Snake was spotted in total, on the Snake's own
          report — the sum over all spotters (22/22 completed rounds; see b53 for the
          derivation and the three-player evidence). Snake reports only, zero exceptions
          among completed reports. Previously misread as deaths-as-Snake, which fitted only
          because it equalled the Snake's A deaths in the three 1v1 rounds then available;
          three-player rounds separate the two immediately.

          "as Snake" is exact, not a hedge: Snake is the only character the alert/spotted
          mechanic applies to, so there is no wider counter this could be a facet of.
      - id: first_to_spot_snake_per_life
        type: s2
        doc: |
          slot 56. [CONFIRMED, SNE] credits the player who spots Snake FIRST in each Snake
          life — one credit per life, no further credit until that Snake dies.

          Evidence, over completed rounds: summing b55 across the non-Snake players equals
          the Snake's death count in 22/22 rounds (and equals 1 in the four rounds where he
          never died but was spotted — his one surviving life). So b55 counts LIVES, not
          spots, which is what separates it from b53: round 091106 wired sum(b53)=10 spots
          against sum(b55)=5, with the Snake dead 5 times. b55 <= b53 in 360/360 frames.

          Why it looked degenerate with b51 (snake kills) for so long: a spot is triggered
          by SHOOTING Snake, so a one-shot kill produces exactly one spot, one kill and one
          first-spot in the same life. In 11 of 22 completed rounds — half the tests —
          sum(b53) == sum(b51) for precisely this reason. Rounds where Snake is hit without
          dying break the tie immediately.
      - id: rounds_as_snake
        type: s2
        doc: "slot 57. [SNE] rounds-as-Snake: 1 on the Snake every round (3/3 incl. both losses), role-correlated like flag_0x04. NOT wins-as-Snake (that is b49)."
      - id: unknown_b57
        type: s2
        doc: "slot 58. [UNKNOWN] never observed nonzero. 0x4107 slots ≥59 (Victories as Snake 63, Knife Kills 64, Snake Kills 67, Snake Time 72) exceed this block — weapon lines feed from 0x43a2 tallies, snake stats from elsewhere."
