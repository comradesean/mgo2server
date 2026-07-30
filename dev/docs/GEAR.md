# Gear: items, colours, and the two gates

Everything the server controls about Personal Data -> Appearance Settings. Written down because the
derivation was expensive and none of it is recoverable from the code alone: the item names are on
the disc, the colour vocabulary is in a client table, and the mapping between a mask bit and a
colour is **per item**.

## The two gates, and they are both ours

Ownership and colour are the only things the server decides here. Both were briefly recorded as
"gear has no server-side gate", which was wrong — see `OBSERVED.md`.

| gate | wire | client |
| --- | --- | --- |
| **item ownership** | `0x4124` / `0x4133` record `+8` | `0x927350`. An item with no record is **never appended** to the wardrobe list |
| **colour availability** | same record `+12`, a `u32` mask | `0x925538` / `0x92772C`, `mask & (1 << slot)` per swatch |

Confirmed live 2026-07-30 by stripping a character to one item: everything else vanished and the
one item showed a single swatch.

**Face, gender, voice, pitch and face paint are NOT on this screen** — they are creation-only
(`0x3101`), stored and echoed with no validation. There is nothing to gate.

## Packet shape

```
u32 count
count x { u8 item_id, u32 colour_mask }      5 bytes each
16    x { u8 item_id, u8 bit_index }         32 bytes, see below
```

`0x4124` (connect burst) and `0x4133` (reply to `0x4132`) carry the identical structure into the
**same** client table at `charTable + 9888 + id*12`, so **they must agree** — whichever arrives last
wins. Both are written by `LoadoutWriter.writeGear`.

The 32-byte tail is **not a terminator and grants nothing**: a pair is ORed into record `+16` only
if the bit is already set in `+12`, and `+16` drives a wardrobe highlight. Unused slots are `0xff`,
which the parser skips because item 255 exceeds its 128-entry bound. See `gear_colour_highlight`.

## Categories

The wardrobe enumerates fixed `{base, count}` windows from a 9-arm table at `0x9270AC`. **67 ids,
maximum 116** — we hold 122 in `gear_item`, so 55 are phantom (`POST_LAUNCH.md`).

**The empty-category fallback matters.** A category with nothing owned does **not** render empty:
`0x92751C`-`0x927568` force-equips the category's **base id** and draws one colourless row. Observed
live — emptying upper body and feet produced ids 11 and 57. It **writes the equipped byte**, so a
character left stripped who then commits an outfit persists those ids over what they were wearing.

Five ids are hardcoded always-available at `0x92735C`-`0x927384`: **28, 46, 68, 86, 102** — the
"None" entry of every category that has one. Granting them is a no-op. Upper body, lower body and
feet have no None, which is why they hit the fallback instead.

## Colour: a bit is a PER-ITEM SLOT

The single most important thing here, and the one that makes a global colour bitmask impossible.

The client's catalogue at **`0x10506BC`** (1044 records of 36 bytes, `{u32 item_id, u32 slot,
u32 colour_name_ordinal}`, negative-terminated at `0x105998C`, scanned by `0x7E2D98`) maps each
item's slots to colour NAMES. The mask indexes **`slot`**; the name is a separate field reaching 35,
which a 32-bit mask could not express anyway.

So **bit 0 is Auscam Desert on item 29, Black on item 33, and Orange on item 103.**

A slot with no catalogue record is skipped **before** the mask is read, so bits above an item's
count are unreadable — which is why the old `0xFFFFFFFF` was harmless and meaningless at once.

### Slot -> colour-name ordinal, by family

Every item's slots are a contiguous `0..n-1` run, so the fully-unlocked mask is `(1 << n) - 1`.

| family | n | slots map to ordinals | items |
| --- | --- | --- | --- |
| camo 21 | 21 | `1..21` (slot + 1) | 11, 22, 29-32, 34-37, 57-62, 69-80, 87-97 |
| solid 10 | 10 | `15..24` (slot + 15) | 12, 13, 33, 38, 104, 108 |
| eight | 8 | `15,16,17,19,20,21,23,24` — **skips Green and Maroon** | 105, 109, 111 |
| lens 6 | 6 | `30..35` | 103 |
| lens 5 | 5 | `30..34` | 106, 107 |
| scarf 5 | 5 | `25..29` | 113 |
| single | 1 | `0` (the null name) | 46-51, 112, 114-116 |
| absent | — | no records at all | 28, 68, 86, 102 |

The widest item is **110 (Scarf) at 24 slots**; nothing exceeds it, so bits 24-31 are dead
everywhere.

### Colour-name ordinals

```
 0 (none)          9 Tree Bark       18 Green          27 Gray *
 1 Auscam Desert  10 Rain Drop       19 Khaki          28 Blue *
 2 Choco Chip     11 Marpat          20 Navy Blue      29 Black *
 3 DPM            12 New JGSDF       21 Sage Green     30 Black
 4 Desert Tiger   13 Old Rhodesian   22 Maroon         31 Yellow
 5 Leaf           14 Russian Flora   23 Slate Gray     32 Rose
 6 Snow           15 Black           24 Dark Slate Gray 33 Orange
 7 Splitter       16 Olive Drab      25 Brown *        34 Brown
 8 Tiger Stripe   17 Coyote Brown    26 Green *        35 Clear
