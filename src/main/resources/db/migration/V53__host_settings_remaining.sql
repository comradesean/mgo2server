-- The rest of the host-settings blob, so it can be dropped.
--
-- Every remaining byte now has a status, established from the client binary. Two are newly named
-- and get real columns; the others are proven to have NO READER in this build and are stored as
-- typed-but-unnamed columns rather than left in a blob. A column per field -- even an unnamed one --
-- means the schema is complete and the blob has nothing left to justify it.
--
-- Wire layout lives in dev/proto/inbound/mgo2_cmd_4310_c2s.ksy. These comments say what the data
-- means, or state plainly that nothing does.

-- Capture Mission "EXTRA TIME": adds time at the end of a round until a victor emerges. A plain
-- ON/OFF toggle in the client, so a boolean here rather than the raw byte.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS capture_extra_time boolean NOT NULL DEFAULT false;

-- Sneaking Mission "SNAKE": how many times Snake must be defeated for Red and Blue to win. The
-- client clamps this to 1..5 and renders it as a number.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS sneaking_snake_kills smallint NOT NULL DEFAULT 3;

-- ECHO-ONLY FIELDS. Each is parsed by the client and read by nothing: either no reader exists at
-- all, or the only consumer is an accessor with no callers and no address references anywhere in
-- the image. They are stored so the settings round-trip is exact, and named by position because
-- naming them by guess is the failure this project has paid for most often.
--
-- The first two are the clearest case of a feature compiled out: both are parsed and pushed into
-- the client's own property store, and their only consumers are dead accessors. The plumbing
-- survived; the code that used it did not.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_800 smallint NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_801 smallint NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_832 integer NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_836 bigint NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_844 integer NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_824 bigint NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_931 smallint NOT NULL DEFAULT 0;

-- The two Common Settings toggle bytes, stored whole.
--
-- The booleans beside them (friendly_fire, ghosts, silent_mode, ...) stay: they are what queries
-- want. But they cannot reproduce these bytes, because BITS 1, 2 AND 6 ARE NOT DECODED -- a
-- byte-for-byte rebuild caught that immediately, producing 0x22 where the client had sent 0x24.
-- Reconstructing from the booleans would silently drop whatever those bits mean.
--
-- So these are the authoritative bytes and the booleans are a decoded view of them. That is the
-- same shape as weapon_restrictions: a typed field whose bit assignment is partly established,
-- which is different from an undifferentiated blob.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS common_a smallint NOT NULL DEFAULT 0;
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS common_b smallint NOT NULL DEFAULT 0;

-- The lobby subtype the host sent with its settings. Stored because the settings block carries it
-- and the reconstruction must be exact; it is not authoritative for anything -- the lobby the game
-- lives in is, and in the automatching lobby this byte reads 2 whether or not automatching is
-- involved, which is why it was never a usable discriminator.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS settings_lobby_subtype smallint NOT NULL DEFAULT 0;

-- Fourteen bytes the client writes as ONE raw block. Kept whole deliberately: the binary gives no
-- field boundaries inside it, so splitting it into columns would invent a structure no evidence
-- supports.
--
-- NOT entirely inert, and the distinction matters. An ELF sweep found no CLIENT reader for any byte
-- of this range, but the server decodes the host-options bit out of the byte at its offset 10 --
-- that is where non_stat comes from, and it is capture-proven. So "the client never reads it back"
-- and "nothing uses it" are different claims, and only the first is established. Round-tripping the
-- whole block preserves that bit whatever else is in here.
ALTER TABLE public.game ADD COLUMN IF NOT EXISTS unread_tail bytea;

COMMENT ON COLUMN public.game.capture_extra_time IS
	'Capture Mission: extend the round until a victor emerges.';
COMMENT ON COLUMN public.game.sneaking_snake_kills IS
	'Sneaking Mission: times Snake must be defeated for the attacking teams to win. Client clamps 1-5.';
COMMENT ON COLUMN public.game.unread_800 IS
	'Parsed by the client, consumed only by an accessor that nothing calls. Stored to round-trip.';
COMMENT ON COLUMN public.game.unread_801 IS 'As unread_800.';
COMMENT ON COLUMN public.game.unread_832 IS 'No reader exists in the client. Stored to round-trip.';
COMMENT ON COLUMN public.game.unread_836 IS 'As unread_832.';
COMMENT ON COLUMN public.game.unread_844 IS 'As unread_832.';
COMMENT ON COLUMN public.game.unread_tail IS
	'Fourteen bytes the client writes as one raw block and never reads back. Kept whole: no field '
	'boundaries exist to split on. Its byte 10 carries the host-options flags the server decodes '
	'non_stat from, so the block is not inert -- only unread by the client.';
COMMENT ON COLUMN public.game.common_a IS
	'Common Settings toggle byte A, stored whole. Bits 0/3/4/5/7 are decoded into booleans; bits 1, '
	'2 and 6 are not, so this byte is authoritative and the booleans are a view of it.';
COMMENT ON COLUMN public.game.common_b IS
	'Common Settings toggle byte B. Bits 0-4, 6 and 7 are decoded; the rest are not.';
COMMENT ON COLUMN public.game.unread_824 IS
	'No reader AND no writer in the client: server-authored and echoed back. Stored to round-trip.';
COMMENT ON COLUMN public.game.unread_931 IS
	'Low byte of the settings flags word. Every flag test in the client lies in the other bytes.';
