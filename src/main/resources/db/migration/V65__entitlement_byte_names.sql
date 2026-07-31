-- Name both entitlement columns after the trailer byte they carry.
--
-- The `0x3049` trailer is a 32-BYTE array. We set bits in two of those bytes:
--
--     index 0   0x00
--     index 1   0x07   <- three bits, inherited, unexamined
--     index 2   0x00
--     index 3   0x03   <- bit 0 = the day-one paid MGO Codec Pack; bit 1 has no reader
--     index 4..31   0x00
--
-- V62 called index 3 `entitlements` and V63 called index 1 `entitlements_index1`. That reads as a
-- value and a variant of it, which is wrong twice over: they are different bytes, and they are not
-- even adjacent on the wire. The naming caused exactly the confusion it invited.
--
-- Both are now named for their byte, symmetrically, so neither can be mistaken for part of the
-- other. No behaviour changes: same values, same reads, same per-request lookup.
--
-- A note on the remaining name. Calling index 1 "entitlements" is still an ASSUMPTION -- only index
-- 3 is proven to gate an entitlement. Index 1's three bits have never been shown to do anything,
-- and until 2026-07-30 nobody had even searched for a reader (the search that reported "no reader"
-- tested displacement 487, which is index THREE; index 1 is 485). If it turns out to gate something
-- else, rename it again to say what it does -- a name should not outrun its evidence.

ALTER TABLE public.account RENAME COLUMN entitlements TO entitlements_byte3;
ALTER TABLE public.account RENAME COLUMN entitlements_index1 TO entitlements_byte1;

ALTER TABLE public.account
    RENAME CONSTRAINT account_entitlements_range TO account_entitlements_byte3_range;
ALTER TABLE public.account
    RENAME CONSTRAINT account_entitlements_index1_range TO account_entitlements_byte1_range;

COMMENT ON COLUMN public.account.entitlements_byte3 IS
    'Byte at 0x3049 trailer index 3. Bit 0 grants the 32 codec / preset messages -- the day-one '
    'paid MGO Codec Pack (proven live 2026-07-29). Bit 1 has no reader on this build. Defaults to '
    '0: paid content is granted per account, never inherited. Read per request, so an UPDATE '
    'applies on the next character-list fetch with no restart.';

COMMENT ON COLUMN public.account.entitlements_byte1 IS
    'Byte at 0x3049 trailer index 1. We have always sent 0x07; none of its three bits is '
    'understood, and whether anything reads the byte at all is still open. Per-account so it can '
    'be isolated live -- UPDATE then reconnect.';
