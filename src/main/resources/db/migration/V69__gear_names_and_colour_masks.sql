-- Gear item names and legal colour masks, read from the disc and the client's own catalogue.
--
-- Until now gear_item held ordinals and ids and nothing else, so every question about gear was a
-- question about numbers. These two columns make the table readable and make the colour mask
-- mean something.
--
-- NAMES [DISC]. The client resolves each item's label as GetString(groupHash, ordinal) via
-- 0x240708, where the ordinal is the item's index within its category and the group hash comes
-- from the 9-arm category table at 0x9270AC: head 0x37DC7F, upper 0xD14C79, chest 0xAD223A,
-- waist 0xE9B23B, hands 0x37CE1F, feet 0x37064F, accessories 0x3454C0 (arms 7 and 8 share it, so
-- accessory 1 and accessory 2 offer the identical list).
--
-- ID 22 IS DELIBERATELY LEFT UNNAMED. Its header at sid 1115 has the EN ordinal pointing at a JP
-- string, "trousers (provisional name)", with a stray "Aucun" in the adjacent slot -- the record is
-- mis-filled on the disc. And the lower-body arm at 0x927138 loads r28 = 0 instead of a group hash,
-- so the client never fetches a label for that category at all. Inventing one would be inventing
-- evidence.
--
-- COLOUR MASKS [ELF 0x10506BC]. The client resolves every swatch through a catalogue of 1044
-- 36-byte records {u32 item_id, u32 colour_slot, u32 colour_id}, scanned by 0x7E2D98 and
-- terminated by a negative first word at 0x105998C. colour_slot is a contiguous 0..n-1 run for
-- every one of the 71 catalogued ids without exception, so the legal mask is exactly (1 << n) - 1.
--
-- A miss in that catalogue SKIPS THE SWATCH BEFORE THE MASK IS CONSULTED (0x9276F0, 0x9254FC), so
-- bits above an item's n are unreadable. We have been sending 0xFFFFFFFF for every item; these
-- masks are what the client can actually use. Narrowing to them is behaviour-neutral.
--
-- The four zero masks (28, 68, 86, 102) are the "None" entries, absent from the catalogue
-- entirely. Note 46 -- hands' None -- IS catalogued with a single slot, so "None ids are absent"
-- is not the rule; only these four are.

ALTER TABLE public.gear_item ADD COLUMN IF NOT EXISTS name character varying(48);
ALTER TABLE public.gear_item ADD COLUMN IF NOT EXISTS colour_mask bigint NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.gear_item.name IS
    'Disc label, resolved via the category group hash. NULL where the disc record is mis-filled '
    '(id 22) -- not a gap in our knowledge but a defect in the data.';
COMMENT ON COLUMN public.gear_item.colour_mask IS
    'The colours this item actually has, (1 << n) - 1 from the client catalogue at 0x10506BC. '
    'Bits above n are unreadable: a swatch with no catalogue record is skipped before the '
    'per-character mask in chara_gear.colours is consulted.';

UPDATE public.gear_item AS g SET name = v.name, colour_mask = v.mask
FROM (VALUES
    ( 11, 'Tactical Jacket', 2097151),
    ( 12, 'Long Sleeve Shirt', 1023),
    ( 13, 'T-shirt', 1023),
    ( 22, null, 2097151),
    ( 28, 'None', 0),
    ( 29, 'Baseball Cap (Type A)', 2097151),
    ( 30, 'Helmet (Type A)', 2097151),
    ( 31, 'Baseball Cap (Type B)', 2097151),
    ( 32, 'Helmet (Type B)', 2097151),
    ( 33, 'Beret', 1023),
    ( 34, 'Ballistic Helmet (Type A)', 2097151),
    ( 35, 'Bush Hat', 2097151),
    ( 36, 'Ballistic Helmet (Type B)', 2097151),
    ( 37, 'Baseball Cap (Type C)', 2097151),
    ( 38, 'Fleece Cap', 1023),
    ( 46, 'None', 1),
    ( 47, 'Operator Gloves (A)', 1),
    ( 48, 'Operator Gloves (B)', 1),
    ( 49, 'Flight Gloves', 1),
    ( 50, 'Hard Knuckle Gloves', 1),
    ( 51, 'Half-Finger Gloves', 1),
    ( 57, 'Tactical Boots & Knee Guards (A)', 2097151),
    ( 58, 'Tactical Boots & Knee Guards (B)', 2097151),
    ( 59, 'Tactical Boots & Leg Armor', 2097151),
    ( 60, 'Tactical Boots & Knee Guards (C)', 2097151),
    ( 61, 'Tactical Boots & Knee Guards (D)', 2097151),
    ( 62, 'Tactical Boots', 2097151),
    ( 68, 'None', 0),
    ( 69, 'Tactical Armor (A)', 2097151),
    ( 70, 'Chest Harness (A)', 2097151),
    ( 71, 'Tactical Armor (B)', 2097151),
    ( 72, 'Tactical Vest (A)', 2097151),
    ( 73, 'H Harness (A)', 2097151),
    ( 74, 'H Harness (B)', 2097151),
    ( 75, 'Tactical Armor (C)', 2097151),
    ( 76, 'Chest Harness (B)', 2097151),
    ( 77, 'Load Bearing Vest (A)', 2097151),
    ( 78, 'Chest Harness (C)', 2097151),
    ( 79, 'Load Bearing Vest (B)', 2097151),
    ( 80, 'Chest Harness (D)', 2097151),
    ( 86, 'None', 0),
    ( 87, 'Leg Holster (A)', 2097151),
    ( 88, 'Leg Pouch (A)', 2097151),
    ( 89, 'Leg Holster (B)', 2097151),
    ( 90, 'Leg Armor', 2097151),
    ( 91, 'Leg Holster (C)', 2097151),
    ( 92, 'Dump Pouch (A)', 2097151),
    ( 93, 'Dump Pouch (B)', 2097151),
    ( 94, 'Leg Pouch (B)', 2097151),
    ( 95, 'Leg Pouch (C)', 2097151),
    ( 96, 'Leg Holster (D)', 2097151),
    ( 97, 'Leg Pouch (D)', 2097151),
    (102, 'None', 0),
    (103, 'Goggles', 63),
    (104, 'Headset (A)', 1023),
    (105, 'Balaclava', 255),
    (106, 'Eye Wear (A)', 31),
    (107, 'Eye Wear (B)', 31),
    (108, 'Headset (B)', 1023),
    (109, 'Half Mask', 255),
    (110, 'Scarf', 16777215),
    (111, 'Helmet Liner', 255),
    (112, 'Full Head Gear Set', 1),
    (113, 'Shemagh Scarf', 31),
    (114, 'Johnny''s Eyewear', 1),
    (115, 'Liquid''s Eyewear', 1),
    (116, 'Otacon''s Glasses', 1)
) AS v(item_id, name, mask)
WHERE g.item_id = v.item_id;
