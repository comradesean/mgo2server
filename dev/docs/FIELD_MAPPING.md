# Field-mapping campaign: every unknown field in every packet we use

**Goal: total understanding.** Not "enough to work" — every field named, positioned and explained,
with the evidence in the `.ksy` `doc:` tag so nobody has to re-derive it.

Scope is **packets the server actually uses** — registered handlers and commands we write. The 19
we have never seen are parked separately in `PACKETS_NOT_OBSERVED.md` and are not part of this.

## The number

**44 packets, 178 unknown fields**, as of 2026-07-30. Regenerate with the script in this file's
history; the criterion is a `- id:` whose name starts with `unknown` or `unread`.

## Method, and the rules that keep it honest

1. **Tier 1 or nothing.** A field is only renamed when the binary says what it is: an address, an
   instruction, a destination struct offset. `dev/docs/ADDRESSES.md` has the methodology and the
   PPC64/OPD gotchas.
2. **Positions are already evidence and must not move.** Sizes and offsets in these schemas were
   read from parsers and are load-bearing. Renaming a field and documenting it is the work;
   changing a width is a separate, argued decision.
3. **A precise negative is a result.** "No reader anywhere in the image" is worth recording, and
   several fields have turned out to be exactly that. Say which searches established it.
4. **Never infer meaning from a neighbour's name or from a reference server.** Six regressions have
   come from that. Where a value is inherited and unexplained, say so in the `doc:` rather than
   inventing a label.
5. **Disc resources are fair game** — `dev/tools/gcx` and `dev/tools/solideye`, disc at
   `D:\rpcs3-v0.0.41-19598-357b7d44_win64_msvc\games\METAL GEAR SOLID 4 GUNS OF THE PATRIOTS
   [BLUS30109]` (WSL: `/mnt/d/...`). `AUTOMATCH.md` section 10 documents the string-resource method
   that has already resolved skill names, gear names and colour names.

## Work list

| id | dir | fields | unknown | family | status |
| --- | --- | --- | --- | --- | --- |
| `0x4107` | s2c | 76 | **35** | stats | batch 1 done — 2 resolved (slots 33/34 = Team Sneaking), remaining 35 have **no reader in the image** |
| `0x4313` | s2c | 52 | **16** | game | open |
| `0x4b21` | s2c | 28 | **11** | clan | open |
| `0x4b81` | s2c | 18 | **10** | clan | open |
| `0x4221` | s2c | 17 | **9** | social | open |
| `0x4310` | c2s | 31 | **8** | game | open |
| `0x4120` | s2c | 27 | **7** | connect | open |
| `0x4305` | s2c | 33 | **7** | game | open |
| `0x4b54` | s2c | 11 | **7** | clan | open |
| `0x4991` | s2c | 14 | **6** | lobby | open |
| `0x4101` | s2c | 13 | **5** | connect | open |
| `0x4582` | s2c | 8 | **5** | social | open |
| `0x4602` | s2c | 8 | **5** | social | open |
| `0x4302` | s2c | 21 | **4** | game | open |
| `0x4b12` | s2c | 10 | **4** | clan | open |
| `0x4b75` | s2c | 7 | **4** | clan | open |
| `0x4129` | s2c | 18 | **3** | connect | open |
| `0x4105` | s2c | 21 | **2** | stats | batch 1 done — cols 13/15 have **no reader in the image**; both docs now carry the scan that establishes it |
| `0x4122` | s2c | 17 | **2** | connect | open |
| `0x4902` | s2c | 12 | **2** | lobby | open |
| `0x3101` | c2s | 26 | **1** | other | open |
| `0x4112` | c2s | 1 | **1** | other | open |
| `0x4130` | c2s | 23 | **1** | other | open |
| `0x4150` | c2s | 1 | **1** | other | open |
| `0x4316` | c2s | 1 | **1** | other | open |
| `0x4344` | c2s | 2 | **1** | other | open |
| `0x4390` | c2s | 81 | **1** | other | open |
| `0x43a6` | c2s | 1 | **1** | other | open |
| `0x43c0` | c2s | 5 | **1** | other | open |
| `0x43c4` | c2s | 1 | **1** | other | open |
| `0x43c8` | c2s | 2 | **1** | other | open |
| `0x4440` | c2s | 1 | **1** | other | open |
| `0x4700` | c2s | 4 | **1** | other | open |
| `0x4800` | c2s | 6 | **1** | other | open |
| `0x4b10` | c2s | 3 | **1** | other | open |
| `0x4b46` | c2s | 1 | **1** | other | open |
| `0x4b70` | c2s | 1 | **1** | other | open |
| `0x2002` | s2c | 1 | **1** | other | open |
| `0x2004` | s2c | 1 | **1** | other | open |
| `0x3049` | s2c | 14 | **1** | other | open |
| `0x4131` | s2c | 9 | **1** | other | open |
| `0x4682` | s2c | 5 | **1** | other | open |
| `0x4822` | s2c | 9 | **1** | other | open |
| `0x4841` | s2c | 2 | **1** | other | open |

## What batch 1 established, and what it changed about the method

**2 of 39 fields got names. That is the honest headline, and it is not the whole result.** The
larger outcome was provenance: 27 slots moved from tier 2 (fingerprint-only — we knew a value
appeared, not where it came from) to tier 1 with an address, an instruction and a destination
offset. And every remaining unknown now carries a *precise negative* — which searches were run and
what would settle it — instead of a blank `[UNKNOWN]`.

That ratio is worth expecting on the rest. Most of these fields have **no reader in the image**;
the work is proving that rather than naming them.

### Lead with the disc, not the disassembler

The string-resource route works for anything the client renders a label for. `gcx` set
`$strres:17779`, group `1ab3b6` (`mgo2_res_myscore`) returned all six known mode-page labels and
all three Snake labels byte-identical, which is what licensed trusting it for two new ones.

**One trap, recorded because it looks plausible when wrong:** strings start at **17943**, not at the
last `1ab3b6` header — twelve later headers belong to other sub-groups. Getting that wrong shifts
every label by twelve files and the result still reads like a sensible list.

### Highest-leverage addresses

| address | why |
| --- | --- |
| `0xD3DB1C` | the `0x4107` parser: a flat run of 73 reads into `T+3768+i*4`, stride 292. Slot ↔ memory index falls straight out |
| `0x917F34`-`0x918B80` | the DETAIL row switch, keyed on a 24-bit resource hash from the 36-entry display list at `0xE13BDC` — a hash→slot table handed over in one function |
| `0x91722C`-`0x9174AC` | the mode-page dispatcher; each arm loads its label as a string literal |

### Four documented claims corrected

1. **`0x4105` wire mode index 6 is TEAM SNEAKING and does have a page.** The schema said "6 HIDDEN
   (no page of its own)". Wire index ≠ memory row: eight wire records land on memory rows
   0,1,2,3,4,5,7,11. The old note's arithmetic was right; only the identity was wrong.
2. **"Text Chase Uses" was a transcription error** for "Text Chat Uses".
3. **Slot 30 is provably not a Rescue stat** — the Rescue arm reads 3876/3880/3888 and steps over
   3884.
4. **`0x4105` col 15's "post-game/ranking views" candidates are unsupported** — nothing outside two
   known ranges addresses that grid at all.

### Flagged, not chased

The only readers of the `0x4107` store are the two Personal Stats screens — **nothing in the
title/medal evaluation reads it.** That sits awkwardly beside `OBSERVED.md`'s "titles and awards are
computed by the client from the stat values themselves", which may derive from `0x4103` alone.
Deserves its own argued check rather than a note in a batch report.
