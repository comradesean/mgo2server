-- chara_training_time.total_seconds held TOTAL PLAY TIME across every lobby, not training time.
-- It lived here for historical reasons -- it was added with the graduation work, and the table
-- already existed -- and the name misled readers badly enough to cause at least one wrong reading.
--
-- Total play time is now derived at query time from round_report, which is the same sum the
-- personal-stats screen displays. Deriving it means the instructor and clan gates agree with the
-- number the player can see, where the stored counter silently disagreed with it.
--
-- The three columns that remain are genuinely training time and are genuinely not derivable:
-- verified live 2026-07-28 across two Solo Training sessions that the mode sends no round report of
-- any kind -- its entire inbound vocabulary is 0003, 0005, 4128, 4150, 4310, 4316, 4344, 4380, 4398,
-- 43d0, 4440, 4820, with no 0x4390 and nothing unhandled -- so presence (now() - joined_at at
-- teardown) is the only measurement available for them.
--
-- The reverse question was asked and answered too: should the six playable modes ALSO use presence,
-- for consistency? No. A game rotates rules under one joined_at, so presence cannot be attributed to
-- a mode, and 0x4105 needs a figure per mode. Presence would also count briefing and lobby waiting,
-- and RankingService already sums seconds_in_game. Training is the mirror image -- one mode for the
-- lobby's whole life -- which is exactly why presence is right there and wrong here.

ALTER TABLE public.chara_training_time DROP COLUMN total_seconds;

COMMENT ON TABLE public.chara_training_time IS
    'Seconds spent in the training lobbies, measured by presence because those modes send no round '
    'report. Total play time is NOT here -- it is derived from round_report.';
