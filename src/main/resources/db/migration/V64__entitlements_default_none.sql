-- New accounts get no entitlements.
--
-- V62 defaulted account.entitlements to 3, preserving what the server had always sent. That was
-- right at the time -- nobody knew what the bits did, and changing behaviour while identifying it
-- would have confounded the test. The bits are now identified:
--
--     bit 0  the day-one MGO Codec Pack, a PAID Konami-ID item. Proven three ways: clearing it
--            removed the codec list on a live client, the predicate reads exactly this bit, and
--            the 32 gated catalogue rows match the published product list 32/32 in order.
--     bit 1  no reader on this build. Most likely the second codec pack, which required a client
--            update -- the catalogue at 0xE1812C would have to grow, and a server flag cannot do
--            that. Inert here.
--
-- So the old default granted a paid item to every account that had ever existed, and would have
-- kept doing it for every new one. Existing accounts were set to 0 on 2026-07-29 with the pack
-- granted individually; this makes new accounts match, so the policy does not depend on someone
-- remembering to run an UPDATE.
--
-- Granting it is a deliberate per-account decision:
--     update account set entitlements = 1 where id = <account>;
--
-- entitlements_index1 is deliberately NOT changed. It still defaults to 7, the three inherited set
-- bits at trailer index 1, because nobody has established what they do -- and unlike index 3, nobody
-- has even looked: the search that reported "no reader" tested `lbz r0,487(r3)`, which is index
-- THREE's offset (ctx+21968 + 487). Index 1 is 485. Zeroing it would be an experiment, not a
-- correction, and this migration is only for the part that is settled.

ALTER TABLE public.account ALTER COLUMN entitlements SET DEFAULT 0;

COMMENT ON COLUMN public.account.entitlements IS
    'Byte at 0x3049 trailer index 3. Bit 0 grants the 32 codec / preset messages -- the day-one '
    'paid MGO Codec Pack (proven live 2026-07-29). Bit 1 has no reader on this build. Defaults to '
    '0: paid content is granted per account, never inherited. Read per request, so an UPDATE '
    'applies on the next character-list fetch with no restart.';
