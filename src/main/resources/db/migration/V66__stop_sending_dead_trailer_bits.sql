-- Stop sending the dead trailer bits. Byte 1 is cargo; only byte 3 bit 0 does anything.
--
-- V63 kept byte 1 at 0x07 because nobody had established what it did -- and, as V64 recorded, the
-- one search claiming it inert had tested displacement 487, which is byte THREE's offset. That gap
-- is now closed properly, and the answer is a clean negative.
--
-- EVIDENCE [ELF 2026-07-30]. The trailer is written by 0xD3774C (`addi r4,r27,484` / `li r5,32` /
-- bl 0xD5D018) into ctx+484..515, where ctx = profile+21968. So byte 1 is ctx+485. Four searches,
-- each stating its displacement:
--
--   * every D-form op `...,485(rN)` for any register and width: one hit, `stb r11,485(r1)`, an
--     unrelated stack store
--   * a raw instruction-word scan of 0x10230..0xDE9328 for D == 485 with RA != 0: same single
--     stack hit, zero non-stack accesses
--   * displacement 22453 (profile-relative) and the whole addis-adjusted band: zero hits
--   * `addi rX,rY,485` anywhere -- i.e. any pointer to that byte ever being formed: zero
--
-- and a chain-of-custody check that also covers indexed access: the ctx pointer has exactly 16
-- origination sites binary-wide (11 x `bl 0xD36C74`, 5 x `addi rX,rY,21968`), and the complete set
-- of offsets any of them touches is 0, 1, 2, 4+60*i, and 487. No lbzx, no loop over the trailer.
--
-- So displacements 484..515 are read at exactly TWO addresses -- 0x9B9E30 and 0x9BADA4 -- both
-- reading byte 3, and both masking to bit 0 by instruction encoding (`rlwinm r27,r0,4,27,27` and
-- `clrlwi r0,r0,31`). Bit 1 of byte 3 is not merely unread; it is discarded in the opcode.
--
-- Everything except byte 3 bit 0 is therefore inert in this build, and byte 1's 0x07 is pure cargo
-- from the reference servers. Sending 0 changes nothing observable -- which is exactly why there is
-- no reason to keep sending something we cannot explain.
--
-- Byte 3's default is already 0 (V64); the day-one paid Codec Pack is granted per account.

UPDATE public.account SET entitlements_byte1 = 0 WHERE entitlements_byte1 <> 0;

ALTER TABLE public.account ALTER COLUMN entitlements_byte1 SET DEFAULT 0;

COMMENT ON COLUMN public.account.entitlements_byte1 IS
    'Byte at 0x3049 trailer index 1. PROVEN DEAD (ELF 2026-07-30): displacement 485 is read '
    'nowhere in the binary. We sent an inherited 0x07 until then; now 0. Kept as a column rather '
    'than removed so a later build can be tested against it without a migration.';
