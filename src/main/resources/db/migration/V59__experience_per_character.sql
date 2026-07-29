-- Experience moves from the account to the character, where the wire has always had it.
--
-- It was stored as two pools on the account: main_exp for the account's main character and
-- alt_exp for everyone else. The justification in V4 was "which is what the original modelled",
-- with no source behind it, and it is contradicted by the protocol -- 0x4101's character-list
-- entry carries its own experience field at wire 0x01c, one per character
-- (dev/proto/outbound/mgo2_cmd_4101_s2c.ksy). The client asks per character; only our storage
-- pooled it.
--
-- The pooling is not academic. Character slots are bounded 1..4, so an account with more than one
-- non-main character had them SHARE alt_exp: play on one, and the other's level moved with it.
-- Live at the time of writing, account 122345677 held charas 1 (main), 4 and 5 -- 4 and 5 shared a
-- pool. The same accounts also accumulated orphaned pools: account 200000008 carried alt_exp = 500
-- with no alt character at all, left behind by a deletion.

ALTER TABLE public.chara ADD COLUMN IF NOT EXISTS experience integer NOT NULL DEFAULT 0;

-- Backfill BEFORE dropping anything. Each character takes the pool it was actually reading, so
-- every level on screen is unchanged by this migration. Where two alts shared a pool they both
-- take its value: that over-credits the one that did not earn it, but the alternative is choosing
-- a loser, and the pool cannot be split after the fact -- the information was never recorded.
UPDATE public.chara c
SET experience = COALESCE(
        CASE WHEN a.main_chara_id = c.id THEN a.main_exp ELSE a.alt_exp END, 0)
FROM public.account a
WHERE a.id = c.account_id;

-- A u16 on the wire (0x4390 reads experience as a zero-extended u16), so values above 65535
-- cannot round-trip. The constraint states the ceiling rather than letting it be discovered by a
-- character silently wrapping.
ALTER TABLE public.chara
    ADD CONSTRAINT chara_experience_range CHECK (experience BETWEEN 0 AND 65535);

ALTER TABLE public.account DROP COLUMN IF EXISTS main_exp;
ALTER TABLE public.account DROP COLUMN IF EXISTS alt_exp;
