# Titles and medals: what they are, and who decides them

**Both are server-driven.** The client draws whatever bits we set and computes nothing — see
`GATES.md` §5a for the proof. That makes every threshold on this page **operator policy**, not
protocol: the original server's rules are unobservable, so ours are a choice we have to make and
label as one (CLAUDE.md, "Distinguishing spec from policy").

Two wire fields carry them, both in `0x4103`:

| wire | what | notes |
| --- | --- | --- |
| **563** | title unlock mask, 22 bits LSB-first | rating-block entry 3 |
| **541** | equipped title, **1-based** | 0 = none |
| **615** | medal bitfield, 16 bytes | medal-**id**-keyed, not row-indexed |
| **611** | bit 0 = "Beta test participant" | |

**Never set title bit 22 or above.** The client's popcount loop runs 23 iterations over a 22-entry
table and corrupts the scrollbar.

### The model, as far as it is understood

Operator account, 2026-07-28: *"you unlock the animal rank and it goes into your history"*, and
*"you wear it on the scorecard"*. That gives three distinct things, and only two of them are wired:

| | field | meaning |
| --- | --- | --- |
| **Collection** | wire 563 mask | every title this character has unlocked |
| **Worn** | wire 541, 1-based | the ONE title on display; 0 = none |
| **History** | — | not fed by any command we know (see Granting policy) |

The worn title is not private: its readers are the title tab, **the name plate**, and two clan
surfaces (`0x916AFC`, `0x915D3C`, `0x906270`, `0x906320`, `0x8842A4`). Other players see it.

**Which implies a command we have never seen.** Choosing which title to wear must send something,
and no unhandled command has ever appeared in a live log — for the simple reason that no character
has ever had a title unlocked, so the selection UI has never been reachable. Granting even one
title makes that command discoverable the first time somebody equips it. Storing the choice is then
a per-character column, and 541 serves it back.

---

## Titles — all 22, with the game's own descriptions

Resource names live inline at `0xE14EB0`, 66 × 16 bytes, three forms per title:
`Title_XXX` / `Title_Short_XXX` / `Title_Doc_XXX`, indexed `(titleNum - 1) * 3 + kind`
(`0x942948`). The text resolves through the 24-bit rotate-5-add hash at `0xD25D0` against the
disc's string resources — verified by `hash("mgo2_res_myscore") == 0x1AB3B6`.

**The `Doc` form names the statistic, NOT the threshold.** "High kill count" does not say how high.
No title threshold table has been found in the binary, and none is known to exist — so the
right-hand column below is *our reading* of each description, and every number a granting rule
eventually uses is invented by us. Read the last column as a hypothesis, not a mapping:

| bit | name | short | the game's description | our source |
| --- | --- | --- | --- | --- |
| 0 | FOXHOUND | F.H | A living legend | rank tier |
| 1 | FOX | FOX | The best of the best | rank tier |
| 2 | DOBERMAN | DOB | A top-class soldier | rank tier |
| 3 | HOUND | HOU | A superior soldier | rank tier |
| 4 | CROCODILE | CRO | High kill count | `round_report.kills` |
| 5 | EAGLE | EAG | Headshot master | `round_report.headshots` |
| 6 | JAWS | JAW | Knife master | `round_weapon_tally`, weapon id 1 |
| 7 | WATER BEAR | W.B | High survival rate | deaths per round |
| 8 | SLOTH | SLO | Highly susceptible to headshots | `headshot_deaths` |
| 9 | FLYING SQUIRREL | F.S | High number of rolls | struct-B b12 |
| 10 | PIGEON | PGE | Prefers not to kill | low kills per round |
| 11 | NIGHT OWL | N.O | Often wears ENVG | struct-B b13 (seconds) |
| 12 | TSUCHINOKO | TSU | Rarely plays | total play seconds |
| 13 | SNAKE | SNA | Prefers Sneaking rules | seconds where `rule = 4` |
| 14 | KEROTAN | KER | Prefers Capture rules | seconds where `rule = 3` |
| 15 | GA-KO | GAR | Prefers Rescue rules | seconds where `rule = 2` |
| 16 | CHAMELEON | CHA | Prefers Team Sneaking rules | seconds where `rule = 7` |
| 17 | CHICKEN | CHI | Rarely participates in battle | low kills + deaths per round |
| 18 | BEAR | BER | Bare hand/CQC master | struct-B b10 |
| 19 | TORTOISE | TOR | Often uses cardboard box | struct-B b20 / b21 |
| 20 | BEE | BEE | Scanning master | struct-B b19 |
| 21 | RAT | RAT | Often gets stuck in traps | struct-B b18 |

