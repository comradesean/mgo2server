-- Serving the personal-stats screens (0x4105 matrix, 0x4107 personal scores) from stored round
-- reports. Two parts: indexes the period queries need, and the weapon-tally table 0x43a2 has been
-- filling nothing since it was decoded.
--
-- No accumulator tables. Every stats surface still derives from round_report at query time
-- (BACKLOG, "Match/encounter history"); at this population materialization was rejected twice and
-- a chara_stats accumulator was already built and dropped as write-only.

-- Every stats query filters by character and, for the weekly period, by time. There was no index
-- on reported_at at all, though RankingService's month window has needed one since V33.
CREATE INDEX round_report_chara_time_idx ON public.round_report (chara_id, reported_at);

-- The 0x4105 matrix groups by rule per character; this covers both that and the per-mode period.
CREATE INDEX round_report_chara_rule_time_idx ON public.round_report (chara_id, rule, reported_at);

-- Per-weapon terminal-event tallies from 0x43a2, one packet per scoring player sent immediately
-- after that player's 0x4390 (dev/proto/mgo2_cmd_43a2.ksy). Feeds the weapon-specific lines of the
-- Personal Stats screen -- 0x4107 slot 64 Knife Kills at minimum, which cannot come from struct B
-- because struct B has only 58 slots.
--
-- game_id deliberately carries NO foreign key, exactly as round_report does: games are deleted at
-- teardown and these rows are history. chara_id keeps one without cascade so a deleted character's
-- tallies survive under the placeholder name.
CREATE TABLE public.round_weapon_tally (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    game_id     bigint      NOT NULL,
    chara_id    bigint      NOT NULL REFERENCES public.chara (id),
    weapon_id   smallint    NOT NULL,
    kills       smallint    NOT NULL DEFAULT 0,
    headshots   smallint    NOT NULL DEFAULT 0,
    faints      smallint    NOT NULL DEFAULT 0,
    reported_at timestamptz NOT NULL DEFAULT now()
);

-- Mirrors round_report's access pattern: by character, windowed by time.
CREATE INDEX round_weapon_tally_chara_time_idx
    ON public.round_weapon_tally (chara_id, reported_at);
