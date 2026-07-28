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
- **Most are ratios, not totals.** "High kill count" against a career total would mean nobody
  qualifies early and everybody qualifies eventually. Per-round or per-hour rates keep the title
  meaningful and let it change as a player's style changes — which is what a play-style title is
  for.

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

**Unwritten.** Both fields currently send zero, which is honest and means no character can hold a
title or medal. The rules are ours to choose; when they exist they belong here, labelled as policy,
with the reasoning for each threshold.

Two constraints on any scheme:

- **Titles should be recomputed, medals should latch.** A medal says "you did this once"; a title
  says "this is how you play". A title that could never be lost would stop describing anybody.
- **Do not tie either to the fingerprints' old behaviour.** Everything on this screen used to award
  everything, which is not a baseline to preserve.
