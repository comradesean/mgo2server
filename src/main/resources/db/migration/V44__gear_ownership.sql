-- Gear ownership, so that unlockables become expressible.
--
-- Until now every character was told it owned all 123 items in every colour, from a constant
-- array in LoadoutWriter. That is why 0x4133 sending an empty table wiped everyone's gear (fixed
-- 46629a3): there was no source of truth to read back, only a hardcoded list one writer used and
-- the other did not. This is that source of truth.
--
-- Shaped after V20's skill/chara_skill pair, which answers the same question for skills: a
-- catalogue table of what exists, and a per-character table where A ROW MEANS "THIS CHARACTER OWNS
-- THIS". No row means the item is omitted from 0x4124 and 0x4133, and the client's memset leaves
-- that slot zeroed -- which is what makes locking expressible at all.
--
-- BEHAVIOUR-NEUTRAL ON PURPOSE. Every existing character is backfilled with every item in every
-- colour, so the wire is byte-identical to what it was before this migration. Restricting a
-- character to a starter set is now a DELETE, not a code change. Do that deliberately, as policy,
-- not as a side effect of this migration.

-- The catalogue, in WIRE ORDER. Keyed on ordinal rather than item id because item id is not
-- unique: 0x86 appears twice (123 rows, 122 distinct ids). PROTOCOL.md flags that as
-- possibly a transcription slip in this project rather than a faithful copy, and nobody has
-- checked. Keying on item id would silently drop the duplicate, taking 0x4124 from its known-good
-- 651 bytes (4 + 123*5 + 32) to 646 -- a wire change on an unverified theory. So the duplicate
-- is preserved exactly, and the question stays open instead of being answered by a schema choice.
CREATE TABLE IF NOT EXISTS public.gear_item
(
    ordinal smallint NOT NULL,
    item_id smallint NOT NULL,
    CONSTRAINT gear_item_pkey PRIMARY KEY (ordinal),
    CONSTRAINT gear_item_id_range CHECK (item_id BETWEEN 0 AND 255)
);

INSERT INTO public.gear_item (ordinal, item_id) VALUES
    (  0,   4),
    (  1,  11),
    (  2,  12),
    (  3,  13),
    (  4,  14),
    (  5,  15),
    (  6,  16),
    (  7,  17),
    (  8,  18),
    (  9,  19),
    ( 10,  22),
    ( 11,  28),
    ( 12,  29),
    ( 13,  30),
    ( 14,  31),
    ( 15,  32),
    ( 16,  33),
    ( 17,  34),
    ( 18,  35),
    ( 19,  36),
    ( 20,  37),
    ( 21,  38),
    ( 22,  40),
    ( 23,  41),
    ( 24,  42),
    ( 25,  43),
    ( 26,  44),
    ( 27,  46),
    ( 28,  47),
    ( 29,  48),
    ( 30,  49),
    ( 31,  50),
    ( 32,  51),
    ( 33,  52),
    ( 34,  53),
    ( 35,  57),
    ( 36,  58),
    ( 37,  59),
    ( 38,  60),
    ( 39,  61),
    ( 40,  62),
    ( 41,  63),
    ( 42,  64),
    ( 43,  68),
    ( 44,  69),
    ( 45,  70),
    ( 46,  71),
    ( 47,  72),
    ( 48,  73),
    ( 49,  74),
    ( 50,  75),
    ( 51,  76),
    ( 52,  77),
    ( 53,  78),
    ( 54,  79),
    ( 55,  80),
    ( 56,  81),
    ( 57,  82),
    ( 58,  83),
    ( 59,  86),
    ( 60,  87),
    ( 61,  88),
    ( 62,  89),
    ( 63,  90),
    ( 64,  91),
    ( 65,  92),
    ( 66,  93),
    ( 67,  94),
    ( 68,  95),
    ( 69,  96),
    ( 70,  97),
    ( 71,  98),
    ( 72,  99),
    ( 73, 100),
    ( 74, 102),
    ( 75, 103),
    ( 76, 104),
    ( 77, 105),
    ( 78, 106),
    ( 79, 107),
    ( 80, 108),
    ( 81, 109),
    ( 82, 110),
    ( 83, 111),
    ( 84, 112),
    ( 85, 113),
    ( 86, 114),
    ( 87, 115),
    ( 88, 116),
    ( 89, 117),
    ( 90, 118),
    ( 91, 119),
    ( 92, 128),
    ( 93, 129),
    ( 94, 130),
    ( 95, 131),
    ( 96, 132),
    ( 97, 133),
    ( 98, 134),
    ( 99, 134),
    (100, 135),
    (101, 136),
    (102, 137),
    (103, 138),
    (104, 139),
    (105, 140),
    (106, 141),
    (107, 142),
    (108, 143),
    (109, 160),
    (110, 161),
    (111, 162),
    (112, 176),
    (113, 192),
    (114, 193),
    (115, 194),
    (116, 195),
    (117, 196),
    (118, 240),
    (119, 241),
    (120, 242),
    (121, 243),
    (122, 244)
ON CONFLICT (ordinal) DO NOTHING;

-- What a character actually has.
--
-- Keyed on item id, not ordinal: ownership is a fact about an item, and the duplicate 0x86 is a
-- quirk of the wire order rather than two separate things to own. The writer emits one record per
-- CATALOGUE ROW, so a character owning 0x86 still gets both of its records and the payload stays
-- 651 bytes.
--
-- colours is the u32 colour mask 0x4124 carries per item. 4294967295 is every colour; a narrower
-- mask is how a partly-unlocked item is expressed. Stored as bigint because Postgres has no
-- unsigned 32-bit type.
CREATE TABLE IF NOT EXISTS public.chara_gear
(
    chara_id bigint   NOT NULL,
    item_id  smallint NOT NULL,
    colours  bigint   NOT NULL DEFAULT 4294967295,
    CONSTRAINT chara_gear_pkey PRIMARY KEY (chara_id, item_id),
    CONSTRAINT chara_gear_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_gear_colours_range CHECK (colours BETWEEN 0 AND 4294967295)
);

-- Backfill: every existing character keeps exactly what it had. DISTINCT because of 0x86.
INSERT INTO public.chara_gear (chara_id, item_id, colours)
SELECT c.id, g.item_id, 4294967295
FROM public.chara c
CROSS JOIN (SELECT DISTINCT item_id FROM public.gear_item) g
ON CONFLICT (chara_id, item_id) DO NOTHING;
