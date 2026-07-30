-- A character owns exactly what it chose at creation. Nothing else.
--
-- CORRECTS V70, which was wrong, and V44 before it which was wrong differently. The history:
--
--   before V44  every character was told it owned all 123 items in every colour, from a constant
--   V44         same, but from a table, so narrowing became possible
--   V70         a 28-item starter set with five colours each -- operator policy, but invented
--   V71         what the original actually did
--
-- On the original service a new character unlocked ONLY the items it picked during character
-- creation, each in ONLY the colour it picked. Everything else stayed locked, and the sole route
-- to more was a REWARD SYSTEM ADDED AFTER LAUNCH.
--
-- That last clause is what makes this a release-day question rather than a taste question. For v1
-- there is no unlock mechanism at all: what a character chooses at creation is what it has,
-- permanently. Serving anything more generous is serving post-launch content. See POST_LAUNCH.md.
--
-- Evidence tier: this is operator knowledge of the original service, not something readable from
-- our artifacts -- the client never checks, it renders whatever the two gear writers agree on. It
-- is recorded as the reason for the change rather than dressed up as an ELF finding.
--
-- THE COLOUR BYTE IS THE MASK'S BIT INDEX, which is what makes this expressible at all. Confirmed
-- from live rows: a 21-slot item stores 14 for Black (slot 14 -> colour-name ordinal 15) while a
-- 10-slot item stores 0 for the same colour. So a choice becomes `1 << colour` exactly.
--
-- EXISTING CHARACTERS ARE NARROWED TO WHAT THEY CURRENTLY WEAR, which is an approximation and
-- should be read as one. Their real creation choices are unrecoverable: V44 granted everything,
-- V70 replaced that with a 28-item set, and the empty-category fallback silently rewrote at least
-- one character's appearance to the category base ids in between. What they wear now is the
-- closest honest thing available, and it keeps every character legally dressed -- which matters,
-- because the fallback rewrites the outfit of anyone left wearing an item they do not own.
--
-- The five "None" ids (28, 46, 68, 86, 102) are skipped: hardcoded always-available at
-- 0x92735C-0x927384, so a row for them is a no-op in both directions. Lower body has no None, so
-- id 22 is granted whenever worn -- which is always, that category having exactly one item.

CREATE TEMPORARY TABLE worn_gear ON COMMIT DROP AS
SELECT chara_id, item_id, bit_or((1::bigint << (colour & 31)))::bigint AS colours
FROM (
    SELECT chara_id, head        AS item_id, head_color        AS colour FROM public.chara_appearance
    UNION ALL SELECT chara_id, upper,        upper_color        FROM public.chara_appearance
    UNION ALL SELECT chara_id, lower,        lower_color        FROM public.chara_appearance
    UNION ALL SELECT chara_id, chest,        chest_color        FROM public.chara_appearance
    UNION ALL SELECT chara_id, waist,        waist_color        FROM public.chara_appearance
    UNION ALL SELECT chara_id, hands,        hands_color        FROM public.chara_appearance
    UNION ALL SELECT chara_id, feet,         feet_color         FROM public.chara_appearance
    UNION ALL SELECT chara_id, accessory1,   accessory1_color   FROM public.chara_appearance
    UNION ALL SELECT chara_id, accessory2,   accessory2_color   FROM public.chara_appearance
) picks
WHERE item_id <> 0
  AND item_id NOT IN (28, 46, 68, 86, 102)
GROUP BY chara_id, item_id;

DELETE FROM public.chara_gear;

INSERT INTO public.chara_gear (chara_id, item_id, colours)
SELECT chara_id, item_id, colours FROM worn_gear;

-- starter_gear goes with it. Keeping a fixed starter table beside a creation-derived grant would
-- leave two competing answers to "what does a new character own", and the table's answer is the
-- wrong one. Unlocking more is a post-launch reward system we do not serve; when it is served, it
-- will write chara_gear rows, not a starter list.
DROP TABLE IF EXISTS public.starter_gear;
