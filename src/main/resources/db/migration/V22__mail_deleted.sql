-- Per-side deletion for mail.
--
-- One row is one delivery, read from both ends: the recipient sees it in their inbox
-- (0x4822 category "inbox") and the sender sees the same row in Sent. Deleting is therefore not
-- a row delete — the client's 0x4880 says "remove this from the list I am looking at", and doing
-- that literally would take the letter out of the other party's mailbox too.
--
-- So each end gets its own flag, and the row is deleted only once neither end can see it.
ALTER TABLE public.mail
    ADD COLUMN IF NOT EXISTS recipient_deleted boolean NOT NULL DEFAULT false;

ALTER TABLE public.mail
    ADD COLUMN IF NOT EXISTS sender_deleted boolean NOT NULL DEFAULT false;
