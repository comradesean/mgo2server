-- Player mail: what 0x4800 sends, what 0x4820 lists, and what 0x4840 opens.
--
-- Wire-derived model (2026-07-26). The 0x4800 send carries {u8 recipient_count, 8 x char[16]
-- recipient names, char[128] subject, char[708] body, 2 unmapped bytes} — 967 bytes, confirmed
-- against a live BLUS30109 capture where the operator's three typed strings landed exactly on the
-- three blocks (dev/proto/blanks/inbound/mgo2_cmd_4800_c2s.ksy). One send therefore fans out to
-- up to eight rows here, one per recipient, which is why the recipient is a column rather than
-- the mail being shared.
--
-- Column widths follow the wire, not taste: 16 for a name, 128 for the subject, 708 for the body.
-- The client cannot express more and truncating on the way in would be a silent edit of what the
-- player wrote.
--
-- The sender is stored BOTH as an id and as the name at the time of sending. The id is the honest
-- link; the name is what the 0x4822 list entry has to show, and a character can be deleted or
-- renamed while its mail sits in someone's mailbox. Keeping the name means a deleted sender's
-- letters still render instead of vanishing or crashing the list.
CREATE TABLE IF NOT EXISTS public.mail
(
    id bigint GENERATED ALWAYS AS IDENTITY,
    -- Whose mailbox this row is in.
    recipient_chara_id bigint NOT NULL,
    -- Null once the sending character is gone; sender_name is what the list actually displays.
    sender_chara_id bigint,
    sender_name character varying(16) NOT NULL,
    subject character varying(128) NOT NULL DEFAULT '',
    body character varying(708) NOT NULL DEFAULT '',
    -- Served as the 0x4822 u32 "time", which the client widens to 64 bits on store — the same
    -- time_t-shaped widening 0x4902's open/close times get. Unix seconds.
    sent_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- The 0x4822 trailing bytes carry tier-4 names "important" and "read" and are unverified, so
    -- this column exists to be served into one of them once that is settled. Nothing sets it yet.
    is_read boolean NOT NULL DEFAULT false,
    CONSTRAINT mail_pkey PRIMARY KEY (id),
    CONSTRAINT mail_recipient_fkey FOREIGN KEY (recipient_chara_id)
        REFERENCES public.chara (id) ON DELETE CASCADE,
    CONSTRAINT mail_sender_fkey FOREIGN KEY (sender_chara_id)
        REFERENCES public.chara (id) ON DELETE SET NULL
);

-- The only read pattern: one character's mailbox, newest first. The 0x4822 index byte is the
-- position in this ordering, so the order has to be stable.
CREATE INDEX IF NOT EXISTS mail_recipient_idx
    ON public.mail (recipient_chara_id, sent_at DESC, id DESC);
