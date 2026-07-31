-- Accumulated training time per character, measured server-side.
--
-- 0x4107 slots 46/47/48 ("Training Mode Time", "Combat Training Time (Instructor)" and
-- "(Student)") were derived from round_report, i.e. from the host's own 0x4390 reports. That works
-- when it fires, but the host only reports when a player leaves early: if the host quits first,
-- nobody is reported at all and a whole session vanishes. Confirmed live 2026-07-26 across several
-- sessions.
--
-- So the totals come from presence instead, which we observe directly: game_player.joined_at is
-- written when a character joins and the row is deleted when they leave, and both ends are ours.
-- The host's seconds_in_game stays in round_report as the game's own measure -- useful to compare
-- against, and the two agreeing on a session is a real cross-check -- but it no longer decides
-- what the stats screen shows.
--
-- This is NOT the graduation gate. That requirement is evaluated inside the client, per session,
-- against its own clock: the student must be present for the full 30 minutes in one sitting, and
-- no value the server sends shortens it (BACKLOG, "Training progression"). These columns are the
-- career totals the stats screen renders, nothing more.
CREATE TABLE IF NOT EXISTS public.chara_training_time
(
    chara_id bigint NOT NULL,
    -- Seconds in a subtype-7 lobby, whatever the role. 0x4107 slot 46.
    training_mode_seconds bigint NOT NULL DEFAULT 0,
    -- Seconds in a subtype-8 lobby hosting the game. 0x4107 slot 47.
    instructor_seconds bigint NOT NULL DEFAULT 0,
    -- Seconds in a subtype-8 lobby as anyone else. 0x4107 slot 48.
    student_seconds bigint NOT NULL DEFAULT 0,
    CONSTRAINT chara_training_time_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_training_time_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE
);

-- Seed from the reports we already hold, so the change of source does not lose history. Reports
-- written before V19 carry lobby_subtype 0 and are counted nowhere, exactly as the earlier
-- derivation treated them.
INSERT INTO public.chara_training_time
    (chara_id, training_mode_seconds, instructor_seconds, student_seconds)
SELECT chara_id,
       coalesce(sum(seconds_in_game) FILTER (WHERE lobby_subtype = 7), 0),
       coalesce(sum(seconds_in_game) FILTER (
           WHERE lobby_subtype = 8 AND host_chara_id = chara_id), 0),
       coalesce(sum(seconds_in_game) FILTER (
           WHERE lobby_subtype = 8 AND host_chara_id != chara_id), 0)
FROM public.round_report
GROUP BY chara_id
ON CONFLICT (chara_id) DO NOTHING;
