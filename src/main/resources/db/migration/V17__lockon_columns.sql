-- Two 0x4390 struct-A slots earned names in the 2026-07-23 single-variable round experiments
-- (OBSERVED.md, "The OTHER-field experiment"): a round of exactly three lock-on kills moved
-- counter_0x09 to 3 on the killer and counter_0x1b to 3 on the victim, after five kill rounds
-- of solid zero in both — the dealt/received pair for lock-on, mirroring how headshots (0x11)
-- pair headshot_deaths (0x13). These are the personal-stats grid's missing operand: the grid's
-- OTHER category derives as minuend - headshots - lockon_kills.
ALTER TABLE public.round_report RENAME COLUMN counter_0x09 TO lockon_kills;
ALTER TABLE public.round_report RENAME COLUMN counter_0x1b TO lockon_deaths;
