meta:
  id: mgo2_cmd_4390
  title: "MGO2 0x4390 — host's end-of-round stat report (client -> server)"
  endian: be
doc: |
  The host's per-player round report, one packet per player, sent at round end and on kick
  teardown (and immediately for a mid-round quitter). The server STORES the decoded frame
  (round_report table, one row per report); every stats/history surface derives from it.
  Long form 167 B; a short 51 B form omits struct B (detail_present 0) and moves the
  trailing word up — the branch is real in the binary but UNREACHABLE from this client's
  only caller, so 167 B is the only shape ever sent (517/517 archived frames). Nomad-era
  builds had a longer form with an aborted byte at 0xB7 — this client's 167 B frame never
  reaches it.

  STORAGE MODEL (ELF, full builder trace 2026-07-27). The frame is assembled by a dumb
  serializer at `0xD42178` — 58 identical lwz/sth/put_u16 triples, no logic at all — called
  from exactly one place, `0x27D5B0`, which is where every semantic decision lives. Both
  structs are views of ONE object: a per-player stat blob holding 76 u16 counters. Index
  those `n = 0..75`. The blob's record "key" IS a byte offset, so:

      live[n]     at blob + 0x1a + 2n          baseline[n] at blob + 0xb2 + 2n
      blob base   = 0x1610568 + slot*0x510     (24 player slots, link-time constants)

  So under RPCS3 the live counter for player slot *i*, index *n*, is at the fixed address
  `0x1610568 + i*0x510 + 0x1a + 2n` — a write watchpoint there names the writer directly.
  A static descriptor table at `0x103C0C6` declares all 76 live halfwords as individually
  addressable u16 fields; the baseline is addressable only as a whole 152-byte block.

  Struct A carries n00..n15; struct B carries n17..n74 THROUGH A PERMUTATION (table in
  struct_b). n16 and n75 are wired nowhere. The permutation is the likely explanation for
  the B-index/0x4107-slot rule breaking where it does — wire order is not storage order.

  DELTA SEMANTICS (ELF-traced, live-confirmed): every counter is the per-round DELTA of a
  profile-blob store (live snapshot minus baseline; baseline rewritten after each report;
  round aborts roll live back to baseline). For plain counters delta == the round's count.
  The rebaseline is `SET(key 0xb2, 152, live)` at `0x27DC60`, immediately after the send.

  WIDTH AND SIGN, exactly: both loads are ZERO-extending (`lhz`), the subtract is 32-bit,
  and only the low 16 bits reach the wire. So the wire value is `(s16)(u16)(live − baseline)`
  — a counter that went DOWN wires negative, and one that crossed 0xFFFF wires the wrapped
  low word. Nothing clamps, saturates or validates anywhere in either function.

  b00/b01 are STREAK RECORDS (store-if-greater), confirmed in the binary at `0x27D6D4` /
  `0x27DCD8`: the round's value at blob key `0x15a` is stored into live n17 or live n18 —
  whichever is selected by bit 0 of the flags byte at key `0x159` — only when it exceeds
  what is there. The wire carries the record's increase, so an equal-or-worse round wires 0.
  **b02 is NOT touched by that code**; its streak-record label rests on live data alone. b24
  is the one slot that is not a delta at all (raw absolute snapshot — see its doc).

  The score is the delta of a store that CLAMPS AT 0 (a −10 round on a +7 bank wires −7);
  whether that store resets per game or per stage is deliberately unresolved — no consumer
  for the answer. The clamp is NOT in the builder or its caller (both were read end to end);
  it must live in whatever increments live n03.

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

  DEALT/RECEIVED PAIRS ARE ROUND-LEVEL CONSERVATION LAWS, not pairwise mirrors (restated
  2026-07-27 over all 517 archived frames). Same-frame equality is mostly false, and the
  "this player's received == the OTHER player's dealt" form only holds in 1v1 — across
  3+-player rounds it fails badly (knockouts 5/14, cqc 3/8, melee 5/10). Summed over every
  report of a round they are exact:

      sum(knockouts_received) == sum(knockouts_dealt) + sum(b04) + sum(b06)   26/26 rounds
      sum(b10) == sum(b11)                                                    14/14
      sum(b22) == sum(b23)                                                    13/13
      sum(headshots_stun) == sum(headshots_stun_received)                     15/15
      sum(headshot_deaths) == sum(headshots_lethal)                           86/86
      sum(deaths) == sum(kills) + sum(b03) + sum(b05)                        100/100

  The b06 (friendly stuns) term in the first law is new and load-bearing: round 080841 wired
  2 received against 0 dealt and 2 friendly stuns. Every one of these sums requires INCLUDING
  teardown frames — see the exclusion rule below.

  round_completed=0 FRAMES: EXCLUDE FOR ROLE FIELDS, INCLUDE FOR COUNTERS. Teardown reports
  — crash disconnects, quits, kicks; 45 of the 517 archived frames — carry unreliable ROLE
  and MARKER fields, because those are evaluated at send time against state the teardown has
  already torn down. flag_0x04 is the clear case: the builder computes it as
  `playerIdx == g_snakeIdx` at report time (`0x27DBCC`), so a Snake reported after the role
  is cleared wires 0 (frame 201: flag_0x04=0 with b56=1). Take the role from b56, or from
  the round's other reports, never from a teardown frame's flag.

  Their COUNTERS, though, are ordinary deltas of real events and belong in every population.
  The blanket exclusion this file used to prescribe was WRONG for counters, and it was
  manufacturing the anomalies recorded here as unexplained (corrected 2026-07-27). Including
  teardown frames takes `sum(deaths) == sum(kills+b03+b05)` from 97/98 to 100/100 rounds,
  `sum(headshot_deaths) == sum(headshots_lethal)` from 85/86 to 86/86, `sum(b53) == sum(b54)`
  from 23/23 to 25/25, and the knockout law from 25/26 to 26/26. The b53/b54 role split still
  wants completed frames only — that one is a role field.
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
      from this + A seconds/kills.

      MECHANISM (ELF 2026-07-27, settles the "other modes / other bit values" question): it
      is not a stored counter at all. The caller computes it fresh at send time as the
      one-bit comparison `playerIdx == g_snakeIdx` (`cmpw` at `0x27DBCC`, passed as arg7) and
      the serializer emits it with put_u8. So it is strictly 0 or 1, can never carry other
      bit values, and in a mode with no Snake it is 0 for everyone.

      NOT RELIABLE ON TEARDOWN REPORTS, and now explained: because it is evaluated live
      rather than accumulated, a report sent after the role has been cleared wires 0 even for
      the Snake (frame 201, flag_0x04=0 alongside b56=1). b56 is a stored counter and
      survives. Over completed frames the two agree exactly, 35/35. Take the role from b56,
      or from the round's other reports, whenever round_completed=0.
  - id: kills
    type: s2
    doc: "[CONFIRMED] kills. Suicides and friendly kills do NOT count."
  - id: deaths
    type: s2
    doc: "[CONFIRMED] deaths — all causes: enemy, friendly, suicide, falls."
  - id: lockon_kills
    type: s2
    doc: |
      [CONFIRMED] lock-on kills — single-variable round: 3 in a 3-lock-on round, 0 in five
      kill rounds without.

      CAVEAT for anyone regression-testing against `dev/proto/samples/4390`: the confirming
      round is NOT in that archive. This field and lockon_deaths are 0/517 there, so a test
      that replays the archive will see both as dead. The reading stands on the original
      capture, not on this data set.
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
      [CORRECTED] knockouts received, all types incl. friendly AND self-inflicted. NOT a
      mirror of this player's knockouts_dealt. The relation is a ROUND-LEVEL conservation
      law, exact over every report of the round including teardown ones:

        sum(knockouts_received) == sum(knockouts_dealt) + sum(b04) + sum(b06)     26/26 rounds

      i.e. every knockout received was dealt by somebody, self-inflicted (b04), or a friendly
      stun (b06). The friendly-stuns term was missing from the earlier statement and is
      load-bearing — round 080841 wired 2 received against 0 dealt and 2 friendly stuns.

      The old pairwise form ("received == the OTHER player's dealt") is a 1v1 special case:
      19/20 in two-player rounds but only 5/14 in three-player rounds. Do not use it.

      Frame 058, previously recorded here as an unexplained residual, is RESOLVED: its round
      also contains frame 056, a round_completed=0 teardown report from ch2 one second
      earlier carrying knockouts_dealt=1. The dealer was on the wire the whole time; the
      old blanket "exclude teardown frames" rule hid him. That single correction is what
      took this law from 25/26 to 26/26.

      Candidate feed for Personal Stats 'Times Stunned', but not separated from b04 on the
      screen yet — both wire the same value when the only stuns are self-inflicted.
  - id: headshots_lethal
    type: s2
    doc: "[CONFIRMED] lethal headshots dealt, bullets only (knife head-stabs and tranq darts do not count). Scores *2. The screen HEADSHOTS row shows this + headshots_stun."
  - id: headshot_deaths
    type: s2
    doc: |
      [CONFIRMED] deaths to headshots. The pairing with headshots_lethal is no longer an
      analogy — it is counted out as a round-level conservation law:
      `sum(headshot_deaths) == sum(headshots_lethal)` in 86/86 rounds (teardown frames
      included; excluding them it is 85/86).
  - id: headshots_stun
    type: s2
    doc: "[CONFIRMED] stun headshots dealt (non-lethal headshots — tranq darts to the head). Hit-location, not weapon-class: 3 body-dart stuns wired 0 here. Scores *2 alongside headshots_lethal."
  - id: headshots_stun_received
    type: s2
    doc: |
      [CONFIRMED] stun headshots received. Conserved per round against headshots_stun:
      `sum(headshots_stun) == sum(headshots_stun_received)` in 15/15 rounds. Not a same-frame
      mirror and must not be read as one. The sleep-stab round's 1 suggests the neck syringe
      counts (unverified).
  - id: unknown_0x19
    type: s2
    doc: |
      [UNKNOWN] zero in every observed round (0/517 archived frames).

      NOT A DEAD FIELD — it has real backing storage. It is live index n10, blob key `0x2e`,
      with its own 2-byte descriptor in the table at `0x103C0C6`, and the caller fills it with
      an ordinary `live − baseline` subtract (`0x27D76C`, stored to A+0x28 at `0x27D7A0`,
      serialized at `0xD42358`). Nothing has ever incremented blob+0x2e in an observed round.
      This is "code path exists, no observed round exercised it", not "dead field" — the
      distinction matters, because a future mode or event could move it.
      Live watch address: `0x1610568 + slot*0x510 + 0x2e`.
  - id: lockon_deaths
    type: s2
    doc: |
      [CONFIRMED] deaths to lock-on. Assumed to pair with lockon_kills by analogy with the
      other dealt/received pairs; unlike those, this pairing has NOT been counted out and
      carries no N — and it cannot be checked against `dev/proto/samples/4390`, where both
      lock-on fields are 0/517. See lockon_kills.
  - id: unknown_0x1d
    type: s2
    doc: |
      [DOUBTED] capture-era 'rounds played' label; never nonzero across all live reports
      (0/517 archived frames), so the label has no support and should not be relied on.

      NOT A DEAD FIELD, same as unknown_0x19: real storage at live index n12, blob key `0x32`,
      own descriptor, ordinary `live − baseline` fill (`0x27D7D4`, stored to A+0x30 at
      `0x27D7F0`, serialized at `0xD42388`). Never incremented in an observed round.
      Live watch address: `0x1610568 + slot*0x510 + 0x32`.

      Note the "rounds played" guess is independently implausible under delta semantics: a
      per-round counter incremented once per round would wire 1 in every report, not 0.
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
    doc: |
      [CONFIRMED] seconds in game/round — equal for co-present players of a full round; short
      for mid-round quitters. Range across the archive 4..3515 s.

      Not a stat-block counter: the caller reads a timebase snapshot from blob key `0x508`,
      calls `0x26DE10` at `0x27D80C` for elapsed milliseconds, and divides by 1000 via the
      usual reciprocal (`mulhwu 0x10624DD3` then `srwi 6`, `0x27D824`/`0x27D828`). So it is
      wall-clock elapsed time computed at send time, truncated toward zero — not accumulated
      per-tick, and unaffected by the delta/baseline machinery.
  - id: experience_total
    type: u4
    doc: |
      [CORRECTED] experience, absolute total (not a delta) — but the wire u32 is a
      ZERO-EXTENDED u16, so the top two bytes are structurally always 00 00.

      Source (ELF 2026-07-27): blob key `0x164`, read as a 2-byte field (`GET(0x164, 2)` at
      `0x27D860`, `lhz r6,0x74(r1)` at `0x27DC34`, passed as arg4 and emitted with put_u32 at
      `0xD423F8`). It is read straight through with no baseline subtraction, which is what
      makes it the one absolute value in an otherwise all-delta frame.

      That it is a u16 is a hard ceiling of 65535, and the archive's maximum is 49900 — close
      enough to the ceiling to matter. Whatever this counts, it is not an unbounded career
      total, and a long-lived character will wrap it.

      ANOMALY, still unexplained: across frames 321/323/317/319 one character wired 49450,
      49450, 49400, 49400 — it went DOWN by 50 and then held flat over two scoring rounds,
      while the other character held 214, 214, 264, 264. The value appears to lag the round
      it is reported with, and the decrease contradicts a monotonic total. Do not build
      anything on this field until it is retested deliberately. The two writers of blob key
      `0x164` are at `0x276340` and `0x2780BC` — that is where the retest should start.
  - id: detail_present
    type: u4
    doc: |
      [CONFIRMED] 1 when struct B follows, 0 in the short form. 1 in 517/517 archived frames.

      The short form is real but UNREACHABLE FROM THIS CLIENT (ELF 2026-07-27). The serializer
      branches on its struct-B argument being NULL (`cmpwi cr7,r28,0` / `beq` at
      `0xD42400`/`0xD42408`), writing a literal 1 down the long path and the known-zero
      register down the short one; the short frame is the 47-byte header plus the trailing
      u32 = 51 bytes, confirming the previously estimated size. But the only caller always
      passes a stack address (`mr r8,r15`, r15 = r1+0x1f8, `0x27DC3C`), which can never be 0.

      Keep parsing both shapes — the branch is real — but never expect the short one, and
      treat its arrival as a finding worth investigating rather than routine.
  - id: detail
    type: struct_b
    if: detail_present != 0
    doc: "58-slot Personal Stats delta ledger; see struct_b."
  - id: trailing_word
    type: u4
    doc: |
      [CONFIRMED] HARDCODED ZERO — this field is closed (ELF 2026-07-27). It is not a counter,
      not reserved space with a source, and not something to keep watching.

      The serializer emits it from its 5th argument (`stw r7,0x5e0(r1)` at `0xD421C8`, put_u32
      at `0xD429B0`). The one and only call site in the entire binary passes `li r7, 0`
      (`0x27DC44`). There is no data path behind it whatsoever.

      Matching the 0/517 archived frames. The server's WARN-if-nonzero tripwire can stay as a
      cheap guard against a mis-parse, but it cannot fire from this client, and its firing
      would mean the frame is misaligned rather than that the field means something.
