-- Host rating votes, from 0x43c4.
--
-- IDENTIFIED 2026-07-28 from a live vote plus a constraint already in the docs. The client sends
-- a bare u32 and the ELF aborts on anything outside 1..5 (0xD40E44) -- a range that rules out the
-- character-id reading the rest of the 0x43xx family invites -- and an operator who gave a host
-- five stars produced exactly `43c4 = 00000005`, sent immediately after the game-info screen and
-- before quitting. Until now the command had no handler and the vote was dropped with a WARN.
--
-- This is why game.host_score and game.host_votes have always been zero, why the Personal Data
-- screen could only ever show a host rating of no stars, and why RankingService's host-rating
-- board (skey 4) returns an empty board on purpose. All three now have a source.
--
-- Shaped after instructor_review, which answers the same question for the other star gauge:
-- append-only, timestamped, one row per vote, with the average computed at query time. Do NOT
-- accumulate into game.host_score -- games are deleted at teardown and the votes are history,
-- exactly as round_report is.
CREATE TABLE public.host_review (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    game_id        bigint      NOT NULL,
    host_chara_id  bigint      NOT NULL REFERENCES public.chara (id),
    voter_chara_id bigint      NOT NULL REFERENCES public.chara (id),
    rating         smallint    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    reviewed_at    timestamptz NOT NULL DEFAULT now(),
    -- One vote per player per game. The client's own flow offers the prompt once as the player
    -- leaves, so a second arrival is a retry or a replay, not a second opinion.
    CONSTRAINT host_review_once_per_game UNIQUE (game_id, voter_chara_id)
);

-- Matches the read pattern of both consumers: the star gauge on 0x4103 and the ranking board,
-- which windows on the timestamp for its monthly half.
CREATE INDEX host_review_host_idx ON public.host_review (host_chara_id, reviewed_at DESC);
