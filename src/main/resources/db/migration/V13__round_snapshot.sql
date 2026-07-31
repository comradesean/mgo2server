-- The round snapshot as its own table. V12 put a played_last_round flag on game_player, which is
-- deleted when the player leaves — but surviving departure is the snapshot's entire purpose: the
-- host's end-of-round stat report (0x4390) must still apply to a player who quit mid-round. A
-- separate table keyed like the roster, rewritten at each round start (0x43ca), keeps the round's
-- membership independent of the current roster.
CREATE TABLE IF NOT EXISTS public.game_round
(
    game_id bigint NOT NULL,
    chara_id bigint NOT NULL,
    CONSTRAINT game_round_pkey PRIMARY KEY (game_id, chara_id),
    CONSTRAINT game_round_game_id_fkey FOREIGN KEY (game_id)
        REFERENCES public.game (id) ON DELETE CASCADE,
    CONSTRAINT game_round_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);

ALTER TABLE public.game_player DROP COLUMN IF EXISTS played_last_round;
