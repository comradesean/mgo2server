-- Graduation: who trained a character, and the total play time the award is gated on.
--
-- The event is the instructor review. Sequence observed live 2026-07-26, with connections
-- attributed by character:
--
--     43a6 = 3            host     client setting 332, written at graduation
--     43c0                host     host info push
--     43c8 = <stars> 21   STUDENT  the review -- 5, 3 and 1 stars produced 5, 3 and 1
--     4390 chara=student  host     the student's session, seconds_in_game 1924
--     4342 = student      host     departure
--     4820               STUDENT  checks the mailbox, seconds later
--
-- The review is the only packet that comes from the student, so it is the only one that says who
-- graduated without inference; the game it arrives in names the host, who is the instructor. The
-- student checking mail immediately afterwards is why the award is granted synchronously: the
-- announcement has to exist by the time that fetch lands.
--
-- Awarding is all-or-nothing. A student who reviews without meeting the requirements gets the
-- relationship recorded and nothing else, and simply trains again -- the next review overwrites
-- these fields, which is what makes repeat graduations work.

CREATE TABLE IF NOT EXISTS public.chara_instructor
(
    chara_id bigint NOT NULL,
    instructor_chara_id bigint,
    -- Snapshots, not lookups: the stats screen shows who trained you at the time, and the
    -- instructor may later be renamed or deleted.
    instructor_name character varying(16) NOT NULL DEFAULT '',
    -- The student is one generation after their instructor. An instructor with no record of their
    -- own is first generation, so their students are second.
    generation integer NOT NULL DEFAULT 2,
    -- Stars the student awarded, 1..5, straight from the 0x43c8 u32.
    rating smallint NOT NULL DEFAULT 0,
    graduated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chara_instructor_pkey PRIMARY KEY (chara_id),
    CONSTRAINT chara_instructor_chara_id_fkey FOREIGN KEY (chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    -- The instructor's row going away must not erase the student's history, hence SET NULL and the
    -- name snapshot above.
    CONSTRAINT chara_instructor_instructor_fkey FOREIGN KEY (instructor_chara_id)
        REFERENCES public.chara (id) ON DELETE SET NULL
);

-- Total time in any game, for the 20-hour requirement. Kept beside the training columns because
-- both are credited from the same presence measurement (game_player.joined_at to row removal).
ALTER TABLE public.chara_training_time
    ADD COLUMN IF NOT EXISTS total_seconds bigint NOT NULL DEFAULT 0;
