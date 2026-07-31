-- The tips are NOT news.
--
-- V36 put the character-select and Personal Data tip text into `news`, on the reading that the
-- news list fed the tip panel. It does not: the tips are HTTP documents the client fetches per
-- screen as /us/mgo2/help/<screen>_<page>.txt, which is why the panel still showed the probe's
-- fallback stub after V36 replaced every news row.
--
-- News is news. This puts back the single announcement row the dev seed used to create.
delete from news;

insert into news (important, title, body)
values (true, 'mgo2server', 'Test server online.');