types:
  struct_b:
    doc: |
      58 s16 counters — the per-round delta feed for the 0x4107 Personal Stats record
      (B-index = slot − 1). Plain counts unless marked otherwise; b00/b01 are per-stage
      streak records and b24 is an absolute snapshot (see top doc). Dealt/received pairs
      (b10/b11, b22/b23) are ROUND-LEVEL conservation laws, not same-frame mirrors — see the
      top doc. [PREDICTED] = untested slot-rule inference.

      WIRE ORDER IS NOT STORAGE ORDER (ELF 2026-07-27). The client's live block is 76 u16
      counters indexed n; struct B carries n17..n74 through this permutation, a bijection:

          b00–b19 -> n17–n36        b35     -> n37
          b20–b23 -> n38–n41        b36–b39 -> n42–n45
          b24     -> n46            b40     -> n47
          b25–b31 -> n48–n54        b41,b42 -> n55,n56
          b32,b33 -> n57,n58        b43–b45 -> n59–n61
          b34     -> n62            b46–b57 -> n63–n74

      Read that as the storage neighbourhoods the wire order scrambles: b35 (wakes) is stored
      right after b19, and b24/b40 sit inside the b25..b34 storage run. Since the four known
      exceptions to the "B-index = slot − 1" rule (b35, b46, b47, b48) are precisely slots
      whose storage position differs from their wire position, the permutation is the leading
      candidate explanation for the rule's failures — but that is a HYPOTHESIS, not a result;
      nobody has yet established which of the two orders the 0x4107 record itself follows.

      To watch any slot live under RPCS3: `0x1610568 + playerSlot*0x510 + 0x1a + 2n`.
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
        doc: |
          slot 3. [CONFIRMED] best consecutive lethal-headshots streak this stage (bullets
          only; 2 separated wired 1). Slot 3 never surfaces on the stats screen.

          BUT the streak-record MECHANISM is not shared with b00/b01. The store-if-greater
          code at `0x27D6D4`/`0x27DCD8` touches only live n17 (b00) and n18 (b01), selecting
          between them on bit 0 of the flags byte at blob key `0x159`. Storage index n19
          (this slot) is not written there at all. So the "per-stage running max" label here
          rests entirely on the live observation, and whatever maintains it is elsewhere in
          the binary — worth finding, because the two mechanisms may not have the same reset
          rule.
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
        doc: |
          slot 10. [CONFIRMED 2026-07-27] Text chat messages sent, **both channels combined** —
          there is no separate all-chat or team-chat counter anywhere in the frame.

          Three-player single-variable round, each player sending a different number: Sean 2 all +
          2 team, poop 1 + 1, rawr 3 + 3. Reports came back 4 / 2 / 6, matching the totals exactly
          and distinguishing all three players. The split is not recoverable from this command.

          This retires the "untestable" note: RPCS3's on-screen keyboard does commit the buffer,
          so the earlier failure was a harness problem rather than a client one.
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

          Storage index n31, blob key `0x58`. The binary confirms it is a live field with its
          own descriptor and an ordinary delta fill — so "never incremented in an observed
          round", not "absent". Watch it at `0x1610568 + slot*0x510 + 0x58`; that is the
          cheapest way to settle what, if anything, moves it.
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

          CONFIRMED IN THE BINARY 2026-07-27: this is the ONLY slot in the whole frame that
          is not a delta. The caller loads live n46 and stores it straight through
          (`lhz r0,0x120(r1)` at `0x27DA5C` -> `stw r0,0x258(r1)` at `0x27DA90`); baseline
          n46 is never even loaded, where all 57 other slots go through `subf`. The
          absolute-snapshot reading is now tier 1, not an inference from its values.
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
        doc: "slot 32 unmapped. [UNKNOWN] never observed nonzero (0/517). Storage index n54."
      - id: unknown_b32
        type: s2
        doc: "slot 33 unmapped. [UNKNOWN] never observed nonzero (0/517). Storage index n57."
      - id: unknown_b33
        type: s2
        doc: "slot 34 unmapped. [UNKNOWN] never observed nonzero (0/517). Storage index n58."
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
        doc: "slot 39. [UNKNOWN] never observed nonzero (0/517). Storage index n44."
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
        doc: "slot 44. [UNKNOWN] never observed nonzero (0/517). Storage index n59."
      - id: unknown_b44
        type: s2
        doc: "slot 45. [UNKNOWN] never observed nonzero (0/517). Storage index n60."
      - id: unknown_b45
        type: s2
        doc: |
          slot 46. [UNKNOWN] never observed nonzero (0/517). Storage index n61.

          DOWNGRADED from the name `training_mode_time_s` (2026-07-27). That name was a pure
          slot-rule inference from 0x4107 slot 46 "Training Mode Time", carrying a [PREDICTED]
          tag, and the slot rule has now failed four times in this region (b35, b46, b47, b48).
          An untested inference sitting in the field NAME reads as knowledge to every consumer
          of this file, which is exactly how the rule's earlier failures propagated. It keeps
          the neighbours' honest label until something moves it.
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
        doc: |
          slot 50. [CONFIRMED, SNE] wins-as-Snake: 1 on the winning Snake only, absent in
          BOTH losses. Feeds 0x4107 slot 63 Victories as Snake.

          UPGRADED from [SNE] 3/3 to a 35/35 result with a mechanism (2026-07-27): across
          every completed Snake report in the archive, `b49 == 1` exactly when `b48 >= 3`
          (equivalently `b47 >= 3`) — 8 ones, 27 zeros, no exceptions. So the Snake's win
          condition is THREE DOGTAGS, and this slot is the flag for having met it.

          The discriminating case is frame 126: a Snake with 9 kills and 4 deaths still wired
          b49=1, because the tags were collected. Kills, deaths and survival do not enter
          into it — which also retires any lingering "wins = survived" reading.
      - id: holdup_count
        type: s2
        doc: "slot 51. [CONFIRMED] HOLDUP COUNT (SNE screen row, scores *2): 1 in a 3-stun/1-holdup round (breaking the earlier stun confound), 4 in the 4-holdup round."
      - id: snake_kills
        type: s2
        doc: "slot 52. [CONFIRMED] SNAKE KILL (SNE screen row): kills of the Snake, worth 6 points each (screen 2 = wire 2, score 22 exact only at 6/kill)."
      - id: unknown_b52
        type: s2
        doc: "slot 53. [UNKNOWN] never observed nonzero (0/517). Storage index n69."
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
        doc: |
          slot 57. [CONFIRMED, SNE] rounds-as-Snake: 1 on the Snake every round, never
          nonzero on anyone else. NOT wins-as-Snake (that is b49).

          Upgraded from 3/3 to 35/35 completed frames (2026-07-27), where it equals
          flag_0x04 exactly. The two are NOT redundant, and which one to trust is settled:
          flag_0x04 is recomputed live at send time (`playerIdx == g_snakeIdx`), while this
          is an accumulated counter, so on the three teardown frames (201, 236, 253) the flag
          reads 0 and this still reads 1. **This is the reliable role field; flag_0x04 is
          not.** Prefer it whenever round_completed=0.
      - id: unknown_b57
        type: s2
        doc: |
          slot 58. [UNKNOWN] never observed nonzero (0/517). Storage index n74 — the last
          live counter the frame carries. 0x4107 slots ≥59 (Victories as Snake 63, Knife
          Kills 64, Snake Kills 67, Snake Time 72) exceed this block — weapon lines feed from
          0x43a2 tallies, snake stats from elsewhere.

          For completeness on the storage side: live n16 and n75 exist in the blob with their
          own descriptors but are wired NOWHERE — neither struct A nor struct B reads them.
          They bracket the struct-A/struct-B split (n00–n15 and n17–n74), so the frame carries
          74 of the 76 live counters.