Notes that matter for granting:

- **Bits 0–3 are a rank ladder, not play style.** Four descending tiers of "good soldier" with no
  statistic named. They want a single overall measure and should be **mutually exclusive** — a
  player is a FOXHOUND *or* a FOX, not both.
- **Bit 16 (CHAMELEON) is unreachable in v1.** It rewards Team Sneaking, which release-day scope
  keeps switched off (`GATES.md` §1). Serving it would require rule 7 to be playable.
- **Several titles are unflattering** — SLOTH, PIGEON, CHICKEN, TSUCHINOKO, RAT. They are not
  achievements and should not be treated as a ladder; the set is a personality read, and a player
  who rarely plays is *supposed* to get TSUCHINOKO.
- **Ratio-versus-total is now the open design question, not a settled one.** If titles latch (see
  Granting policy), then "everybody qualifies eventually" is not a bug — it is how an unlockable
  works, and a career total is the natural measure. If they are a live read of current style, rates
  are right. The operator's observation points at latching; the earlier note here assumed the
  opposite and was written before that was known.

---

## Medals

The table at `0xE139C0` is 39 rows of `{u32 id, u32 nameHash, u32 threshold}`, terminated by
`0xFFFFFFFF` — 13 families × 3 tiers.

**Be careful what "threshold" means here.** The client loads that word *after* the gate and prints
it into the description as the `%d`. It is **display text, never a condition**. So the table tells
us what each medal *claims* to require, and nothing about what the original server actually
demanded — that is unobservable. The numbers below are labels.

| ids | tiers | award text | statistic |
| --- | --- | --- | --- |
| 1/2/3 | 5 / 10 / 25 | `%d consecutive kills` | 0x4107 slot 1 |
| 10/11/12 | 3 / 10 / 30 | `%d consecutive headshots` | slot 3 |
| 20/21/22 | 5 / 10 / 25 | `%d consecutive deaths` | slot 2 |
| 30/31/32 | 500 / 2000 / 10000 | `%d total kills` | Σ kills |
| 40/41/42 | 500 / 2000 / 10000 | `%d total deaths` | Σ deaths |
| 50/51/52 | 2 / 4 / 6 | `%d consecutive survivals in TDM` | slot 25 |
| 60/61/62 | 50 / 100 / 500 | `%d times spotted Snake first` | slot 56 / b55 |
| 63/64/65 | 50 / 100 / 500 | `%d Mk.II destructions` | b52 |
| 66/67/68 | 50 / 100 / 500 | `%d hold ups performed as Snake` | b50 |
| 70/71/72 | 50 / 100 / 200 | `%d SOP destabilizer uses` | slot 27 |
| 80/81/82 | 50 / 100 / 500 | `%d targets captured` | unmapped |
| 90/91/92 | 50 / 100 / 500 | `%d matches without a scratch` | slot 31 |
| 100/101/102 | 10 / 100 / 300 | `%d people finished training` | slot 36 |

**Three of these cannot be earned on this build**, and the reason is documented rather than
mysterious: Mk.II destructions need 12+ players (`GATES.md` §4), and consecutive kills / headshots
read from `0x4107` slots 1–3, which we serve as zero until stage boundaries are stored
(BACKLOG). `%d targets captured` has no mapped statistic at all.

> **Medal requirements are not known.** The numbers above are the strings this disc ships, which
> may or may not be what the live service required, and are believed to have been reworked at some
> point. Nothing in the binary states a condition. External documentation — patch notes, the
> official site, community records — would be tier 3–4 under CLAUDE.md's hierarchy but is the only
> plausible source, since the server side is unobservable. **Operator has offered to find the
> original requirements; nothing here should be built until they arrive.**

---

## Granting policy

### The source, and what it is worth

