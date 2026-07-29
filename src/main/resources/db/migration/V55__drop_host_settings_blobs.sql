-- Drop the host-settings blobs.
--
-- Both tables now hold every byte of the structure in typed columns, and both rebuild the block
-- byte-for-byte from them -- asserted in MatchStateIT against payloads where every field carries a
-- distinct value, so a mis-mapped offset swaps two things visibly rather than cancelling out.
-- Nothing reads these columns any more: the game-details reply builds from columns, and the Create
-- Game pre-fill is reconstructed rather than replayed.
--
-- What the decode found, which is the argument for having done it:
--
--   * the rotation was being truncated to its first entry, so a game's later rounds did not
--     survive a round trip through storage;
--   * three fields had never been stored at all and only surfaced when something tried to
--     reproduce the block;
--   * the Common Settings toggle bytes cannot be rebuilt from their booleans, because bits 1, 2
--     and 6 are undecoded -- a rebuild produced 0x22 where the client had sent 0x24.
--
-- None of that was visible while the bytes were kept whole and handed back unread.
--
-- The clan emblem stays a blob deliberately: it is a 32x32 16-colour EMBD image that round-trips
-- between the client's own editor and its own renderer, fully documented in
-- dev/proto/inbound/mgo2_cmd_4b50_c2s.ksy. Knowing the format is what makes keeping it a choice.

-- BACKFILL FIRST. The columns were only populated by pushes that arrived after V52/V53, so every
-- row stored before them still has its settings ONLY in the blob. Dropping without this discards
-- real player state: a host's saved Create Game pre-fill, which they would have to re-enter.
--
-- Byte offsets are 0-based, matching get_byte. The layout is in
-- dev/proto/inbound/mgo2_cmd_4310_c2s.ksy; it is spelled out here rather than referenced because a
-- migration has to be readable on its own years later.

UPDATE public.chara_host_settings SET
	-- NUL-terminated fixed-width fields. Trimmed on the BYTEA before converting: Postgres refuses a
	-- NUL inside text, so chr(0) cannot be used as a delimiter here at all.
	comment = convert_from(substring(blob from 17 for
		coalesce(nullif(position('\x00'::bytea in substring(blob from 17 for 128)), 0) - 1, 128)),
		'LATIN1'),
	password = CASE WHEN get_byte(blob, 144) <> 0 THEN convert_from(substring(blob from 146 for
		coalesce(nullif(position('\x00'::bytea in substring(blob from 146 for 16)), 0) - 1, 16)),
		'LATIN1') END,
	dedicated = get_byte(blob, 161) <> 0,
	settings_lobby_subtype = get_byte(blob, 162),
	rotation_rules = (select array_agg(get_byte(blob, 163 + i * 3) order by i)
		from generate_series(0, 15) i),
	rotation_maps = (select array_agg(get_byte(blob, 164 + i * 3) order by i)
		from generate_series(0, 15) i),
	rotation_flags = (select array_agg(get_byte(blob, 165 + i * 3) order by i)
		from generate_series(0, 15) i),
	unread_800 = get_byte(blob, 211),
	unread_801 = get_byte(blob, 212),
	weapon_restrictions = substring(blob from 214 for 16),
	max_players = get_byte(blob, 229),
	briefing_time = (get_byte(blob, 230) << 24) | (get_byte(blob, 231) << 16)
		| (get_byte(blob, 232) << 8) | get_byte(blob, 233),
	unread_824 = (get_byte(blob, 234)::bigint << 24) | (get_byte(blob, 235) << 16)
		| (get_byte(blob, 236) << 8) | get_byte(blob, 237),
	unread_832 = (get_byte(blob, 238) << 8) | get_byte(blob, 239),
	unread_836 = (get_byte(blob, 240)::bigint << 24) | (get_byte(blob, 241) << 16)
		| (get_byte(blob, 242) << 8) | get_byte(blob, 243),
	unread_844 = (get_byte(blob, 244) << 8) | get_byte(blob, 245),
	stance = get_byte(blob, 246),
	level_limit_tolerance = get_byte(blob, 247),
	level_limit_base = (get_byte(blob, 248) << 24) | (get_byte(blob, 249) << 16)
		| (get_byte(blob, 250) << 8) | get_byte(blob, 251),
	rule_timers = (select array_agg(
			(get_byte(blob, 252 + i * 4) << 24) | (get_byte(blob, 253 + i * 4) << 16)
			| (get_byte(blob, 254 + i * 4) << 8) | get_byte(blob, 255 + i * 4) order by i)
		from generate_series(0, 16) i),
	unique_red = get_byte(blob, 320),
	unique_blue = get_byte(blob, 321),
	common_a = get_byte(blob, 322),
	common_b = get_byte(blob, 323),
	unread_931 = get_byte(blob, 324),
	idle_kick = (get_byte(blob, 325) << 8) | get_byte(blob, 326),
	team_kill_kick = (get_byte(blob, 327) << 8) | get_byte(blob, 328),
	capture_extra_time = get_byte(blob, 329) <> 0,
	sneaking_snake_kills = get_byte(blob, 330),
	-- Zero-padded to a full 14 bytes: a capture that stopped at the parser's 0x156 minimum is three
	-- short, and the reconstruction expects the whole block. Padding is built as bytea rather than
	-- text for the same reason as above.
	unread_tail = substring(blob from 332 for 14)
		|| decode(repeat('00', greatest(0, 14 - length(substring(blob from 332 for 14)))), 'hex')
WHERE blob IS NOT NULL AND length(blob) >= 342 AND unread_tail IS NULL;

-- Note the stored payloads are 352 bytes, not the 345 the last named field implies: the trailing
-- seven are zero in every capture. Nothing is read from them; they are reproduced because the block
-- handed back to the client has to be the length the client sent.

-- The capture harness hangs off this column and blocks the drop. It is operator-installed from
-- dev/tools/blob_audit.sql, not part of the schema, and its job here is done: it existed to archive
-- 0x4310 pushes so consecutive hosts would not overwrite the evidence while the block was being
-- decoded. The block is decoded, so the trigger goes with the column.
--
-- blob_audit itself is KEPT, rows and all. It holds the captures the decode was built from, and
-- throwing away the evidence because the conclusion is written down is how a finding becomes
-- unverifiable. Re-point the harness at another column when the next blob needs the same treatment.
DROP TRIGGER IF EXISTS host_settings_blob_audit ON public.chara_host_settings;

ALTER TABLE public.game DROP COLUMN IF EXISTS host_settings;
ALTER TABLE public.chara_host_settings DROP COLUMN IF EXISTS blob;
