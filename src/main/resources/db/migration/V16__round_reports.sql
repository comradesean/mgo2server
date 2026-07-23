-- One row per 0x4390 end-of-round stat report — the raw per-round, per-player record, kept
-- instead of being folded into accumulators (BACKLOG, "Match/encounter history"). Every stats
-- and history surface derives from this table at query time: lifetime totals are sums, period
-- views are windows over reported_at, per-mode views join the game's settings, and the
-- met-players history (0x4680) is a self-join on game_id. Single write path, no derived state.
--
-- Column names follow the 0x4390 frame map (PROTOCOL.md): slots confirmed by the 2026-07-22
-- capture are named; unlabelled counters are named by wire offset rather than guessed. The
-- struct-B detail block is 58 unlabelled s16s — stored as a decoded, element-addressable array
-- (not a blob) until its slots earn names.
--
-- game_id has no foreign key on purpose: game rows are deleted at teardown, and reports are
-- history. chara_id keeps one because characters are soft-deleted, so the row always exists;
-- a deleted character shows its placeholder name in others' histories rather than vanishing.
CREATE TABLE public.round_report
(
    id bigserial PRIMARY KEY,
    game_id bigint NOT NULL,
    host_chara_id bigint NOT NULL,
    chara_id bigint NOT NULL,
    reported_at timestamptz NOT NULL DEFAULT now(),
    flag_0x04 smallint NOT NULL DEFAULT 0,
    kills smallint NOT NULL DEFAULT 0,
    deaths smallint NOT NULL DEFAULT 0,
    counter_0x09 smallint NOT NULL DEFAULT 0,
    -- Round score can be negative (deaths and penalties outweigh kills); signed on purpose.
    score smallint NOT NULL DEFAULT 0,
    stuns smallint NOT NULL DEFAULT 0,
    counter_0x0f smallint NOT NULL DEFAULT 0,
    headshots smallint NOT NULL DEFAULT 0,
    headshot_deaths smallint NOT NULL DEFAULT 0,
    counter_0x15 smallint NOT NULL DEFAULT 0,
    counter_0x17 smallint NOT NULL DEFAULT 0,
    counter_0x19 smallint NOT NULL DEFAULT 0,
    counter_0x1b smallint NOT NULL DEFAULT 0,
    rounds_played smallint NOT NULL DEFAULT 0,
    counter_0x1f smallint NOT NULL DEFAULT 0,
    counter_0x21 smallint NOT NULL DEFAULT 0,
    seconds_in_game bigint NOT NULL DEFAULT 0,
    experience_total bigint NOT NULL DEFAULT 0,
    detail_present bigint NOT NULL DEFAULT 0,
    detail_counters smallint[] NOT NULL DEFAULT '{}',
    trailing_word bigint NOT NULL DEFAULT 0,
    aborted boolean NOT NULL DEFAULT false,
    CONSTRAINT round_report_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id)
);

-- The met-players self-join enters by viewer and pairs by game.
CREATE INDEX round_report_chara_idx ON public.round_report (chara_id);
CREATE INDEX round_report_game_idx ON public.round_report (game_id);

-- Write-only lifetime accumulator, superseded: nothing ever read it, and its two rows were one
-- test round from the 2026-07-22 labelling capture, recorded in OBSERVED.md. Totals are now
-- sums over round_report.
DROP TABLE IF EXISTS public.chara_stats;
