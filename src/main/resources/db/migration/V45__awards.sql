-- Titles: the latched collection, plus the last-seen stamp one title needs.
--
-- Medals get no table on purpose. Every medal source is a career sum or maximum, so it only grows
-- and a medal cannot un-earn itself -- StatsService.medalBits derives the whole 16-byte field at
-- query time. Titles cannot work that way: their requirements are RATIOS, and a ratio falls. A
-- derived title would vanish the moment a player had a bad week, so the unlock is stored.

-- One row means this character has unlocked this title, exactly as chara_skill (V20) and
-- chara_gear (V44) mean ownership. Latching is then the database's job: the evaluator inserts
-- on conflict do nothing and never deletes.
CREATE TABLE public.chara_title (
    chara_id    bigint      NOT NULL REFERENCES public.chara (id) ON DELETE CASCADE,
    -- Position in the 22-bit mask at 0x4103 wire 563.
    --
    -- The upper bound is a real client limit, not tidiness: the title screen's popcount loop runs
    -- 23 iterations over a 22-entry table, so setting bit 22 or above over-counts the owned-title
    -- total and corrupts the scrollbar. Better a failed INSERT than a corrupted screen.
    title_bit   smallint    NOT NULL CHECK (title_bit BETWEEN 0 AND 21),
    unlocked_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (chara_id, title_bit)
);

-- When this character was last seen logging in. TSUCHINOKO ("rarely plays") is the only award that
-- needs it -- its requirement is an absence of activity, which no gameplay row can express, because
-- not playing writes nothing.
--
-- It also makes 0x4103's two login-time fields servable; they have been zero because nothing
-- recorded a login. NULL means never seen since this column existed, which reads as "no data"
-- rather than "logged in at the epoch".
ALTER TABLE public.chara ADD COLUMN last_seen_at timestamptz;
