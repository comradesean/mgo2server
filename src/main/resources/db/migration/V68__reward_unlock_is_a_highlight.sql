-- reward_unlock cannot unlock anything. Renaming it before the name misleads someone.
--
-- V67 added reward_unlock on the premise that the sixteen {u8 item_id, u8 bit_index} pairs at the
-- end of the 0x4124 / 0x4133 gear payload were a colour-granting channel. **They are not**, and the
-- read of the parser that settled it is unambiguous:
--
--     0xD3CFBC..0xD3CFE4 -- for each pair, if bit `bit_index` is ALREADY SET in the mask at
--     record+12, OR it into record+16.
--
-- So the pairs can only ever produce a SUBSET of the mask we already send in the record. They
-- cannot add a colour, and a pair naming a bit that is clear in +12 does nothing at all.
--
-- What +16 actually drives: it is read at 0x92740C and 0x927744 on a secondary path -- a
-- highlight / "new" marker in the wardrobe, not availability. Availability is +12 (per colour,
-- 0x925538 and 0x92772C) and +8 (item ownership, 0x927350).
--
-- V67 was harmless in effect -- the table is empty, so every slot still gets the 0xff filler and
-- the payload is byte-identical to before it existed. But a table called "reward_unlock" sitting
-- next to a real grant mechanism is precisely the kind of name that gets trusted later. This
-- project has spent the day undoing labels that outran their evidence; this one is caught while it
-- is still empty and costs nothing to correct.
--
-- To actually grant a colour, set the bit in chara_gear.colours. To grant an item, insert the
-- chara_gear row. Those are the two real gates.

ALTER TABLE public.reward_unlock RENAME TO gear_colour_highlight;

ALTER INDEX public.reward_unlock_chara_idx RENAME TO gear_colour_highlight_chara_idx;

ALTER TABLE public.gear_colour_highlight
    RENAME CONSTRAINT reward_unlock_item_range TO gear_colour_highlight_item_range;
ALTER TABLE public.gear_colour_highlight
    RENAME CONSTRAINT reward_unlock_bit_range TO gear_colour_highlight_bit_range;

COMMENT ON TABLE public.gear_colour_highlight IS
    'Fills the sixteen {item_id, bit_index} pairs at the end of the 0x4124 / 0x4133 gear payload. '
    'These do NOT grant anything: the parser ORs a pair into record+16 only if the bit is already '
    'set in the colour mask at record+12, and +16 drives a wardrobe highlight, not availability. '
    'Grant colours via chara_gear.colours and items via chara_gear rows. Empty by default, which '
    'leaves the 0xff filler the parser skips.';
