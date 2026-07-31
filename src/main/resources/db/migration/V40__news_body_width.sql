-- Narrow news.body to what the client can actually hold.
--
-- 886 was never a client limit. It was the padding width the server used to reach a 1023-byte
-- payload, and it leaked into the schema as though it were a field size. The real limit is the
-- client's per-entry body buffer: each news table entry is 920 bytes with the body at offset 145,
-- leaving 775 including the terminator, so 774 characters.
--
-- The distinction matters because 0xD5CE34 bounds only its SOURCE (pos+i <= 1023) and never its
-- destination. A body between 775 and 886 characters would have been accepted by this column and
-- would overrun a stack temporary in the client. NewsGameController caps it, so nothing can reach
-- the wire over-length; this makes the schema stop inviting text that the cap would silently cut.
--
-- Protocol, not policy: 774 is read out of the binary, not chosen.
alter table news alter column body type varchar(774);

comment on column news.body is
	'Max 774: the client''s per-entry body buffer is 775 bytes including its NUL terminator';