```

**Confidence is not uniform.**

- **0-24: solid.** Two independent extractions agree exactly.
- **25-29 (marked `*`): DISPUTED.** One reading gives `Brown, Green, Gray, Blue, Black`, another
  `Brown, Gray, Blue, Yellow, Rose`. Only item 113 (Shemagh Scarf) uses them, and nothing has
  forced the question. **Re-derive before relying on these.**
- **30-35: confirmed live.** The operator asked for Goggles in *Black and Clear* and Eye Wear in
  *Black and Brown*; that is only satisfiable if 30 is Black, 34 Brown and 35 Clear. Tier-2
  observation settled a contested dump.

Names are the disc's, resolved as `GetString(groupHash, ordinal)` via `0x240708`.

### Worked example

Granting **Black, Olive Drab, Coyote Brown, Khaki, Sage Green** — the same five colours — produces
three different masks:

```
21-slot camo item   ordinals 15,16,17,19,21 -> slots 14,15,16,18,20 -> 0x15C000
10-slot solid item  ordinals 15,16,17,19,21 -> slots  0, 1, 2, 4, 6 -> 0x000057
8-slot item         ordinals 15,16,17,19,21 -> slots  0, 1, 2, 3, 5 -> 0x00002F
```

The 8-slot row differs because its ordinal list skips Green, shifting everything after it.

## The starter set

`starter_gear` (V70) is what a new character owns, and every existing character was brought to it.
**Operator policy, not protocol** — nothing in the binary requires any particular set; the client
renders whatever the two writers agree on. Editing it is an `UPDATE`, no rebuild:

```sql
update starter_gear set colours = <mask> where item_id = <id>;
insert into starter_gear (item_id, colours) values (<id>, <mask>);
delete from starter_gear where item_id = <id>;
```

That changes new characters only. To change existing ones, write `chara_gear` directly. Unlocking
everything again, if it is ever wanted, is one statement:

```sql
insert into chara_gear (chara_id, item_id, colours)
select c.id, gi.item_id, gi.colour_mask from chara c cross join gear_item gi
on conflict (chara_id, item_id) do update set colours = excluded.colours;
```

Note `gi.colour_mask`, not `0xFFFFFFFF`: the per-item legal mask is the honest "everything".

## Item tables

`ord` is the index within the category, which is what resolves the name and what the empty-category
fallback renders. "legal colours" is the client's own maximum for that item; "starter" is what we
currently grant.

### HEAD — ids 28-38, name group `0x37DC7F`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 28 | 0 | None | `0x000000` | — |
| 29 | 1 | Baseball Cap (Type A) | `0x1FFFFF` | — |
| 30 | 2 | Helmet (Type A) | `0x1FFFFF` | `0x15C000` |
| 31 | 3 | Baseball Cap (Type B) | `0x1FFFFF` | — |
| 32 | 4 | Helmet (Type B) | `0x1FFFFF` | `0x15C000` |
| 33 | 5 | Beret | `0x0003FF` | — |
| 34 | 6 | Ballistic Helmet (Type A) | `0x1FFFFF` | `0x15C000` |
| 35 | 7 | Bush Hat | `0x1FFFFF` | — |
| 36 | 8 | Ballistic Helmet (Type B) | `0x1FFFFF` | — |
| 37 | 9 | Baseball Cap (Type C) | `0x1FFFFF` | `0x15C000` |
| 38 | 10 | Fleece Cap | `0x0003FF` | `0x000057` |

### UPPER BODY — ids 11-13, name group `0xD14C79`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 11 | 0 | Tactical Jacket | `0x1FFFFF` | `0x15C000` |
| 12 | 1 | Long Sleeve Shirt | `0x0003FF` | `0x000057` |
| 13 | 2 | T-shirt | `0x0003FF` | `0x000057` |

### LOWER BODY — ids 22, name group `(zero — no label)`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 22 | 0 | (unnamed on disc) | `0x1FFFFF` | `0x15C000` |

### CHEST — ids 68-80, name group `0xAD223A`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 68 | 0 | None | `0x000000` | — |
| 69 | 1 | Tactical Armor (A) | `0x1FFFFF` | `0x15C000` |
| 70 | 2 | Chest Harness (A) | `0x1FFFFF` | `0x15C000` |
| 71 | 3 | Tactical Armor (B) | `0x1FFFFF` | — |
| 72 | 4 | Tactical Vest (A) | `0x1FFFFF` | `0x15C000` |
| 73 | 5 | H Harness (A) | `0x1FFFFF` | `0x15C000` |
| 74 | 6 | H Harness (B) | `0x1FFFFF` | — |
| 75 | 7 | Tactical Armor (C) | `0x1FFFFF` | — |
| 76 | 8 | Chest Harness (B) | `0x1FFFFF` | — |
| 77 | 9 | Load Bearing Vest (A) | `0x1FFFFF` | `0x15C000` |
| 78 | 10 | Chest Harness (C) | `0x1FFFFF` | — |
| 79 | 11 | Load Bearing Vest (B) | `0x1FFFFF` | — |
| 80 | 12 | Chest Harness (D) | `0x1FFFFF` | — |

### WAIST — ids 86-97, name group `0xE9B23B`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 86 | 0 | None | `0x000000` | — |
| 87 | 1 | Leg Holster (A) | `0x1FFFFF` | `0x15C000` |
| 88 | 2 | Leg Pouch (A) | `0x1FFFFF` | `0x15C000` |
| 89 | 3 | Leg Holster (B) | `0x1FFFFF` | — |
| 90 | 4 | Leg Armor | `0x1FFFFF` | — |
| 91 | 5 | Leg Holster (C) | `0x1FFFFF` | `0x15C000` |
| 92 | 6 | Dump Pouch (A) | `0x1FFFFF` | `0x15C000` |
| 93 | 7 | Dump Pouch (B) | `0x1FFFFF` | — |
| 94 | 8 | Leg Pouch (B) | `0x1FFFFF` | — |
| 95 | 9 | Leg Pouch (C) | `0x1FFFFF` | `0x15C000` |
| 96 | 10 | Leg Holster (D) | `0x1FFFFF` | — |
| 97 | 11 | Leg Pouch (D) | `0x1FFFFF` | — |

### HANDS — ids 46-51, name group `0x37CE1F`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 46 | 0 | None | `0x000001` | — |
| 47 | 1 | Operator Gloves (A) | `0x000001` | `0x000001` |
| 48 | 2 | Operator Gloves (B) | `0x000001` | — |
| 49 | 3 | Flight Gloves | `0x000001` | `0x000001` |
| 50 | 4 | Hard Knuckle Gloves | `0x000001` | — |
| 51 | 5 | Half-Finger Gloves | `0x000001` | — |

### FEET — ids 57-62, name group `0x37064F`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 57 | 0 | Tactical Boots & Knee Guards (A) | `0x1FFFFF` | `0x15C000` |
| 58 | 1 | Tactical Boots & Knee Guards (B) | `0x1FFFFF` | — |
| 59 | 2 | Tactical Boots & Leg Armor | `0x1FFFFF` | — |
| 60 | 3 | Tactical Boots & Knee Guards (C) | `0x1FFFFF` | — |
| 61 | 4 | Tactical Boots & Knee Guards (D) | `0x1FFFFF` | `0x15C000` |
| 62 | 5 | Tactical Boots | `0x1FFFFF` | — |

### ACCESSORIES — ids 102-116, name group `0x3454C0`

| id | ord | name | legal colours | starter |
| --- | --- | --- | --- | --- |
| 102 | 0 | None | `0x000000` | — |
| 103 | 1 | Goggles | `0x00003F` | `0x000021` |
| 104 | 2 | Headset (A) | `0x0003FF` | `0x000057` |
| 105 | 3 | Balaclava | `0x0000FF` | `0x00002F` |
| 106 | 4 | Eye Wear (A) | `0x00001F` | `0x000011` |
| 107 | 5 | Eye Wear (B) | `0x00001F` | — |
| 108 | 6 | Headset (B) | `0x0003FF` | — |
| 109 | 7 | Half Mask | `0x0000FF` | — |
| 110 | 8 | Scarf | `0xFFFFFF` | — |
| 111 | 9 | Helmet Liner | `0x0000FF` | `0x00002F` |
| 112 | 10 | Full Head Gear Set | `0x000001` | — |
| 113 | 11 | Shemagh Scarf | `0x00001F` | — |
| 114 | 12 | Johnny's Eyewear | `0x000001` | — |
| 115 | 13 | Liquid's Eyewear | `0x000001` | — |
| 116 | 14 | Otacon's Glasses | `0x000001` | — |

**Id 22 has no name** and that is not a gap in our knowledge: the disc header points its English
ordinal at a Japanese string reading *"trousers (provisional name)"*, with a stray `Aucun`
alongside. The record is mis-filled on the disc, and the lower-body arm loads a zero group hash so
the client never asks for it.

**Name confidence:** head and accessories are anchored (the ELF special-cases ids 35 and 38, landing
on the only two soft crushable hats; three colour-set signatures group the accessories
semantically). Upper body and feet were confirmed by observing the fallback render ordinal 0.
**Hands, chest and waist remain ordering-derived** — counts match and colour signatures are
consistent, but the flat string dump's group boundaries are unreliable. The fallback trick would
settle each of them.