A community guide (GameFAQs, HeathclifFlowen) gives concrete requirements. **Tier 3-4** under
CLAUDE.md's hierarchy, and its own author opens by saying all of it is "subject to MASSIVE
scrutiny" after the 1.30 patch. Treat every number as a starting point to be checked live, not as
a specification.

**But it corroborates our extraction in a way that materially raises confidence.** The guide lists
mode-preference ranks that are ABSENT from our 22: Killer Whale (TDM), Fighting Fish (DM), Komodo
Dragon (Stealth DM), Arctic Skua (Solo Capture), Elephant (Base), Cuckoo (Bomb) — and separately
notes that 1.30 "added new ranks, mostly mode preference ranks". Our disc carries preference titles
for exactly four modes (Sneaking, Capture, Rescue, Team Sneaking) and none of those six. Two
independent artefacts agreeing on which titles are launch-era is worth more than either alone.

### The 1.30 split — this is the load-bearing part

The patch notes the guide quotes describe a **behavioural change**, not just renumbering:

| | release day (our target) | after 1.30 |
| --- | --- | --- |
| basis | overall/cumulative performance | the **weekly** total |
| cadence | instant | weekly, at scheduled maintenance |
| how many | **one** — the highest you qualify for, by an override order | **all** you qualify for, with the highest displayed |
| history | — | others you qualified for go to rank history |

So the familiar "you unlock a rank and it goes into your history, and you wear one" is **1.30
behaviour**. Release-day behaviour is simpler: one title at a time, recomputed from career stats,
chosen by override.

That also resolves what looked like a contradiction: the wire has both a 22-bit mask AND a 1-based
equipped field, which reads like a collection plus a choice — but at launch the mask would carry a
single bit and 541 would name that same title. The multi-bit collection is what 1.30 turned on.

### Requirements — two sources, both post-launch, and they disagree

**Source A** — a community guide (GameFAQs, HeathclifFlowen), written pre-1.30 and annotated after
it. Its own author says everything is "subject to MASSIVE scrutiny".

**Source B** — a structured requirements list supplied by the operator, clearly from a *late*
version: it covers RACE, BOMB and Stealth Deathmatch, and carries explicit **weekly** activity
requirements.

Both are **tier 3-4**. Neither describes release day. They disagree materially — Foxhound is
`K/D >= 1.5` and 65% win in A, `(K+S)/(D+SR) >= 1.45` and 52.5% win in B — so at most one is right
for any given patch, and possibly neither is right for ours.

**What they do agree on is the boundary of our title set.** Source B lists ~35 titles; every one
absent from our 22 belongs to a mode added after launch (Fighting Fish/DM, Killer Whale/TDM, Komodo
Dragon/Stealth DM, Elephant/Base, Cuckoo/Bomb, Hog/Race) or is a later specialty (Octopus, Panda,
Puma, Scorpion, Mantis, Ocelot). Source A says the same thing in its own words. Three artefacts —
the disc, and two independent community records — agreeing on which titles are launch-era is worth
more than any of them alone.

#### Source B, restricted to our 22

Modes we do not serve are struck from each rule; **TSNE never counts for us** (`GATES.md` §1).

| title | rule |
| --- | --- |
| FOXHOUND | `(K+S)/(D+SR) >= 1.45` over DM/TDM/SNE · win >= 52.5% over CAP/BASE/RES · bases per BASE round > 1.60 · withdrawal <= 2% · >= 100 rounds in each required mode |
| FOX | `>= 1.40` · `>= 47.5%` · `> 1.40` · `<= 2%` · >= 50 rounds |
| DOBERMAN | `>= 1.35` · `>= 45%` · `> 1.20` · `<= 4%` · >= 25 rounds |
| HOUND | `>= 1.30` · `>= 42.5%` · `> 1.00` · `<= 4%` · >= 5 rounds |
| CROCODILE | `(K+S)/(D+SR) >= 1.50` |
| EAGLE | `>= 1.30` AND `(HS kills + HS stuns)/(kills + stuns) >= 0.50` |
| JAWS | `>= 1.25` AND `knife kills / total kills >= 0.075` |
| WATER BEAR | `deaths / rounds <= 0.50` over RES (+TSNE) |
| SLOTH | `kills/deaths <= 0.85` AND `HS deaths/deaths >= 0.60` AND `stuns/stuns received <= 0.85` |
| FLYING SQUIRREL | `rolls / rounds >= 15` |
| PIGEON | `stuns/kills >= 1.20` AND `stuns/stuns received >= 1.20` |
| NIGHT OWL | `ENVG seconds / play seconds >= 0.05` |
| TSUCHINOKO | last login >= 30 days |
| SNAKE / KEROTAN / GA-KO / CHAMELEON | `mode rounds / overall rounds >= 0.60` AND `weekly mode rounds >= 30` |
| CHICKEN | `kills/rounds <= 0.30` AND `stuns/rounds <= 0.30` AND `stuns received/rounds <= 0.50` AND `deaths/rounds <= 0.50` |
| BEAR | `CQC attacks / rounds >= 5` |
| TORTOISE | `box uses / rounds >= 15` |
| BEE | `scans / rounds >= 0.30` |
| RAT | `stuck in trap / rounds >= 0.30` |

