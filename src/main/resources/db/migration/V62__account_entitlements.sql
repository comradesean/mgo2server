-- Entitlements move to the account, where they can be edited without a restart.
--
-- This is the byte at index 3 of the 32-byte trailer on 0x3049 (the character list). It was a
-- compile-time constant, then briefly an environment variable; neither can be changed for one
-- account, and both need a restart. An entitlement is per-account state, so it belongs here.
--
-- WHAT THE BIT DOES [ELF]. Only bit 0 is read, by two sites, both of the same byte at ctx+22455:
-- 0x9B9E30 computes (byte & 1) << 4 -- 0 or 16 -- and 0x9BADA4 tests byte & 1 to choose between two
-- list-builders. The 16 is a threshold: the availability predicate 0x9B9DF0 walks an 85-entry table
-- at 0xE1812C and refuses any entry whose gate exceeds it. 32 entries gate on exactly 16, 23 gate
-- on 0 and are always available, and 27 defer to a separate ownership check. So clearing bit 0
-- removes 32 entries from the client.
--
-- WHAT THOSE 32 ENTRIES ARE IS UNRESOLVED. "Loadout items" is the label from the first trace of the
-- predicate, but the day-one MGO Codec Pack adds exactly 32 preset-message phrases, so one bit may
-- be the whole shop. See dev/docs/POST_LAUNCH.md for the experiment: with this column it is now an
-- UPDATE and a reconnect rather than a restart.
--
-- DEFAULT 3 preserves exactly what we have always sent. Bit 1 has no reader, and neither do the
-- other 31 bytes of the trailer -- the array is one meaningful bit and a lot of padding -- but the
-- 0x03 is kept verbatim rather than trimmed to 0x01, because "what we have always sent" is the only
-- thing about the inert bits that is evidenced.

ALTER TABLE public.account
    ADD COLUMN IF NOT EXISTS entitlements smallint NOT NULL DEFAULT 3;

COMMENT ON COLUMN public.account.entitlements IS
    'Bit 0 unlocks 32 gated entries in the client (0x3049 trailer index 3). Read per request, so '
    'an UPDATE takes effect on the next character-list fetch with no restart.';

ALTER TABLE public.account
    ADD CONSTRAINT account_entitlements_range CHECK (entitlements BETWEEN 0 AND 255);
