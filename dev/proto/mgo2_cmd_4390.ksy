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
  and only the low 16 bits reach the wire. So the wire value is `(s16)(u16)(live − baseline)`,
  and a counter that went DOWN wires negative.

  It cannot, however, wrap. Gameplay does not store into the blob directly — it goes through
  a thin wrapper `0x6A9758(blobBase, key, len, u16)`, and every bump site computes
  `min(value + 1, 0xFFFF)`. **The counters SATURATE at 0xFFFF rather than wrapping**, so a
  wrapped low word is not a possible wire value and must not be parsed as one. (The wrapper
  is also why a search for constant keys at the `SET` call site finds nothing: the key is a
  constant one frame up, at the `bl 0x6a9758` site, not at the `bl 0x27F258` inside it.)

  b00/b01 are STREAK RECORDS (store-if-greater), confirmed in the binary at `0x27D6D4` /
  `0x27DCD8`: the round's value at blob key `0x15a` is stored into live n17 or live n18 —
  whichever is selected by bit 0 of the flags byte at key `0x159` — only when it exceeds
  what is there. The wire carries the record's increase, so an equal-or-worse round wires 0.
  **b02 is NOT touched by that code**; its streak-record label rests on live data alone. b24
  is the one slot that is not a delta at all (raw absolute snapshot — see its doc).

  THE SCORE IS NOT AN ACCUMULATOR — SETTLED 2026-07-27, and this supersedes the whole
  "banked store, clamp at 0, per-game or per-stage?" reading. `ComputeScore(rule, slot)` at
  `0x6FA408` RECOMPUTES the score from the other live counters, and `0x71B470` clamps the
  result to [0, 65535] (`0x71B510`..`0x71B534`) before storing it into live n03. That is the
  only write to n03 in the binary. So there is no bank and no reset scope to determine: the
  question "per game or per stage" was malformed. What the wire carries is still the delta
  (n03 now − n03 at baseline), which is why a round that lowers a previously-clamped total
  can wire a negative.

  **DECOMPOSE AGAINST CUMULATIVE COUNTERS, NOT ROUND COUNTERS — live-confirmed 2026-07-27.**
  The inputs `ComputeScore` reads are the LIVE counters, which accumulate across the whole
  game; only the baseline is rewritten per report. So

      wire score = clamp(ComputeScore(cumulative counters))
                 − clamp(ComputeScore(counters as of the last report))

  and a per-round decomposition is correct ONLY for a game's first round, where cumulative
  equals round. This is not a subtlety that can be skipped: it is what made the friendly-kill
  penalty finally visible. Worked example, Base game 229 round 2 — a player with 3 kills,
  3 headshots, 1 team-kill, 2 captures and capture-time 8, who had already team-killed once in
  round 1:

      per-round  (b05 = 1):  3*3 + 1*5 − 1*5 + 2*5 + 8*1  =  27    wire 22   WRONG
      cumulative (b05 = 2):  3*3 + 1*5 − 2*5 + 2*5 + 8*1  =  22    wire 22   exact

  Round 1 had wired 0 from a raw −5 clamped at 0, so the delta is 22 − 0. Both other players
  in the same round reproduce exactly the same way.

  SCORE FORMULA — the actual table (ELF + disc, 2026-07-27). `ComputeScore` walks a
  37-column x 11-row table of s8 coefficients, row = game rule (`mulli r25,r3,37` at
  `0x6FA448`), with a jump table at `0x6FA4C4` mapping each column to the live counter it
  reads. The table is NOT static in the binary: its base is `*(0xFDE2AC) = 0x1659F24` in
  .bss, filled at runtime by the GCX native command at `0x6FA1B8` (hash `0x0035706D`) from
  `-rule N -score <37 ints>` directives in the stage script. The values were read out of the
  disc (`stage/n002a|n003a|n004a/scenerio.gcx` proc23) and are byte-identical across stages:

    rule 0 DEATHMATCH   rule 1 TEAM DEATHMATCH   rule 2 RESCUE   rule 3 CAPTURE
    rule 4 SNEAKING     rule 5 BASE              rule 7 TEAM SNEAKING
    rules 6, 8, 9, 10 are never emitted by any stage script and score nothing at all —
    now EXHAUSTIVE over the disc (2026-07-27): only five stages carry real scripts
    (n002a, n003a, n004a, n007a, n012a; r_sneak_n and r_sna01_n are stubs holding one
    print statement), each emits exactly seven `command [35706d]` blocks, and the seven
    rows are byte-identical across all five (matching md5). There is no hidden BASE
    variant behind rule 6 and no COOP table behind rule 8 anywhere on this disc.

  The rule ids are not guessed from coefficients: the UI's rule-name function `0x9C2778`
  switches on the mode id through a jump table at `0x9C2864` whose cases land on the strings
  `Rule_Eng_DM`, `_TDM`, `_RESCUE`, `_CAP`, `_SNEAK`, `_BASE`, `_TSNE`, `_COOP` — giving
  2 = Rescue and 7 = Team Sneaking directly. That is what identifies rule 7, and it is
  corroborated twice over: the five slots that score only in rule 7 all have writers guarded
  by `cmpwi 7` in functions whose sibling branch tests `cmpwi 2` and writes a confirmed
  Rescue slot.

  **LIVE-CONFIRMED 2026-07-27 for all six playable rules.** One game created per mode in a
  known order, reading the rule byte the client sends in its host settings (`0x4310`): Team
  Deathmatch 1, Rescue 2, Capture 3, Sneaking 4, Base 5, Deathmatch 0 (games 219-224). Six
  single-variable observations, no inference. This retires "identified by coefficient match"
  for rows 0-5 and, by elimination over the eight named rules, leaves rule 7 = Team Sneaking
  as the only reading consistent with both the jump table and the writer guards.

  Coefficients by wire field (0 omitted). r0=DM r1=TDM r2=RES r3=CAP r4=SNE r5=BASE r7=?:

    kills            r0 3  r1 3  r2 7  r3 5  r4 3  r5 3  r7 5
    deaths           r0 −2 r1 −2             r4 −2
    knockouts_dealt  r0 3  r1 2  r2 7  r3 5  r4 2  r5 3  r7 5
    knockouts_recvd  r0 −2 r1 −1             r4 −1
    headshots (lethal + stun, summed)  r0 2 r1 2 r2 3 r3 3 r4 2
    team_win               r2 5  r3 5  r4 5  r5 5  r7 5
    b05 friendly kills     r2 −5 r5 −5
    b19 hacks        r1 5  r3 3  r4 5
    b35 wakes        r1 2  r3 5  r4 2  r5 3  r7 5
    b36 combo        (r0/r1/r4: coefficient clamped to 1; col 9's raw value is the step size)
    b37 assists      r1 3  r2 5  r3 3  r4 3  r5 3
    b39 kill 1st     r0 5
    b40 capture-time r5 1        b25 r5 5     b26 r5 10
    b27 r2 3   b28 r2 3   b29 r2 2   b41 r2 3
    b34 r3 5   b46 r3 1
    b47 r4 3   b48 r4 5   b49 r4 5   b50 r4 2   b51 r4 6   b52 r4 4   b57 r4 3
    b32 r7 3   b43 r7 5   b45 r7 3

  Validated against the archive: 165 of 172 nonzero-score frames reproduce exactly; the
  residuals are clamp effects and the off-wire OTHER column below.

  BEING STUNNED DOES DEDUCT, and the old guess was half right: the term is on
  knockouts_received, but it is −1 in TDM (not −2), and **b04 self-stuns have no coefficient
  in any row**. That half is refuted. Frame 319 needs no extra term: TDM raw =
  2*2 + 2*2 − 1 = 7, wired 4 because the clamped total was already at its floor.

  **The −1 is now live-confirmed on the wire** (2026-07-27, Sneaking game 230 round 1, which
  also confirms the whole SNE row): a player with 3 kills, 3 headshots, combo 3 and ONE
  knockout received wired 17 — `3*3 + 3*2 + 3*1 − 1*1 = 17`. Without the deduction it is 18;
  at the old guessed −2 it is 16. This was the original INCOMPLETE note's open question and it
  is closed. Sneaking has column 36 at zero, so the total is complete with nothing off-wire.

  THE "OTHER" ROW IS NOT RECONSTRUCTABLE FROM THE WIRE. Column 36 reads live n75 — which
  A1 proved is serialised nowhere in this frame — and scores x1 in Rescue, Capture and rule
  7. Every past attempt to decompose OTHER as "b36 + knockouts-received + mode extras" was
  fitting around a counter that simply is not on the wire. b42, long suspected of feeding
  the Rescue OTHER row, has a coefficient of ZERO in every rule; the Rescue OTHER gap
  (screen 18 vs b42 21) is explained by n75, not by b42.

  WHICH FOLLOWS INTO A RULE FOR TESTING THE COEFFICIENTS. Column 36 is nonzero in exactly
  RESCUE, CAPTURE and rule 7, and zero in DM, TDM, SNEAKING and BASE. So:

    - **DM, TDM, Sneaking, Base — the score is fully reconstructable from the wire.** Every
      scoring input is a serialised field, so a decomposition that misses is a real finding.
    - **Rescue, Capture, Team Sneaking — it is NOT, ever.** Any residual can be absorbed by an
      invisible counter, so a decomposition that "works" proves nothing and one that fails
      indicts nothing. Do not try to validate coefficients in these modes.

  Learned the hard way 2026-07-27: two live Rescue rounds were played specifically to check the
  Rescue coefficients and could not, residuals of 2 and 19 both landing where n75 absorbs them.
  Test the friendly-kill −5 in BASE (rule 5 carries it AND has column 36 zero), not in Rescue.

  Suicide-class deaths deduct like any death. Friendly kills are NOT score-neutral in every
  mode — they cost −5 in Rescue and Base, and are merely uncounted in TDM/DM.

  STRUCT B <-> 0x4107: B-index = personal-stats slot − 1, exact for 25+ tested pairs across
  all six modes. 0x4107 slots ≥ 59 (e.g. 64 Knife Kills) exceed B's 58 slots and are fed
  elsewhere (weapon lines from the 0x43a2 tallies; snake stats from flag_0x04 + A-block +
  b49). **The exceptions are not random and the rule does not "break" — RESOLVED 2026-07-27.**

  FIRST, WHAT AN "EXCEPTION" IS, because the shorthand misleads. These are two separately
  labelled lists: struct B's 58 per-round counters, labelled by playing single-variable rounds,
  and 0x4107's 73 career slots, labelled by writing slot numbers into them and reading the
  screen. The "rule" is the observed offset between them. An exception is a place where the
  ARITHMETIC PREDICTS a correspondence that the two labels contradict. **Nobody ever observed a
  wake count appearing on screen under "Number of Soldiers Trained"** — the conflict is between a
  prediction and two solid labels, not between two observations. Read `->` below as "the rule
  predicts this lands here", never as "these are the same statistic":

      b35 wakes              -> slot 36  Number of Soldiers Trained
      b45 tsne_goals         -> slot 46  Training Mode Time
      b46 capture_put_count  -> slot 47  Combat Training Time (Instructor)
      b47 sne_bodysearches   -> slot 48  Combat Training Time (Student)

  Every left-hand reading is live-confirmed and stays exactly as it is; so does every right-hand
  label. Only the arrow is wrong.

  Those four are the ONLY training statistics in the whole 73-slot record, and they are the ONLY
  exceptions. Their neighbours on both sides (slots 35, 37, 45, 49, 50) are unlabelled, so there
  is nothing there to conflict with — which is also why b48 -> slot 49, once listed as a fifth
  exception, is not one.

  The reason is a CATEGORY difference, not a mapping error. Training statistics cannot come from
  a host's per-round report at all: "Soldiers Trained", "Training Mode Time" and the two Combat
  Training times are cross-session bookkeeping about who instructed whom and for how long. They
  are server-side accounting. This server already treats them that way — `CharacterService`
  feeds them from `chara_training_time`, accumulated from lobby presence, and its own docs record
  that this REPLACED a derivation from `round_report` because the host only reports when a player
  leaves early, so a host who quit first reported nobody and lost whole sessions.

  Concretely, of the four collided slots this server today feeds 46, 47 and 48 with real
  presence-derived values, and does not feed 36 (Soldiers Trained) at all — it goes out as a
  fingerprint, and nothing in the codebase tracks students instructed, though `chara_instructor`
  and `instructor_review` exist to build it from.

  So the rule, stated correctly: **B-index = personal-stats slot − 1, among those career slots
  that are fed by round reports at all.** Four slots in that range are fed by server-side
  accounting instead, and the arithmetic simply collides with them. Nothing is unexplained.

  The practical consequence is unchanged and still matters: a [PREDICTED] label inferred from the
  rule is a hypothesis, not a fact — b45 is the cautionary case, where "Training Mode Time" was
  inferred, was wrong, and was one of these very collisions.

  SOME 0x4107 SLOTS ARE NOT FED BY THIS COMMAND AT ALL — established 2026-07-27 by decoding
  the DETAIL page's display list (a 36-entry resource-hash array at `0xE13BDC` in MGO2.elf,
  resolved against the disc's string resources). Nine of its rows are quantities struct B
  provably cannot carry:

      Time Playing DEATHMATCH / TEAM DEATHMATCH / BASE / CAPTURE / RESCUE /
      TEAM SNEAKING / SNEAKING          (seven per-mode play-time counters)
      Host Rating, Instructor Score

  The seven play-time rows cannot be struct-B slots by a simple argument: play time
  necessarily accrues in EVERY round of its mode, so under delta semantics the owning slot
  would be nonzero in essentially every report. Every unmapped B slot is 0/517. They are
  therefore SERVER-DERIVED, and the derivation is available to us — "Time Playing <mode>" is
  the sum of `seconds_in_game` over that character's reports grouped by the game's mode.
  Host Rating and Instructor Score were already in the no-wire-source category; this puts
  the play-time rows there too, and explains a chunk of the 0x4107 slots that no amount of
  0x4390 analysis was ever going to name.

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
      [CORRECTED] round score, the delta of live n03 — NOT raw round points, and NOT a bank.

      MECHANISM (ELF 2026-07-27): n03 is not accumulated. `ComputeScore(rule, slot)` at
      `0x6FA408` recomputes the whole score from the player's other live counters against a
      per-mode coefficient table, and `0x71B470` clamps it to **[0, 65535]** at
      `0x71B510`..`0x71B534` before the single store into n03 — the only write to that field
      in the binary. The wire then carries `n03 − baseline n03` like everything else.

      That is why a negative appears: not because a "bank" absorbed a loss, but because the
      recomputed clamped total came out lower than it was at the last baseline. The clamp
      floor at 0 is what makes deeply negative rounds wire as a smaller negative than the raw
      arithmetic predicts. The old "banked store, resets per game or per stage?" question is
      retired — there is no store to reset. Full coefficient table in the header doc.
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
  - id: lockon_stuns_dealt
    type: s2
    doc: |
      [CONFIRMED] LOCK-ON STUNS DEALT — non-lethal knockouts scored with a lock-on.
      Storage n10, blob key `0x2e`. It was 0/517 across the entire archive until 2026-07-27,
      simply because no archived round had combined a lock-on with a stun weapon.

      **LIVE-CONFIRMED 2026-07-27** (Sneaking game 231): a player landed three lock-on stuns on
      one victim and wired exactly `3` here, with the victim wiring `3` in lockon_stuns_received
      — a clean cross-player pair with known counts, on a field that had been 0/517 until then.

      It also **scores nothing**: those three stuns contributed 0 to a score that decomposed
      exactly without them (`3*3 + 3*2 + 1*5 + 3*1 + 3*6 = 41`, wire 41). n10 is not a column
      in the score table, so this pair is counted but never paid — consistent with the table
      and worth knowing before anyone tries to reconcile a Sneaking score with it.

      An earlier attempt the same night wired 0/0 and was recorded as inconclusive rather than
      negative; that was right. The operator had not yet enabled lock-on, and the tell was in
      the same frame — the round's three kills wired `lockon_kills = 0`, so nothing in it used
      lock-on at all. **A zero here means nothing without a control that proves the mechanic
      was live in the same round.** In the confirming round a fourth stun on a second victim
      also failed to register, and that victim wired 0 received, so the lock evidently was not
      held for it — the wire is the authority on which stuns were locked, not the recollection.

      Named from the binary 2026-07-27, and the derivation is tight. The stun/knockout handler
      `0x6EDC90` takes `(ctx, dealerSlot, victimSlot, weaponId, hitClass, ...)`. Its dealer and
      victim arguments are pinned by two already-CONFIRMED labels — it writes knockouts_dealt
      (key `0x22`) on arg2 and knockouts_received (key `0x24`) on arg3. It then switches on
      `hitClass`: `== 1` writes n08/n09 (the CONFIRMED stun-headshot pair), `== 2` writes
      n10/n12, i.e. this field and unknown_0x1d.

      The same enum appears in the same argument position in the KILL handler `0x6EEAF0`,
      where `== 1` selects headshots_lethal/headshot_deaths and `== 2` selects
      lockon_kills/lockon_deaths. So four independently confirmed labels fix the enum:
      1 = headshot, 2 = lock-on. This pair is the stun-side counterpart of lockon_kills,
      exactly as headshots_stun is of headshots_lethal.
  - id: lockon_deaths
    type: s2
    doc: |
      [CONFIRMED] deaths to lock-on. Assumed to pair with lockon_kills by analogy with the
      other dealt/received pairs; unlike those, this pairing has NOT been counted out and
      carries no N — and it cannot be checked against `dev/proto/samples/4390`, where both
      lock-on fields are 0/517. See lockon_kills.
  - id: lockon_stuns_received
    type: s2
    doc: |
      [CONFIRMED] LOCK-ON STUNS RECEIVED — the received side of lockon_stuns_dealt, written on
      the victim by the same handler `0x6EDC90` under `hitClass == 2`. Storage n12, blob key
      `0x32`.

      Live-confirmed 2026-07-27 (Sneaking game 231): the victim of three lock-on stuns wired
      exactly 3 here against the dealer's 3, while a third player in the same round wired 0.
      Scores nothing, like its dealt-side partner.

      **This retires the capture-era "rounds played" label**, which was already independently
      implausible: under delta semantics a counter incremented once per round would wire 1 in
      every report, not 0 in all 517. See lockon_stuns_dealt for the full derivation of the
      hit-class enum.
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
  - id: team_win
    type: u2
    doc: |
      [CORRECTED 2026-07-27] TEAM WIN flag for this round — 1 if this player's side won, 0
      otherwise. Live index n15, an ordinary delta like every other A counter.

      **LIVE-PROVEN 2026-07-27 by a flip within one game.** Game 227, three Rescue rounds, the
      same two characters throughout: chara 1 wired 1, 1, 0 and chara 3 wired 0, 0, 1. A team
      slot index is constant per player per game by definition and cannot flip mid-game; a win
      flag flips exactly when the winner changes, which is what happened. This is the
      discriminating observation the two earlier lines of evidence could only point at — every
      previous round had the same side winning, where both readings predict identical output.

      **This field was previously documented as `team_slot`, "a team slot index, constant per
      player per game". That reading is falsified.** Two further lines agree:

      1. ELF: it is column 5 of the score table at `ComputeScore` (`0x6FA408`), carrying a
         coefficient of **5 in Rescue, Capture, Sneaking, Base and rule 7**, and 0 in DM/TDM.
         Every per-mode table already documented here lists a "TEAM WIN x5" category whose
         wire source was unidentified. This is it. A slot index would not be a scoring input.
      2. Archive: a slot index is constant per player per game; this is not. Over 239 rounds
         ch1's value flips 50 times, ch2's 22, ch3's 32. And in the 105 rounds where players
         disagree, the round's top scorer holds the 1 in **96 cases against 5** — a winner
         marker, not an identity.

      Both readings predict 0 for everyone in DM, which is why the old one survived: DM has
      no teams, so nobody is ever on a winning *team*. The "grouped killers correctly in a
      3-player TDM" observation is likewise explained — teammates win together.

      NOTE FOR THE SERVER: `round_report.team_slot` (column, Java field `teamSlot`, migration
      `V18__team_slot.sql`) still carries the old name and therefore now stores a win flag
      under a misleading label. Renaming it is a schema change and is deliberately NOT done
      here — the spec is corrected first. Anything deriving team identity from that column is
      wrong today and was wrong before this was noticed.
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
      right after b19, and b24/b40 sit inside the b25..b34 storage run.

      IT DOES NOT EXPLAIN THE SLOT-RULE EXCEPTIONS — hypothesis raised and killed the same
      day (2026-07-27). The tempting story was that 0x4107 follows storage order while 0x4390
      follows wire order, which would have made b35/b46/b47/b48 fall out for free. Tracing
      the 0x4107 parser at `0xD3DB1C` settles it the other way: that record follows the SAME
      slot order as struct B for slots 1..63 (identity mapping into its destination buffer),
      and its only permutation is confined to the tail — wire 64 -> mem 71, 65 -> mem 72,
      66..73 -> mem 63..70, verified live because Knife Kills (slot 64) is drawn from
      `rec+0x11C` = mem 71. Nothing above slot 63 is reachable from struct B's 58 slots, so
      the two permutations never interact. The b35/b46/b47/b48 exceptions are genuine
      exceptions and still want an explanation.

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

          CORROBORATED from the disc + ELF (2026-07-27): the client's title/award table at
          `0xE139C0` carries a `%d consecutive headshots` family (ids 10/11/12, thresholds
          3/10/30) — so the client definitely tracks such a counter, and the 3/10/30 medal
          was already observed live. The award has NO Personal Stats label of its own, which
          fits 0x4107 slot 3 never surfacing on screen while still being fed.

          The streak-record MECHANISM is not shared with b00/b01, and it has now been located.
          The store-if-greater code in the report caller (`0x27D6D4`/`0x27DCD8`) touches only
          live n17 (b00) and n18 (b01), selecting between them on bit 0 of the flags byte at
          blob key `0x159` — storage n19 (this slot) is not written there at all. Its own
          streak is maintained at **`0x6EF620`**, assigned from blob key `0x15c` (b00/b01 use
          key `0x15a`). Separate running total, separate key, so the two need not share a
          reset rule; confirming that they do would take a stage rotation with a live headshot
          streak in flight.
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
        doc: |
          slot 6. [CORRECTED] friendly kills (FF round: 3/3). Not counted in A kills.

          NOT score-neutral — that was a TDM/DM-only observation. It is column 6 of the score
          table and costs **−5 in Rescue and in Base**; in every other rule its coefficient is
          0. So a team-killer is penalised in the objective modes and merely uncredited in the
          deathmatch modes.

          **THE −5 IS LIVE-CONFIRMED (2026-07-27), on the second attempt.** The first Base round
          could not show it: the team-killer wired b05 = 1, kills 0 and a score of 0, because
          raw −5 clamps to 0 and 0 is equally consistent with a coefficient of zero. The
          second round put him in credit — 3 kills, 2 captures, capture-time 8, one team-kill —
          and the arithmetic only closes with the penalty applied twice, once for each round's
          team-kill, against his CUMULATIVE b05 of 2:

              3*3 + 1*5 − 2*5 + 2*5 + 8*1 = 22, wire 22.   (b05 = 1 gives 27; wire says 22)

          So the penalty is real, it is −5, and it applies per friendly kill. Note this doubles
          as the confirmation of the cumulative-counter model — see the header — since the two
          readings differ by exactly one application of this coefficient.

          Friendly kills again did NOT count as kills in the same report (kills 3 against three
          enemy kills, with the team-kill excluded).
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
          slot 15. [UNKNOWN] never observed nonzero (0/517 archived frames), including the
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

          **IDENTICALLY ZERO ON THIS BUILD — re-audited and restored, with a different reason
          than first published (2026-07-27).** Storage n31, blob key `0x58`.

          The original claim was "no writer anywhere", from a sweep of the 152 `bl 0x6a9758`
          bump sites finding none that carried `li r4, 0x58`. **That sentence is literally
          false**, and the sweep's method was unsound (it recovered keys by scanning backwards
          for the nearest `li r4`, which cannot separate keys converging on a shared tail; it
          mis-attributed 2 of 152 sites). Three sites do write blob byte `0x58`:
          `0x27D4DC` (`SET(base, 0x1a, 152)` from a zeroed buffer) and `0x71B3B8`/`0x71BDC0`
          (a host-only per-slot loop, `addi r4,r31,0x1a` / `li r5,2` over `r31 = 0,2,…,0x96`,
          copying the baseline block back over the live block).

          What is actually load-bearing, and survives a proper control-flow re-derivation:
          **nothing can make `live[n31]` differ from `baseline[n31]`.** Init zeroes both; the
          reset loop assigns live := baseline; the post-report store at `0x27DC70` assigns
          baseline := live. The wire field is exactly that difference (`lhz r3,0x102(r1)`,
          `lhz r18,0x19a(r1)`, `subf`, `stw r3,0x230(r1)` at `0x27D970`..`0x27D9D4`), so it is
          identically 0 — not "unwritten", but "written only in ways that move both copies
          together". The slot is safe to treat as a permanent zero.

          The re-audit is trustworthy where the sweep was not: call sites enumerated from raw
          branch encodings, keys recovered by forward AND backward CFG dataflow, and — the
          check the first pass never made — it *proved* all 152 `r4` values are in-function `li`
          constants, so no site takes a computed or parameterised key. The 19 direct `0x27F258`
          sites with non-constant keys are excluded individually by length against the
          descriptor table (byte `0x58` is reachable only as `key=0x58,len=2` or
          `key=0x1a,len=152`). Residual gap, stated honestly: a record pointer spilled to stack
          and reloaded would evade the taint trace. The settling experiment is an RPCS3 write
          watchpoint on `0x1610568 + 0x510*slot + 0x58`.

          Companion result for live n16 (key `0x3a`): same verdict by the same method, but a
          DIFFERENT kind of nothing — n16 is unread and unwritten, dead at both ends, whereas
          n31 is read every round and wires the resulting zero.

          Independently of all that: the LABEL on 0x4107 slot 15 is tier-1 confirmed as "Time as
          Dedicated Host" (entry 11 of the DETAIL display list at `0xE13BDC`), and the live
          falsification of dedicated-host time stands on its own evidence — three hosted games
          produced no report for the hosting character and the next report wired 0. Whatever
          b14 turns out to be, it is not that.

          The LABEL on 0x4107 slot 15 is now tier-1 confirmed as "Time as Dedicated Host":
          it is entry 11 of the DETAIL page's display list, a 36-entry resource-hash array at
          `0xE13BDC` in MGO2.elf (decoded against the disc's string resources 2026-07-27; all
          22 of its independently known index-slot pairs match the live fingerprint exactly).
          So the falsification here means "the client never REPORTS dedicated-host time",
          not "slot 15 is mislabelled". The two claims are compatible and both stand.
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
        doc: |
          slot 26. [CONFIRMED] bases conquered: 4 and 2 in the first Base round, matching both
          screens' CONTROL row exactly. Scores **x5 in Base**, now confirmed on the wire rather
          than off a screen: 2026-07-27, a player who captured three points wired b25 = 3 and a
          score of 32, decomposing as `team_win 1*5 + b25 3*5 + b40 12*1` — exact, in a mode
          with no off-wire column, so the whole score is accounted for.
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
        doc: |
          slot 30, unmapped on the stats screen. [CONFIRMED, RES] GA-KO pickups — **every
          pickup, including the round's first**. Scores **x2 in Rescue** (score-table column
          18, nonzero in rule 2 only).

          THE "SUBSEQUENT GRABS ONLY" READING IS REFUTED (live, 2026-07-27). It was published
          the same morning off an ELF trace of the latch in `0x706BB8` — the first grab takes
          the unlatched path and bumps b41, later grabs fall to `0x706D7C` and bump this slot —
          and read as a partition: b41 = first grab, b29 = the rest. Two live Rescue rounds
          with **exactly one pickup each** wired `b41 = 1` AND `b29 = 1` both times. A partition
          predicts `b29 = 0` there. It is not a partition.

          The reading that fits is a FALL-THROUGH: the first grab bumps both, later grabs bump
          only b29. That predicts 1 grab -> (1, 1) and 2 grabs -> (1, 2), and it restores the
          original capture-era note ("1 on the picking-up attacker in both pickup rounds").
          The exact control flow has NOT been re-read to confirm the fall-through, so treat the
          mechanism as open and the COUNTS as the established fact.

          Worth noting the failure mode, because it has now happened twice in one day from the
          same source: an ELF trace read two arms of a branch as mutually exclusive when they
          share a continuation. The other instance was the `0x6ED650` dispatcher's shared
          increment tail, which is what put b14's "no writer" claim under re-audit.
      - id: fully_defended_matches
        type: s2
        doc: "slot 31. [CONFIRMED-1] fully defended: 1 on the defender of a round where the GA-KO was never taken (engineered idle round); fires per ROUND despite the stat name Fully Defended Matches; absent when the GA-KO was picked up. Defender scored exactly 5 that round with zero activity — B30*5 score-category candidate."
      - id: rescue_solo_team_wipe
        type: s2
        doc: |
          slot 32 unmapped on any screen. [CONFIRMED-1, RES] a Rescue round-end award: granted
          when EVERY member of a losing team of 4 or more was last killed by the same player —
          a solo team wipe. Storage n54; 0/517, which needs a 4v4 Rescue round and one player
          eliminating the entire opposing side, so its absence from a small archive is
          expected.

          Found in the round-end award code as the else-branch of b30 fully_defended_matches,
          which is why the two sit adjacent. Scores nothing (its score-table column is zero in
          all 11 rules) — it is an award/statistic, not a scoring category.
      - id: tsne_spots_made
        type: s2
        doc: |
          slot 33. [CONFIRMED-1, TSNE] TEAM SNEAKING: times this player SPOTTED an enemy
          sneaker. The TSNE twin of b53 times_spotted_snake. Scores **x3**. Storage n57;
          0/517 because the archive contains no Team Sneaking rounds at all.

          Writer `0x6FB8A0(spotter, spotted)` writes key `0x8c` on the spotter at `0x6FB9FC`.
          Reached from the melee/spot handler `0x6ED088`, whose mode test is explicit:
          `bl 0x6a9a38; cmpwi cr7,r3,7; beq` -> the TSNE arm at `0x6ED364` (the neighbouring
          arm handles the Sneaking case and calls `0x70F460`, the Snake-spotting writer of
          b53/b54). Both writers set the identical HUD byte, so it is the same alert mechanism
          in a different mode.
      - id: tsne_times_spotted
        type: s2
        doc: |
          slot 34. [CONFIRMED-1, TSNE] TEAM SNEAKING: times this player WAS SPOTTED while
          sneaking. The TSNE twin of b54 times_spotted_as_snake. Storage n58; 0/517.

          Same writer `0x6FB8A0`, key `0x8e` applied to the spotted player at `0x6FBA54`.
          Renders on the Team Sneaking sub-page (`SP_SCORE_TSNE02`) beside slot 33, and its
          score-table column is zero in all 11 rules — a scoreboard statistic that pays
          nothing, exactly like its Sneaking twin.
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
        doc: |
          slot 39. [UNKNOWN what to call it] never observed nonzero (0/517). Storage index n44,
          blob key `0x72`. Scores nothing (score-table column 11 is zero in all 11 rules) and
          renders on no stats page.

          PRECISELY CHARACTERISED, DELIBERATELY UNNAMED (2026-07-27, after two false starts).

          It is **host-side**, and it fires on a **self-inflicted death in player state 191**,
          in a round whose flags byte has **bit `0x4`** set. The chain:
          - Written at `0x6ED784` (`li r4,114` = key `0x72` at `0x6EDA00`) as **event 8** of a
            host-only numbered player-event dispatcher `0x6ED650`, `f(eventId, playerSlot)` —
            31 callers, jump table at `0x6ED6E0`.
          - Event 8 has exactly one raiser in the binary: `bl 0x6ED650` at `0x778D20`, preceded
            at `0x778D0C` by `0x6EF930(slot, slot, 0, 0)` — a kill whose victim IS the killer.
          - It sits in `0x778380`, the death-cause classifier (the same function raises event 6
            on damage-cause 141 and event 7 on causes 65/67), on the branch
            `player->[0x90] == 191`, after a `[this+0x200]` countdown expires with flag bit 56
            of `[this+0x368]` set. State 191 is written in one place only: `li r9,191;
            stw r9,0x90(r29)` at `0x3A841C`, under `mode == 1` of the virtual method `0x3A81B8`.
          - The mode guard `0x6A9948` reads the third byte of the `[rule, map, flags]` round
            triple the host pushes in `0x4310` at `0xA3 + 3*round`. Only bits `0x2` and `0x4`
            are ever tested binary-wide; this slot is on bit `0x4`, alongside the kill/melee/CQC
            announcement paths.

          State 191 and flags bit `0x4` are unnamed — no string, resource hash, error code or
          script token touches either. So the mechanism is known to the instruction and the
          NAME is still absent, which is the honest place to stop.

          FALSIFIABLE PREDICTION, for whoever gets a round that moves it: because the raiser is
          a self-kill, **b38 and b03 (suicides) must move together on the same player in the
          same report.** If b38 ever ticks without b03, this whole chain is wrong.

          TWO EARLIER READINGS OF THIS SLOT WERE WRONG, both recorded here as a warning.
          A "script-bound listener with no caller" was identified as the sole writer; that block
          (`0x6EC250`..`0x6ECA98`) is **dead code** — its descriptor `0x1014868` is absent from
          the native-command registry, the byte pattern occurs nowhere in the 17 MB binary at
          any alignment, and no branch targets it. And the "one writer" claim was an artefact of
          recovering keys by scanning backwards for the nearest `li r4` across a dispatcher whose
          arms share one increment tail.
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
        doc: |
          slot 42. [CONFIRMED, RES] the round's FIRST GA-KO pickup — one per round, not per
          carry. Scores **x3 in Rescue** (score-table column 19, nonzero in rule 2 only).
          Unlabelled on any stats page.

          Writer `0x706E30` (key `0x88`) on the unlatched path of `0x706BB8`, gated by a
          per-round latch (bit `0x100` of `[this+0x668]`, tested `0x706CA8`, set `0x706D08`).
          Its Team Sneaking twin is slot 44 (key `0x90`, same function, `cmpwi 7` arm).

          The once-per-round part is live-confirmed — two Rescue rounds with one pickup each
          wired 1 both times. What was WRONG was the claim that the latch makes b41 and b29
          mutually exclusive: b29 wired 1 in those same rounds, so the first pickup feeds both.
          See b29.
      - id: rescue_carry_magnitude
        type: s2
        doc: |
          slot 43. [RES] 7 then 21 on the GA-KO-carrying attacker — carry magnitude
          (seconds?). Unlabelled on any stats page.

          IT DOES NOT SCORE, AND THE "OTHER ROW" GAP IS CLOSED (2026-07-27). This slot's
          score-table column (20) is **zero in all 11 rules**, so it contributes nothing to
          the round score in any mode. The long-standing puzzle — screen OTHER = 18 against
          this reading 21 — was never about b42 at all: the Rescue OTHER row is column 36,
          which reads live n75, a counter this frame does not serialise anywhere. OTHER is
          structurally unreconstructable from the wire; stop trying to fit it to b42.

          THE UNITS ARE NOW KNOWN: **2-second ticks**, not seconds. The writers at `0x706FB8`
          and `0x708410` accumulate against a quantum of `0x1770` = 6000 units and bump once
          per quantum, and the same idiom in b13/b20/b40 (all confirmed durations) uses 3000
          for one second. So the archived 7 and 21 are **14 s and 42 s** of carrying, against
          rounds of 98 s and 99 s — which is why the earlier "seconds?" reading looked
          plausible but never quite reconciled with the screen.

          There are two independent accumulators (`[this+0x6ec]`, `[this+0x6f0]`), one per
          carriable objective, so a single report can cover two concurrent carries.
      - id: tsne_first_pickup
        type: s2
        doc: |
          slot 44. [CONFIRMED-1, TSNE] TEAM SNEAKING: FIRST pickup of the round's objective.
          The TSNE twin of b41 rescue_carry_marker. Scores **x5**. Storage n59; 0/517.

          Writer `0x706BB8` (the "objective picked up" method, vtable `0xFB512C`), key `0x90`
          at `0x706E90` under `cmpwi 7`, against the mode-2 arm's key `0x88` = b41 at
          `0x706E30`. A per-round latch (bit `0x100` of `[this+0x668]`, tested `0x706CA8`, set
          `0x706D08`) restricts both to the round's first grab.

          That latch also settles the neighbouring Rescue pair: the ALREADY-latched mode-2
          path goes to key `0x82` = b29 gako_pickups. So **b41 is "first grab" and b29 is
          "subsequent grabs"** — the mechanism behind the guess this file recorded as a
          "per-carry-run marker candidate".
      - id: tsne_carry_time
        type: s2
        doc: |
          slot 45. [CONFIRMED-1, TSNE] TEAM SNEAKING: time spent carrying the objective, in
          **2-second ticks** (quantum `0x1770` = 6000 units). The TSNE twin of b42. Storage
          n60; 0/517. Scores nothing (column 24 is zero in all 11 rules), like its twin.

          Writers `0x7070CC`/`0x707174`/`0x708584`/`0x70862C`, key `0x92`, against the mode-2
          arm's key `0x8a` = b42. There are two independent carry accumulators
          (`[this+0x6ec]`, `[this+0x6f0]`) matching the two `PRP_TEAM_SNEAKING_TGT_01/02`
          objective props, so a TSNE round can carry two objectives at once.
      - id: tsne_goals
        type: s2
        doc: |
          slot 46. [CONFIRMED-1, TSNE] TEAM SNEAKING: objective delivered to the goal. The
          TSNE twin of b27 gako_saved. Scores **x3**. Storage n61; 0/517.

          Writer `0x706A10` (the "objective reached the goal" method, vtable `0xFB5134`):
          `bl 0x6a9a38; cmpwi cr7,r3,7; beq` -> key `0x94` at `0x706BAC`, against the mode-2
          arm's key `0x7e` = b27 at `0x706B54`.

          THIS SLOT WAS CALLED `training_mode_time_s`, AND THAT WAS WRONG — it is a per-goal
          COUNT in a mode that has nothing to do with training. The name came from the slot
          rule pointing at 0x4107 slot 46 "Training Mode Time", a [PREDICTED] label nobody
          tested. Worth noting how good the trap was: slot 46 IS a genuine time slot on the
          stats screen (one of exactly six — 14, 15, 21, 46, 47, 48 — per the renderer's
          `%.2d:%.2d:%.2d` path), so every check short of finding the writer would have
          confirmed it. Fifth slot-rule failure in this region, after b35, b46, b47 and b48.

          THIS SLOT WAS CALLED `training_mode_time_s`, AND THAT WAS WRONG. The name came from
          the slot rule pointing at 0x4107 slot 46 "Training Mode Time" — a [PREDICTED] label
          that was never tested. The score table refutes it outright: a training-mode duration
          would not be a Team Sneaking scoring category. Worth noting how close the trap was —
          slot 46 IS a genuine time slot on the stats screen (one of exactly six, alongside
          14, 15, 21, 47 and 48, per the renderer's `%.2d:%.2d:%.2d` path), so every check
          short of reading the score table would have confirmed the wrong answer. This is the
          fifth slot-rule failure in this region, after b35, b46, b47 and b48.
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

          THE DOGTAG SCORING QUESTION IS ANSWERED (ELF score table, 2026-07-27), and the
          answer is "both of them, at different rates":

              b47 (searches that yielded an item)  x3   in Sneaking
              b48 (tags collected from the ground) x5   in Sneaking

          The old note asked which of the pair feeds the DOGTAG row and at what multiplier,
          and expected to settle it with a round where the two differ. No such round is
          needed: they are columns 28 and 29 of the score table, both nonzero in rule 4 only.
          This also explains why observed per-tag values "varied" — a round is being paid on
          two counters at once, and the four archived rounds where b47 > b48 (233, 238, 266,
          196) mix the rates at 3 and 5 rather than showing one rate that moves.
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
      - id: mk2_kills
        type: s2
        doc: |
          slot 53. [CONFIRMED, SNE] **Mk.II destructions** — destroying the Metal Gear Mk.II,
          worth **x4** in Sneaking. Storage n69.

          NAME CONFIRMED 2026-07-27 — the game says so itself. The Sneaking rule text on the
          disc (gcx string resource `n012a/scenerio_strres/507.bin`, English; the same sentence
          in 508-511 for fr/de/it/es) reads:

              "(If 11 or more characters are playing, one player becomes Metal Gear Mk.II
               and can support Snake.)"

          That is the ONLY entity in the entire string corpus gated on a player count, and the
          binary has exactly one role gated on a player count — the `+0x80` byte of the Sneaking
          singleton, which is the role A6 traced this slot to. Three further corroborations:
          the chosen holder is forcibly moved to **team 2** (`li r0,2; stb r0,1(r3)` at
          `0x71CA0C`), which is the team the kill-credit path tests at `0x6FC254` before
          crediting snake_kills/mk2_kills — the role literally joins Snake's side; `MK2_SKILL`
          and `SNAKE_SKILL` (`0xE1B808`/`0xE1B7F8`) are the only two unique-character skill names
          the ELF references; and `MK2 SPARK` is damage-source id `0x72` (`0x1036BCC`), the
          taser, which is what b57 counts.

          **UNTESTABLE BELOW 12 PLAYERS — not merely untested.** The role is assigned only when
          the participant count clears a hard threshold: `cmpwi cr7,r28,11` / `ble` at
          `0x71C7FC`, with the same literal in the request handler at `0x71C6CC` (refusal writes
          status `0xFF`). r28 counts slots 0..23 whose `team != 0xFE`. Note the code wants
          **> 11, i.e. 12 or more**, while the manual sentence says "11 or more" — an off-by-one
          that could not be reconciled from the binary, so plan for 12+. For contrast the Snake
          role in the same function uses `cmpwi cr7,r28,1` (2+ players).

          Selection is RANDOM once the gate passes: an LCG `seed = seed*0x5D588B65 + 1`
          (`0x71CBD8`..`0x71CBF8`) mixed with round elapsed time and a profile byte, modulo the
          pool size, drawn from the LARGER of team 0 / team 1. An already-seated Mk.II is not
          demoted if the count later drops (`0x71C8D0`).

          So 0/517 is fully explained and no small-lobby experiment can change it. This is a
          DIFFERENT category from the Team Sneaking slots, which merely need a mode nobody has
          hosted — this one needs twelve human participants.
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
          Structural: b53 and b54 are never both nonzero in one frame (0/517).

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
          against sum(b55)=5, with the Snake dead 5 times. b55 <= b53 in 517/517 frames.

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
      - id: mk2_knockouts_dealt
        type: s2
        doc: |
          slot 58. [CONFIRMED, SNE] knockouts DEALT while playing as the Metal Gear Mk.II —
          the same role whose kills b52 counts, and the name is now confirmed with it (see
          b52: the disc's own Sneaking rule text names the role, and the taser that delivers
          these stuns is damage-source `MK2 SPARK`, id `0x72`). Scores **x3** in Sneaking
          (score-table column 31, nonzero in rule 4 only). Storage n74, the last live counter
          the frame carries. 0/517: nobody in the archive held that role and stunned anyone.

          Written by the same role-tested path as b52, which is what ties the two together; as
          with b52 the ROLE's identity (Mk.II) is [PREDICTED], while the mechanism — "a
          knockout dealt while in that role" — is read from the binary. Renders on no stats
          page, so there is no label to recover.

          0x4107 slots ≥59 (Victories as Snake 63, Knife
          Kills 64, Snake Kills 67, Snake Time 72) exceed this block — weapon lines feed from
          0x43a2 tallies, snake stats from elsewhere.

          For completeness on the storage side: live n16 and n75 exist in the blob with their
          own descriptors but are wired NOWHERE — neither struct A nor struct B reads them.
          They bracket the struct-A/struct-B split (n00–n15 and n17–n74), so the frame carries
          74 of the 76 live counters. **The two gaps have different causes**: n16 has no writer
          either, so it is dead at both ends, whereas **n75 is alive** — it is written during
          play and it is score-table column 36, the "OTHER" row, paying x1 in Rescue, Capture
          and Team Sneaking. n75 is the one counter this frame is genuinely missing.
