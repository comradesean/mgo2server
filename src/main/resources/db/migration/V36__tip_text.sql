-- The tips shown on the character-select and Personal Data screens.
--
-- These are news rows: the gate sends every row of `news` in one list (0x2009/0x200a) and the
-- client draws them as the tip panel. The page markers ("Page 1/3") are part of the text the server
-- supplies, not something the client adds, which is why each page is its own row.
--
-- What was here before was twelve copies of "mgo2server / Test server online." — the dev seed has
-- no conflict target, so every run of it added another. This replaces the lot with the real text.
delete from news;

insert into news (important, title, body) values
(true, 'REGISTER CHARACTER',
'Before you can begin playing the game,
you need to create your character.
                Page 1/3'),
(true, 'REGISTER CHARACTER',
'This will be your alter ego in
the METAL GEAR ONLINE world,
so think carefully about what kind of
character you want.
                Page 2/3'),
(true, 'REGISTER CHARACTER',
'When you are ready, select
Register New Character and
follow the on-screen instruction.
                Page 3/3'),
(true, 'PERSONAL DATA',
'This is your Personal Data.

Here you can view and
adjust settings related to your character.
                Page 1/3'),
(true, 'PERSONAL DATA',
'You can set skills, player options,
and gear settings,
and also view your record and friends.
                Page 2/3'),
(true, 'PERSONAL DATA',
'You can set skills and play options at
the start of a game as well,
but there is a time limit.
This is a good place to become familiar
with what kinds of options are available.
                Page 3/3');
