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

ALTER TABLE public.game DROP COLUMN IF EXISTS host_settings;
ALTER TABLE public.chara_host_settings DROP COLUMN IF EXISTS blob;
