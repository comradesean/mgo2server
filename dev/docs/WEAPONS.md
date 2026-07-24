# The weapon master table (ELF-extracted 2026-07-23)

Static table in `MGO2.elf` at vaddr `0x1035834` (file `0x1025834`), stride `0x2C` (11 BE u32
columns), **141 records, 0-based — the array position IS the weapon id**. Columns: w0 =
display-name pointer; w1 low u16 = category bitmask (1 knife, 2 pistol, 4 SMG, 8 AR, 0x10
LMG, 0x20 shotgun, 0x40 sniper, 0x80 GL, 0x100 launcher, 0x200 grenade, 0x400 placeable,
0x800 attachment, 0x1000 shield); w2 = flags|id with **bit 0x8000 = non-lethal** (ST KNIFE,
MOSIN N, SLEEP CLAYMORE, SLEEP C4); w3–w8 numeric params (unlabelled); w9 model/hash; w10 ~0.
A separate ammo-name table (`WP_Bul*`, 67 entries, stride 8) lives at vaddr `0x1037d80`.

Anchored live via the `0x43a2` round-end tally list (slot = weapon id): 1 = ST KNIFE (knife
kill), 43 = MOSIN N (tranq darts; non-lethal flag agrees). Ids 0–126 are the tally-eligible
damage sources; 127–140 are boss/environment sources.

**Name-column caveat (2026-07-24):** these are the ELF table's strings — plausibly internal
development names, NOT verified as what the client UI renders. The user plays the id-2 tranq
pistol as "the Mk.2" while the table says RUGER; the UI's own names may live in localized
resources (as the medal names do). Ids and behaviours are the confirmed layer; treat every
name below as [INFERRED] until read off the live UI. UI-correspondence verified so far:
AK102 (id 25, read off the screen). Diverging or unverified: everything else.

Tally triple **confirmed** 2026-07-24: per-weapon {kills, headshots, faints} — a deliberate
one-headshot-one-bodyshot AK102 round produced {2,1,0}, splitting the fields. The Mosin
dart-to-head counts as a weapon-level headshot even though the scoreboard headshot counter
(lethal bullets only) refuses it. Anchors exact: ST KNIFE 1, **RUGER 2 = the Mk.2 tranq
pistol** (one dart-faint on an awake target → {2: 0,0,1}; 30 darts into an already-fainted
body → no entry, so the field counts faints CAUSED), AK102 25, MOSIN N 43. CQC knockouts
never appear in this list at all (id 112 stays silent) — melee stuns live only in the
scoreboard stun pair.

| id | name | id | name | id | name |
|---|---|---|---|---|---|
| 0 | NONE | 47 | XM25 | 94 | REX LASER |
| 1 | ST KNIFE | 48 | STINGER | 95 | Nighthawk |
| 2 | RUGER | 49 | JAVELIN | 96 | AK KNIFE |
| 3 | OPERATOR | 50 | RPG7 | 97 | Throw Knife |
| 4 | SOCOM | 51 | M72A3 | 98 | Throw Machete |
| 5 | PMM | 52 | GRENADE | 99 | WP_ParaCord |
| 6 | FIVESEVEN | 53 | WP G | 100 | XM8 Short |
| 7 | SIG GSR | 54 | STUN G | 101 | XM8 Long |
| 8 | D EAGLE | 55 | CHAFF G | 102 | XM8 Jona |
| 9 | D EAGLE L | 56 | SMOKE G | 103 | MORTARBOMB |
| 10 | THOR | 57 | SMOKE G.(R) | 104 | M2 |
| 11 | M1911A1 | 58 | SMOKE G.(G) | 105 | CORE |
| 12 | RACE GUN | 59 | SMOKE G.(Y) | 106 | CLAYMORE |
| 13 | GUN DEL SOL | 60 | SMOKE G.(P) | 107 | KICK |
| 14 | PSS | 61 | PETRO BOMB | 108 | PUNCH |
| 15 | GLOCK | 62 | MAGAZINE | 109 | PUNCH |
| 16 | T17 | 63 | EMP GRENADE | 110 | STOMP |
| 17 | MP7 | 64 | CLAYMORE | 111 | ROLLING |
| 18 | MP5 | 65 | SLEEP CLAYMORE | 112 | CQC |
| 19 | INGRAM | 66 | C4 | 113 | ROLLING DRUM |
| 20 | P90 | 67 | SLEEP C4 | 114 | MK2 SPARK |
| 21 | BIZON | 68 | BASE BUSTER | 115 | DOOR ATTACK |
| 22 | PATRIOT | 69 | BOOK | 116 | DRUMCAN |
| 23 | SKORPION | 70 | AFFECT BOOK | 117 | GROUND FIRE |
| 24 | M4 | 71 | DOLL | 118 | GROUND FIRE |
| 25 | AK102 | 72 | DOLL | 119 | ANIMAL STRONG |
| 26 | G3A3 | 73 | SHIELD | 120 | C4 TRIGGER |
| 27 | AN94 | 74 | SBS | 121 | SLEEP C4 TRIGGER |
| 28 | FAL | 75 | XM320 | 122 | INJECTION |
| 29 | TANE | 76 | GP30 | 123 | CRITICAL KNIFE |
| 30 | MK17 | 77 | SURPRESSOR | 124 | EXPLOSION SMALL |
| 31 | XM8 | 78 | SURPRESSOR | 125 | EXPLOSION MIDDLE |
| 32 | LMG | 79 | SURPRESSOR | 126 | EXPLOSION LARGE |
| 33 | HK21E | 80 | SURPRESSOR | 127 | TORNADO |
| 34 | PK | 81 | SURPRESSOR | 128 | GEKKOVULCAN |
| 35 | M60E4 | 82 | SURPRESSOR | 129 | GEKKOMISSILE |
| 36 | SBS | 83 | SURPRESSOR | 130 | GK KICK |
| 37 | M870 | 84 | SCOPE | 131 | GK STOMP |
| 38 | SAIGA | 85 | DOTSIGHT | 132 | REX KICK |
| 39 | VSS | 86 | MP7 DOTSIGHT | 133 | REX BODY |
| 40 | M82A2 | 87 | LIGHT | 134 | RAY VULCAN |
| 41 | DSR1 | 88 | LASERSIGHT | 135 | RAY MISSILE |
| 42 | M14EBR | 89 | LIGHT | 136 | RAY CUTTER |
| 43 | MOSIN N | 90 | GRIP A | 137 | RAY KICK |
| 44 | DRAGNOV | 91 | GRIP B | 138 | RAY BODY |
| 45 | RAILGUN | 92 | REX VULCAN | 139 | BINOCULAR |
| 46 | MGL-140 | 93 | REX MISSILE | 140 | ENVG |
