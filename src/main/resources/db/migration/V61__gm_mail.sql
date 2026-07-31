-- Letters addressed to the Game Master.
--
-- IDENTIFIED 2026-07-29, ELF plus a live send. Mail -> Create New Mail -> To -> GM produces an
-- ordinary 967-byte 0x4800 with NO recipient: the count byte at wire 0x000 is zero and all eight
-- 16-byte name slots are zeroed. The destination is carried by a single byte at wire 0x3C5, which
-- reads 3 for the Game Master and 0 otherwise.
--
-- The client writes it at 0x8EEAA8 (`li r0,3 ; stb r0,272(r11)`), reached only when bit 18 of the
-- compose screen's flags word at screen+372 is set -- the same bit that greys out the
-- "View/Edit Address Book" row, confirmed live, because a GM letter has no recipient list to edit.
--
-- Bit EIGHTEEN, not 17: `rldicl. r9,r0,46,63` tests bit 64-46. Two independent traces read it as
-- 17 before the rotate arithmetic was checked, and 17 is a real but unrelated flag (the
-- message-body editor), which is why the wrong label kept half-fitting.
--
-- Bit 18 is set only by the GM menu item (0x8EF098, dispatch case 3) and by the already-addressed
-- screen-entry arm (0x8E6ECC), and is cleared by every other To-menu item and by the send. It is
-- NOT cleared by leaving the screen, so picking GM and backing out leaves it set.
-- The value set is {0, 3}: there is no 1 or 2 arm, and friend/clan recipients travel the ordinary
-- named path, so nothing else on the wire distinguishes them.
--
-- WHY THIS TABLE RATHER THAN A ROW IN mail. Every column of `mail` is about delivery between two
-- characters -- recipient_chara_id is NOT NULL, and read/deleted flags exist for both ends. A GM
-- letter has no recipient character and no reply path in the protocol, so forcing it into that
-- shape would mean inventing a fake recipient. It is operator correspondence, not player mail.
--
-- WHAT THIS FIXES. Until now a GM letter was parsed as "0 of 0 recipients delivered" and answered
-- SUCCESS, so the player was told it sent and nothing was stored anywhere. That is the
-- success-on-a-no-op pattern this project has removed several times already.

CREATE TABLE public.gm_mail
(
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sender_chara_id bigint      NOT NULL REFERENCES public.chara (id) ON DELETE CASCADE,
    sender_name     character varying(16)  NOT NULL,
    subject         character varying(128) NOT NULL DEFAULT '',
    body            character varying(708) NOT NULL DEFAULT '',
    sent_at         timestamptz NOT NULL DEFAULT now(),
    -- Operator workflow. There is no in-game reply path -- the client cannot be sent a GM letter
    -- by any command we have identified -- so "handled" is a note to whoever reads these, not
    -- anything the player ever sees.
    handled         boolean     NOT NULL DEFAULT false
);

CREATE INDEX gm_mail_unhandled_idx ON public.gm_mail (sent_at DESC) WHERE NOT handled;
