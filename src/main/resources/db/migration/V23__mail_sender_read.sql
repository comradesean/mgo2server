-- Read state is per-side, for the same reason deletion is (V22): one row is a single delivery
-- seen from both ends, and the 0x4822 entry carries a read byte in BOTH lists.
--
-- Without this, a sender opening their own letter in Sent would mark the recipient's copy read
-- and clear the recipient's "new mail" badge for a letter they never saw.
--
-- The existing is_read column keeps its meaning: the RECIPIENT's read state, which is the one
-- the client's unread counters act on (0 = unread, tallied at 0x8E5298 / 0x8F0638 / 0x8F08E8).
ALTER TABLE public.mail
    ADD COLUMN IF NOT EXISTS sender_read boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.mail.is_read IS
    'Recipient read state, served as the 0x4822 read byte (wire 0x109) in the inbox list.';

COMMENT ON COLUMN public.mail.sender_read IS
    'Sender read state, served as the 0x4822 read byte in the Sent list.';