#### What we can compute, and the one thing we cannot

Every input exists in `round_report` or `round_weapon_tally` **except last-login**:

| input | source |
| --- | --- |
| kills, deaths, stuns, stuns received | struct A: `kills`, `deaths`, `stuns`, `counter_0x0f` |
| headshot kills / stuns / deaths | `headshots`, `counter_0x15`, `headshot_deaths` |
| knife kills | `round_weapon_tally`, weapon id 1 |
| rounds, per mode | `count(*)` grouped by `rule` |
| wins | `team_win` |
| **withdrawal rate** | `counter_0x1f` (round_completed) — 1 minus its mean |
| bases conquered | struct B b25 |
| rolls, CQC, box uses, scans, traps, ENVG | b12, b10, b21, b19, b18, b13 |
| weekly anything | the `Period.WEEKLY` window already built |
| **last login** | **NOT TRACKED.** Needed for TSUCHINOKO alone |

Note `withdrawal rate` is a genuinely new use for a column nothing has read: `counter_0x1f` has sat
in `round_report` unread since V16.

### The decision this forces

**Source B bakes the weekly model in** — "Weekly SNE Rounds >= 30" is not a threshold we can drop
without inventing a replacement. Adopting it therefore means adopting **1.30-and-later behaviour**:
weekly evaluation, multiple simultaneous titles, history.

That sits against CLAUDE.md's release-day target. The argument for taking it anyway is that **we
have real requirements for the weekly system and none at all for the launch one** — implementing
release-day behaviour would mean inventing every number, which is precisely the failure mode that
produced the phantom medals. Better a documented later system than an invented earlier one.

The argument against is that it is a knowing departure from the stated target, and those are
supposed to be explicit rather than convenient.

**Unresolved. Operator's call.** Nothing is implemented either way.

### Medals — IMPLEMENTED 2026-07-28 (operator policy)

**A medal is earned when the career statistic reaches the number the client prints in that medal's
own description.**

That is the whole rule, and the justification is narrow but solid: the `0xE139C0` "threshold" is
display text the client sprintf's into the caption *after* the gate, never a condition. So awarding
at exactly that number is the one choice that makes the screen truthful — a medal captioned
"500 Mk.II destructions" is granted at 500 Mk.II destructions. Any other number leaves the client
stating a requirement we did not apply. The original server's rule is unobservable, so this is
policy, not recovery.

**No award state is stored.** Every source is a career sum or a career maximum, so it only grows
and a medal cannot un-earn itself. "Medals latch" therefore needs no table — `medalBits()` derives
the 16-byte field at query time, like everything else on these screens.

**Twelve families are implemented, not thirteen.** Ids 80/81/82 ("%d targets captured") are in the
threshold table but the client's accessor (`0xD5C2A8`) has **no arm for those ids**, so no bit can
draw them. That also disposes of the one family with no mapped statistic — it was unreachable
either way.

Families that cannot light yet, for reasons already documented:

- **consecutive kills / headshots / deaths** read `0x4107` slots 1-3, served as zero until stage
  boundaries are stored (BACKLOG). They are implemented and will start working that day.
- **Mk.II destructions** needs a 12-player Sneaking round (`GATES.md` §4).

### Still undecided

Whether to implement **release-day behaviour** (one title, career stats, recomputed on change) or
the **1.30 behaviour** most people remember (weekly, multiple, with history). CLAUDE.md's target
says the former. Nothing is built either way.
