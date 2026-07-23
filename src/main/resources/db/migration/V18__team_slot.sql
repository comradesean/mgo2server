-- Wire offset 0x23 turned out to be two u16 fields, not one u32 (OBSERVED.md, "Three-player
-- TDM"): the high half is a team slot index (0/1; constant per player per game, 0 in DM),
-- the low half the actual seconds. Existing rows stored the raw composite; split it.
ALTER TABLE public.round_report ADD COLUMN team_slot smallint NOT NULL DEFAULT 0;
UPDATE public.round_report SET team_slot = seconds_in_game / 65536,
    seconds_in_game = seconds_in_game % 65536;
