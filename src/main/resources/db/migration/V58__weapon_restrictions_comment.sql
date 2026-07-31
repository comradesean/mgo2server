-- Correct the weapon_restrictions comments. V52 and V54 claimed "no per-bit meaning is
-- established". That is wrong, and it contradicts our own documentation.
--
-- PROTOCOL.md, "Weapon restrictions - the 16-byte bitfield", carries a per-weapon map with NINETEEN
-- BITS CONFIRMED ONE WEAPON AT A TIME against the live client (2026-07-22 sweep, recorded in
-- OBSERVED.md), plus the master enable flag at bit 0 of the first byte. Knife, Mk.2, GSR, P90,
-- Vz.83, M4 Custom, AK-102, M870 Custom, Mosin-Nagant, SVD, the grenades, Claymore, Shield and the
-- rest are all named and verified.
--
-- The column is still stored whole, but for an honest reason rather than an invented one:
--
--   * it is a BITMASK the client owns end to end -- 128 bits whose assignment is the client's, not
--     ours -- and a bitmask is the natural shape for that;
--   * the remaining bits are transcribed from a reference and are UNVERIFIABLE on BLUS30109, being
--     expansion-era weapons this build's UI cannot express. Expanding the field into columns would
--     harden those guesses into schema, which is the failure this project has paid for most;
--   * nothing server-side reasons about an individual weapon bit. If that ever changes, the map to
--     use is in PROTOCOL.md and the tiers are marked.
--
-- Comments only. The data and its shape are unchanged.

COMMENT ON COLUMN public.game.weapon_restrictions IS
	'Weapon restriction bitmask, one bit per item, set = locked; bit 0 of the first byte is the '
	'master enable. Per-weapon map in dev/docs/PROTOCOL.md: 19 bits confirmed weapon-by-weapon '
	'against the live client, the remainder transcribed from a reference and unverifiable on this '
	'build. Stored whole because the assignment is the client''s and the unverified half must not '
	'be hardened into schema.';

COMMENT ON COLUMN public.chara_host_settings.weapon_restrictions IS
	'Weapon restriction bitmask; see game.weapon_restrictions and dev/docs/PROTOCOL.md.';
