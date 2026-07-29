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

-- Fourteen bytes written by the client as ONE raw block, with no byte of it read or written
-- anywhere. Kept whole deliberately: the binary gives no field boundaries inside it, so splitting it
-- into columns would invent a structure no evidence supports. This is opaque BY EVIDENCE -- the
-- strongest form, since we know the client itself never looks at it.
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
	'Fourteen bytes the client writes as one raw block and never reads. Kept whole: no field '
	'boundaries exist to split on.';
