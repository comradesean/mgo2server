-- Bans, so -541 has something to enforce.
--
-- The client already has the sentence and accepts the code on BOTH halves of play: 0x4321 (join)
-- and 0x4311 (the host's settings check, which precedes create). One value covers hosting and
-- joining, so one column does too. [ELF 2026-07-29, code -541 -> disc string 22583,
-- "You are currently banned from creating and joining games."]
--
-- OPERATOR POLICY: there is no in-game way to set this and there is not meant to be. An operator
-- writes the timestamp directly. NULL means not banned; a timestamp in the future means banned
-- until then; a timestamp in the past has simply expired and needs no cleanup job.
--
-- Deliberately on ACCOUNT rather than CHARA. A ban that a player can walk away from by switching
-- character is not a ban, and the client's own sentence says "You are", not "This character is".
alter table account add column banned_until timestamptz;

comment on column account.banned_until is
	'Operator-set play ban. NULL = not banned; future timestamp = banned until then. Enforced on '
	'0x4321 (join) and 0x4311 (host settings check) with result -541, which the client renders as '
	'"You are currently banned from creating and joining games."';
