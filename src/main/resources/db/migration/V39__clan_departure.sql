-- When a character last stopped being in a clan.
--
-- The client carries the sentence "A fixed amount of time must pass in order to apply to join a
-- clan." (dialog 24137), which is the same family as the disband, character-delete and emblem
-- cooldowns. It cannot compute any of them — those countdown strings are orphaned in this build —
-- so if the wait is to exist at all, the server is the only thing that can enforce it, and the
-- server needs a departure timestamp to enforce it from.
--
-- OPERATOR POLICY, and note it is policy twice over. That a wait exists is the game's own text;
-- the length of it is our choice (MGO2SERVER_CLAN_JOIN_COOLDOWN_HOURS), and so is the decision to
-- measure it from *departure* rather than from the last application. Departure is the reading
-- that matches the rest of the family — every other cooldown here is "you recently did X, wait
-- before undoing it" — but nothing in the binary states which it is, because nothing in the
-- binary checks it.
--
-- Kept on chara rather than on clan_member because the row it describes has been deleted: leaving
-- a clan removes the membership, so a column there would go with it.
alter table chara add column clan_left_at timestamptz;

comment on column chara.clan_left_at is
	'When this character last left a clan; NULL if it never has. Drives the apply-to-join cooldown.';
