-- Decode the per-character Create Game pre-fill, the sibling of the game's host settings.
--
-- Same 345-byte structure, same field map, keyed per (character, lobby subtype) instead of per
-- game. It is the last stored blob that carries a structure rather than an image. See BACKLOG,
-- "The host-settings blob must go".
--
-- Wire layout lives in dev/proto/inbound/mgo2_cmd_4310_c2s.ksy. These comments say what the data
-- means; the ksy is the authority for offsets and widths.

ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS comment character varying;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS password character varying;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS dedicated boolean NOT NULL DEFAULT false;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS settings_lobby_subtype smallint NOT NULL DEFAULT 0;

ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS rotation_rules smallint[];
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS rotation_maps smallint[];
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS rotation_flags smallint[];

ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS weapon_restrictions bytea;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS max_players smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS briefing_time integer NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS stance smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS level_limit_tolerance smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS level_limit_base integer NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS rule_timers integer[];
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unique_red smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unique_blue smallint NOT NULL DEFAULT 0;

-- The Common Settings toggle bytes, stored whole. The booleans elsewhere are a decoded VIEW of
-- these: bits 1, 2 and 6 are not decoded, so they cannot reproduce the byte -- a byte-for-byte
-- rebuild of the game's copy caught exactly that.
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS common_a smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS common_b smallint NOT NULL DEFAULT 0;

ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS idle_kick smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS team_kill_kick smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS capture_extra_time boolean NOT NULL DEFAULT false;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS sneaking_snake_kills smallint NOT NULL DEFAULT 3;

-- Fields the client parses and reads back through nothing. Stored so the round-trip is exact and
-- named by position, because naming them by guess is the failure this project has paid for most.
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_800 smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_801 smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_824 bigint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_832 integer NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_836 bigint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_844 integer NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_931 smallint NOT NULL DEFAULT 0;
ALTER TABLE public.chara_host_settings ADD COLUMN IF NOT EXISTS unread_tail bytea;

COMMENT ON COLUMN public.chara_host_settings.unread_tail IS
	'Fourteen bytes the client writes as one raw block and never reads back. Kept whole: no field '
	'boundaries exist to split on. Its byte 10 carries the host-options flags non_stat comes from, '
	'so the block is not inert -- only unread by the client.';
COMMENT ON COLUMN public.chara_host_settings.weapon_restrictions IS
	'One bit per item, set = locked. Stored whole: the client owns the bit assignment.';
COMMENT ON COLUMN public.chara_host_settings.common_a IS
	'Common Settings toggle byte A, authoritative. Bits 1, 2 and 6 are undecoded.';
COMMENT ON COLUMN public.chara_host_settings.common_b IS 'Common Settings toggle byte B.';
