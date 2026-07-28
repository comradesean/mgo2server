-- Name the columns of chara_training_time in the database itself, because the table's name
-- undersells one of them badly enough to have caused a misreading.
--
-- This is comments only: no data, no structure. It exists as its own migration rather than as an
-- edit to V24 because V24 has already run, and Flyway checksums applied migrations -- changing one
-- after the fact fails validation at startup.

COMMENT ON TABLE public.chara_training_time IS
    'Play-time counters. NOTE: total_seconds is not training time and is not the sum of the other '
    'three columns -- see its own comment.';

COMMENT ON COLUMN public.chara_training_time.training_mode_seconds IS
    'Seconds in Basic Training (lobby subtype 7). Shown at 0x4107 slot 46.';

COMMENT ON COLUMN public.chara_training_time.instructor_seconds IS
    'Seconds in Combat Training (subtype 8) while hosting, i.e. as the instructor. 0x4107 slot 47.';

COMMENT ON COLUMN public.chara_training_time.student_seconds IS
    'Seconds in Combat Training (subtype 8) while not hosting, i.e. as a student. 0x4107 slot 48.';

COMMENT ON COLUMN public.chara_training_time.total_seconds IS
    'TOTAL PLAY TIME across every lobby, Free Battle included -- not training time, and strictly '
    'larger than the sum of the three columns above for anyone who plays normally. It cannot be '
    'reconstructed from them. This is what the 20-hour instructor gate reads, because Konami''s '
    'requirement is "20 or more hours of gameplay", not twenty hours in a training lobby. '
    'Feeds no screen.';
