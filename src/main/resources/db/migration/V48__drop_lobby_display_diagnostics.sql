-- Drops the two diagnostic lobby columns added while hunting the "beginner lobby" marking. Both
-- answered their question, and the answer was no.
--
-- hub_flags (V46) fed the hub entry's flags byte, 0x4902 wire 0x07. Setting all eight bits at once
-- (0xff, confirmed in a live capture) changed nothing, which matches the static read: no call site
-- of the hub-entry getter 0xD49040 touches offset 7. The byte is parsed by the client and never
-- read. The writer still emits it as an explicit zero, and says why, so nobody re-derives this.
--
-- player_count_override (V47) faked the reported occupancy to see whether the population icons on
-- a lobby row keyed off a count threshold. 500 went out (0x01f4, confirmed on the wire) and the
-- row did not change.
--
-- Neither is policy and nothing depends on either. Keeping a knob that is proven inert invites a
-- future session to try it again.
ALTER TABLE public.lobby DROP CONSTRAINT IF EXISTS lobby_hub_flags_range;
ALTER TABLE public.lobby DROP CONSTRAINT IF EXISTS lobby_player_count_override_range;
ALTER TABLE public.lobby DROP COLUMN IF EXISTS hub_flags;
ALTER TABLE public.lobby DROP COLUMN IF EXISTS player_count_override;
