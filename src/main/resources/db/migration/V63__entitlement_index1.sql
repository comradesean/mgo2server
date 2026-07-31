-- The second entitlement byte, so every bit we set is per-account and testable.
--
-- The 0x3049 trailer is 32 bytes and we set bits in exactly two of them:
--
--     index 1 = 0x07   three bits, all unexplained
--     index 3 = 0x03   bit 0 is the codec pack (proven live); bit 1 unexplained
--
-- That is FIVE set bits, of which one is understood. V62 made index 3 per-account. This does the
-- same for index 1, so the remaining four can be isolated by UPDATE and reconnect rather than
-- guessed at.
--
-- WHY NOT TRUST "THEY HAVE NO READER". A trace reported that indices 0, 2 and 4..31 have no reader
-- and that index 1 has none either. That same trace labelled index 3 bit 0 as unlocking "32 of the
-- 91 selectable loadout items", which a live test disproved on 2026-07-29 -- it gates the codec
-- messages and does not touch gear. A negative from a source that got the positive wrong is not
-- worth much, and these bits are cheap to test properly now.
--
-- NAMED BY WIRE POSITION, deliberately, following the unread_NNN precedent in chara_host_settings:
-- a field whose meaning is unknown gets a name that says where it is, not a guess at what it does.
-- Rename it when the bits are identified.

ALTER TABLE public.account
    ADD COLUMN IF NOT EXISTS entitlements_index1 smallint NOT NULL DEFAULT 7;

COMMENT ON COLUMN public.account.entitlements_index1 IS
    'Byte at 0x3049 trailer index 1. We have always sent 0x07; no bit of it is understood. '
    'Per-account so it can be isolated live -- UPDATE then reconnect.';

COMMENT ON COLUMN public.account.entitlements IS
    'Byte at 0x3049 trailer index 3. Bit 0 unlocks the 32 codec / preset messages (proven live '
    '2026-07-29). Bit 1 is set by default and NOT understood. Read per request, so an UPDATE '
    'applies on the next character-list fetch with no restart.';

ALTER TABLE public.account
    ADD CONSTRAINT account_entitlements_index1_range CHECK (entitlements_index1 BETWEEN 0 AND 255);
