-- Type the parts of the host-settings blob we already understand.
--
-- 134 of the blob's 345 bytes were understood and simply not stored: the rotation's other fifteen
-- entries, the weapon-restriction bitfield, the seventeen rule timers and the unique-character
-- pair. Storing them raw and handing them back was a bridge, not a design -- if we return these
-- bytes to a client we are responsible for knowing what they are. See BACKLOG, "The host-settings
-- blob must go".
--
-- WIRE LAYOUT IS NOT RECORDED HERE. Offsets and widths belong to dev/proto/inbound/
-- mgo2_cmd_4310_c2s.ksy, which is the authority for them; duplicating them into column comments
-- creates a second copy that drifts. These comments say what the data MEANS.
--
-- The blob column stays for now ON PURPOSE. It is dropped only once reconstruction from these
-- columns is proven byte-identical to it, because a reconstruction one byte wrong would corrupt
-- every Create Game pre-fill and the symptom would be a screen full of plausible values.

-- The game's round rotation: sixteen entries of rule, map and per-entry rule option. Stored as
-- three parallel arrays rather than a composite type -- they are read as whole columns, and arrays
-- keep the round index as the subscript. A zero map ends the client's walk over the array, so
-- trailing zero entries are inert rather than invalid, which is why all sixteen are kept.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rotation_rules smallint[];
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rotation_maps smallint[];
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rotation_flags smallint[];

-- Weapon restrictions: a bitfield, one bit per item, set means locked. Kept whole rather than
-- expanded into booleans because the client owns the bit assignment and no per-bit meaning is
-- established -- opaque BY EVIDENCE, as distinct from opaque by neglect.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS weapon_restrictions bytea;

-- Per-rule time, round and ticket limits. The slot-to-rule mapping is in
-- AutomatchSettingsBlock.RULE_TIMERS and is confirmed two ways: the client scales exactly the eight
-- TIME slots by 60, and stored blobs from unedited characters match the documented defaults at
-- those slots.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS rule_timers integer[];

-- Unique characters per side. Absent from this build's Create screens (expansion-era content), so
-- these round-trip unread.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unique_red smallint;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unique_blue smallint;

COMMENT ON COLUMN public.game.rotation_rules IS
	'Rule of each of the 16 rotation entries. A zero map ends the rotation.';
COMMENT ON COLUMN public.game.rotation_maps IS
	'Map of each rotation entry. Zero terminates the rotation.';
COMMENT ON COLUMN public.game.rotation_flags IS
	'Per-entry rule option. Whitelisted to {0,2} for most rules, {0} for Sneaking.';
COMMENT ON COLUMN public.game.weapon_restrictions IS
	'Weapon restriction bitfield, one bit per item, set = locked. Stored whole: the client owns the '
	'bit assignment and no per-bit meaning is established.';
COMMENT ON COLUMN public.game.rule_timers IS
	'Per-rule time, round and ticket limits. Slot mapping: AutomatchSettingsBlock.RULE_TIMERS.';
COMMENT ON COLUMN public.game.unique_red IS
	'Unique character for the red side. Expansion-era; unread by this build.';
COMMENT ON COLUMN public.game.unique_blue IS 'Unique character for the blue side.';
