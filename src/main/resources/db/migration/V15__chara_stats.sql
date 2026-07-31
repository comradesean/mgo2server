-- Lifetime scoreboard stats per character, accumulated from the host's end-of-round reports
-- (0x4390). Each report is one round for one player; these columns sum across every round played.
--
-- The 0x4390 stat-struct offsets were labelled by a live capture 2026-07-22 (OBSERVED.md, "The
-- 0x4390 scoreboard"): a two-round TDM match whose reported totals matched these slots exactly for
-- both players. Only the confirmed slots are stored; the report's other counters (hacking, assist,
-- wake, "other", and the whole 0x2f detail block) were zero that match and remain unlabelled.
CREATE TABLE IF NOT EXISTS public.chara_stats
(
    chara_id bigint NOT NULL,
    kills bigint NOT NULL DEFAULT 0,
    deaths bigint NOT NULL DEFAULT 0,
    -- Round score can be negative (deaths and penalties outweigh kills), so the lifetime sum can
    -- dip; signed on purpose.
    score bigint NOT NULL DEFAULT 0,
    headshots bigint NOT NULL DEFAULT 0,
    headshot_deaths bigint NOT NULL DEFAULT 0,
    stuns bigint NOT NULL DEFAULT 0,
    rounds bigint NOT NULL DEFAULT 0,
    CONSTRAINT chara_stats_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_stats_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);
