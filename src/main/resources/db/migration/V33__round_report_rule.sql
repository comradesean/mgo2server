-- The game mode a round was played under, recorded on the round report itself.
--
-- The Rankings screens split the player score board by mode: seven consecutive menu rows send
-- skey 0 with rule 0, 1, 3, 5, 2, 7 and 4 [ELF, the menu table at 0x914140]. Answering those seven
-- rows with the same numbers would make the split meaningless.
--
-- The rule was already stored, but only on `game`, and game rows are deleted at teardown while
-- reports are history — round_report.game_id deliberately carries no foreign key for exactly that
-- reason (see V16). So by the time a ranking is queried the mode of an old round is gone. Copying
-- it onto the report at write time is the smallest fix: one column, written once, from a row that
-- is guaranteed to still exist because the report arrives during the game.
--
-- Existing rows cannot be recovered — their games are long gone — so they default to 0 and count
-- towards mode 0 only. That is a known, bounded inaccuracy in historical data, not a silent one.
ALTER TABLE public.round_report ADD COLUMN IF NOT EXISTS rule smallint NOT NULL DEFAULT 0;

-- Backfill whatever is still joinable; in a live database this is usually the in-flight games only.
UPDATE public.round_report r
SET rule = g.rule
FROM public.game g
WHERE g.id = r.game_id AND r.rule = 0;

-- The score board groups by character and filters on the mode.
CREATE INDEX IF NOT EXISTS round_report_rule_idx ON public.round_report (rule, chara_id);
