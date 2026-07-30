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
| `0x4107` | s2c | 76 | **37** | stats | open |
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
| `0x4105` | s2c | 21 | **2** | stats | open |
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
