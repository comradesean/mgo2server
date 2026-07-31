-- Player relationships (the ADDLIST): who a character has marked as friend or blocked.
--
-- Wire-observed model (2026-07-22): the client pushes one 0x4500 {u8 state, u32 target} per
-- change — state 0 = friend, 1 = blocked as seen live — and expects the authoritative lists back
-- in the 0x4101 login burst's friend/blocked id arrays. "None" sends nothing: it is the absence
-- of a row here, which is why a relationship could never be cleared while nothing was stored.
CREATE TABLE IF NOT EXISTS public.chara_relation
(
    chara_id bigint NOT NULL,
    target_chara_id bigint NOT NULL,
    -- 0 friend, 1 blocked; values beyond the two observed are stored as-is and served to no one.
    state smallint NOT NULL,
    updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chara_relation_pkey PRIMARY KEY (chara_id, target_chara_id),
    CONSTRAINT chara_relation_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT chara_relation_target_fkey FOREIGN KEY (target_chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);
