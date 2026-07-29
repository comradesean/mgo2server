-- Type the parts of the 0x4310 host-settings blob we already understand.
--
-- 134 of the blob's 345 bytes were understood and simply not stored: the rotation's other fifteen
-- entries, the weapon-restriction bitfield, the seventeen rule timers and the unique-character
-- pair. Storing them raw and handing them back was a bridge, not a design -- if we return these
-- bytes to a client we are responsible for knowing what they are. See BACKLOG, "The host-settings
-- blob must go".
--
-- The blob column stays for now ON PURPOSE. It is dropped only once reconstruction from these
-- columns is proven byte-identical to it, because a reconstruction one byte wrong would corrupt
-- every Create Game pre-fill and the symptom would be a screen full of plausible values.

-- ROTATION, wire 0x0a3..0x0d2: sixteen {rule, map, flags} triples. The count is fixed at 16 by the
-- client's own loop bound, and a zero map terminates every walk over it, so trailing zero entries
-- are inert rather than invalid. Stored as three parallel smallint arrays rather than a composite
-- type: they are read as whole columns, and arrays keep the round index as the subscript.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rotation_rules smallint[];
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rotation_maps smallint[];
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rotation_flags smallint[];

-- WEAPON RESTRICTIONS, wire 0x0d5..0x0e4, 16 bytes. [CONFIRMED] one bit per item, 1 = LOCKED.
-- Kept as bytea rather than expanded: it is a bitfield the client owns end to end, 128 bits with no
-- per-bit meaning established, and expanding it into 128 booleans would invent structure we have
-- not earned. This is opaque BY EVIDENCE, which is different from opaque by neglect.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS weapon_restrictions bytea;

-- RULE TIMERS, wire 0x0fc..0x13f: seventeen consecutive u32. The per-rule pairing is recorded in
-- AutomatchSettingsBlock.RULE_TIMERS and is confirmed two ways -- the client scales exactly the
-- eight TIME indices by 60, and four stored blobs from unedited characters match the documented
-- defaults at exactly these indices.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rule_timers integer[];

-- UNIQUE CHARACTERS, wire 0x140..0x141, one 2-byte write. [INFERRED] red then blue. The setting is
-- absent from this build's Create screens (expansion-era content), so it round-trips unread here.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unique_red smallint;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unique_blue smallint;

COMMENT ON COLUMN public.game.rotation_rules IS
	'0x4310 wire 0x0a3, rule of each of the 16 rotation entries. A zero map ends the walk.';
COMMENT ON COLUMN public.game.rotation_maps IS
	'0x4310 wire 0x0a4 stride 3, map of each rotation entry. Zero terminates.';
COMMENT ON COLUMN public.game.rotation_flags IS
	'0x4310 wire 0x0a5 stride 3, per-entry rule option. Whitelisted to {0,2} for most rules.';
COMMENT ON COLUMN public.game.weapon_restrictions IS
	'0x4310 wire 0x0d5, 16 bytes. One bit per item, 1 = locked. Opaque by evidence: the client owns '
	'the bit assignment and no per-bit meaning is established.';
COMMENT ON COLUMN public.game.rule_timers IS
	'0x4310 wire 0x0fc, 17 u32. Per-rule slots; see AutomatchSettingsBlock.RULE_TIMERS.';
COMMENT ON COLUMN public.game.unique_red IS '0x4310 wire 0x140. Expansion-era, unread by this build.';
COMMENT ON COLUMN public.game.unique_blue IS '0x4310 wire 0x141.';
